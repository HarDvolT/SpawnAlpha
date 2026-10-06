#include "local_transcription.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <winrt/base.h>
#include <whisper.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <thread>

namespace {
using winrt::com_ptr;
using winrt::check_hresult;
constexpr DWORD kAudio = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
constexpr int kRate = WHISPER_SAMPLE_RATE;
constexpr size_t kMaxSamples = kRate * 60 * 15;
void SilentLog(enum ggml_log_level, const char*, void*) {}
bool Abort(void* value) { return static_cast<std::atomic<bool>*>(value)->load(); }
void CheckCancel(std::atomic<bool>& cancel) {
  if (cancel.load()) throw std::runtime_error("Transcription cancelled");
}
void CheckLocalFile(const std::wstring& value) {
  const std::filesystem::path path(value);
  const auto drive = path.root_name().wstring();
  if (!path.is_absolute() || drive.size() != 2 || drive[1] != L':' ||
      value.find(L"://") != std::wstring::npos) {
    throw std::runtime_error("A local file is required");
  }
  const auto kind = GetDriveTypeW(path.root_path().c_str());
  if (kind != DRIVE_FIXED && kind != DRIVE_REMOVABLE) {
    throw std::runtime_error("A local file is required");
  }
  for (auto current = path; !current.empty();) {
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
      throw std::runtime_error("A local file is required");
    }
    const auto parent = current.parent_path();
    if (parent == current) break;
    current = parent;
  }
}

// A wide-path loader avoids Windows' narrow fopen path corruption. The library
// owns the close callback, including model load failure.
size_t ModelRead(void* value, void* output, size_t size) {
  return fread(output, 1, size, static_cast<FILE*>(value));
}
bool ModelEof(void* value) { return feof(static_cast<FILE*>(value)) != 0; }
void ModelClose(void* value) { fclose(static_cast<FILE*>(value)); }

std::vector<float> Decode(const std::wstring& path, std::atomic<bool>& cancel) {
  com_ptr<IMFSourceReader> reader;
  check_hresult(MFCreateSourceReaderFromURL(path.c_str(), nullptr, reader.put()));
  check_hresult(reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE));
  check_hresult(reader->SetStreamSelection(kAudio, TRUE));
  com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
  check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kRate));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 32));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, sizeof(float)));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, kRate * sizeof(float)));
  check_hresult(reader->SetCurrentMediaType(kAudio, nullptr, type.get()));
  std::vector<float> pcm;
  for (;;) {
    CheckCancel(cancel);
    DWORD flags = 0; LONGLONG timestamp = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kAudio, 0, nullptr, &flags, &timestamp, sample.put()));
    if (flags & (MF_SOURCE_READERF_ERROR | MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED)) {
      throw std::runtime_error("Audio format changed");
    }
    if (sample) {
      com_ptr<IMFMediaBuffer> buffer;
      check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
      BYTE* bytes = nullptr; DWORD length = 0;
      check_hresult(buffer->Lock(&bytes, nullptr, &length));
      // Copy before any operation that could throw; always release the lock.
      std::vector<float> packet;
      try {
        if (length % sizeof(float)) throw std::runtime_error("Invalid audio packet");
        const auto data = reinterpret_cast<const float*>(bytes);
        packet.assign(data, data + length / sizeof(float));
      } catch (...) { buffer->Unlock(); throw; }
      check_hresult(buffer->Unlock());
      // Preserve the take clock, including initial gaps and AAC preroll. Never
      // concatenate packet gaps or subtract the first decoded timestamp.
      if (timestamp > static_cast<int64_t>(kMaxSamples) * 10000000 / kRate ||
          timestamp < -10000000) throw std::runtime_error("Audio exceeds check limit");
      const int64_t offset = static_cast<int64_t>(std::llround(
          static_cast<double>(timestamp) * kRate / 10000000));
      const size_t trim = static_cast<size_t>(std::max<int64_t>(0, -offset));
      const size_t start = static_cast<size_t>(std::max<int64_t>(0, offset));
      if (trim < packet.size()) {
        const size_t count = packet.size() - trim;
        if (start > kMaxSamples || count > kMaxSamples - start) {
          throw std::runtime_error("Audio exceeds check limit");
        }
        pcm.resize(std::max(pcm.size(), start + count), 0);
        for (size_t i = 0; i < count; ++i) {
          const float value = packet[trim + i];
          if (!std::isfinite(value)) throw std::runtime_error("Invalid audio sample");
          pcm[start + i] = std::clamp(value, -1.0f, 1.0f);
        }
      }
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  if (pcm.empty()) throw std::runtime_error("No audio to transcribe");
  return pcm;
}
}

std::vector<float> DecodeLocalSpeechAudio(const std::wstring& media,
    std::atomic<bool>& cancel) {
  CheckCancel(cancel); CheckLocalFile(media);
  return Decode(media, cancel);
}

LocalTranscript TranscribeLocal(const std::wstring& model,
    const std::wstring& media, const std::string& language,
    const std::string& vocabulary, std::atomic<bool>& cancel) {
  if (language != "en" && language != "fr" && language != "ar") {
    throw std::runtime_error("Unsupported speech language");
  }
  if (vocabulary.size() > 8192) throw std::runtime_error("Vocabulary exceeds check limit");
  // Upstream logging can contain text/path fragments. Disable it globally
  // before model load, not just realtime transcript printing.
  whisper_log_set(SilentLog, nullptr); ggml_log_set(SilentLog, nullptr);
  CheckCancel(cancel);
  CheckLocalFile(model);
  auto pcm = DecodeLocalSpeechAudio(media, cancel);
  CheckCancel(cancel);
  auto context_params = whisper_context_default_params();
  context_params.use_gpu = false;
  FILE* file = nullptr;
  if (_wfopen_s(&file, model.c_str(), L"rb") || !file) {
    throw std::runtime_error("Offline speech model unavailable");
  }
  whisper_model_loader loader{file, ModelRead, ModelEof, ModelClose};
  using Context = std::unique_ptr<whisper_context, decltype(&whisper_free)>;
  Context context(whisper_init_with_params(&loader, context_params), whisper_free);
  if (!context) throw std::runtime_error("Offline speech model unavailable");
  if (!whisper_is_multilingual(context.get())) {
    throw std::runtime_error("A multilingual speech model is required");
  }
  CheckCancel(cancel);
  auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.n_threads = static_cast<int>(std::clamp(std::thread::hardware_concurrency(), 1u, 8u));
  params.language = language.c_str(); params.translate = false;
  params.initial_prompt = vocabulary.empty() ? nullptr : vocabulary.c_str();
  params.token_timestamps = true; params.split_on_word = true;
  params.print_realtime = false; params.print_progress = false;
  params.print_timestamps = false; params.print_special = false;
  params.no_context = true; params.vad = false;
  params.abort_callback = Abort; params.abort_callback_user_data = &cancel;
  if (whisper_full(context.get(), params, pcm.data(), static_cast<int>(pcm.size())) != 0) {
    CheckCancel(cancel); throw std::runtime_error("Offline transcription failed");
  }
  CheckCancel(cancel);
  LocalTranscript result;
  result.duration_us = static_cast<int64_t>(pcm.size()) * 1000000 / kRate;
  const int segments = whisper_full_n_segments(context.get());
  for (int segment = 0; segment < segments; ++segment) {
    for (int token = 0; token < whisper_full_n_tokens(context.get(), segment); ++token) {
      const auto data = whisper_full_get_token_data(context.get(), segment, token);
      if (data.id >= whisper_token_eot(context.get())) continue;
      const char* text = whisper_full_get_token_text(context.get(), segment, token);
      if (!text) throw std::runtime_error("Invalid speech output");
      // Use getters, which also remain correct if VAD is enabled later.
      const auto start = whisper_full_get_token_t0(context.get(), segment, token) * 10000;
      const auto end = whisper_full_get_token_t1(context.get(), segment, token) * 10000;
      if (start < 0 || end < start || !std::isfinite(data.p)) {
        throw std::runtime_error("Invalid speech timing");
      }
      result.pieces.push_back({text, std::min(start, result.duration_us),
          std::min(end, result.duration_us), std::clamp(data.p, 0.0f, 1.0f)});
      if (result.pieces.size() > 100000) throw std::runtime_error("Speech output exceeds check limit");
    }
  }
  return result;
}

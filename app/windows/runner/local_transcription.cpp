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
#include <propvarutil.h>
#include <bcrypt.h>
#include <fstream>
#include <array>

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

std::vector<float> Decode(const std::wstring& path, std::atomic<bool>& cancel,
    int64_t window_start_us = 0, size_t maximum = kMaxSamples, bool windowed = false) {
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
  if (window_start_us) {
    PROPVARIANT position{};
    check_hresult(InitPropVariantFromInt64(window_start_us * 10, &position));
    const auto seek = reader->SetCurrentPosition(GUID_NULL, position);
    PropVariantClear(&position); check_hresult(seek);
  }
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
      const int64_t relative = timestamp - window_start_us * 10;
      if (!windowed && (relative > static_cast<int64_t>(maximum) * 10000000 / kRate ||
          relative < -10000000)) throw std::runtime_error("Audio exceeds check limit");
      if (windowed && relative >= static_cast<int64_t>(maximum) * 10000000 / kRate) break;
      const int64_t offset = static_cast<int64_t>(std::llround(
          static_cast<double>(relative) * kRate / 10000000));
      const size_t trim = static_cast<size_t>(std::max<int64_t>(0, -offset));
      const size_t start = static_cast<size_t>(std::max<int64_t>(0, offset));
      if (trim < packet.size()) {
        size_t count = packet.size() - trim;
        if (windowed) count = std::min(count, maximum - std::min(start, maximum));
        if (start > maximum || count > maximum - start) {
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
  if (pcm.empty() && !windowed) throw std::runtime_error("No audio to transcribe");
  return pcm;
}
}  // namespace

bool VerifyLocalSpeechModel(const std::wstring& path, std::atomic<bool>& cancel) {
  CheckCancel(cancel); CheckLocalFile(path);
  if (std::filesystem::file_size(path) != 147951465) return false;
  BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_HASH_HANDLE hash = nullptr;
  auto cleanup = [&] { if (hash) BCryptDestroyHash(hash); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); };
  try {
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0 ||
        BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) < 0) throw std::runtime_error("Model verification unavailable");
    std::ifstream input(std::filesystem::path(path), std::ios::binary);
    if (!input) throw std::runtime_error("Model verification unavailable");
    std::array<char, 65536> buffer{};
    while (input) {
      CheckCancel(cancel); input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
      if (input.gcount() && BCryptHashData(hash, reinterpret_cast<PUCHAR>(buffer.data()), static_cast<ULONG>(input.gcount()), 0) < 0) {
        throw std::runtime_error("Model verification unavailable");
      }
    }
    if (!input.eof()) throw std::runtime_error("Model verification unavailable");
    std::array<unsigned char, 32> digest{};
    if (BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) < 0) throw std::runtime_error("Model verification unavailable");
    cleanup(); algorithm = nullptr; hash = nullptr;
    constexpr unsigned char expected[] = {0x60,0xed,0x5b,0xc3,0xdd,0x14,0xee,0xa8,0x56,0x49,0x3d,0x33,0x43,0x49,0xb4,0x05,0x78,0x2d,0xdc,0xaf,0x00,0x28,0xd4,0xb5,0xdf,0x40,0x88,0x34,0x5f,0xba,0x2e,0xfe};
    return std::equal(digest.begin(), digest.end(), std::begin(expected));
  } catch (...) { cleanup(); throw; }
}

std::vector<LocalSpeechWindow> TranscribeLocalWindows(const std::wstring& model,
    const std::wstring& media, const std::string& language,
    const std::string& vocabulary, int64_t duration_us,
    std::atomic<bool>& cancel, const std::function<void(double)>& progress) {
  if ((language != "en" && language != "fr" && language != "ar") || vocabulary.size() > 8192 ||
      duration_us <= 0 || duration_us > 24LL * 60 * 60 * 1000000) throw std::runtime_error("Invalid speech request");
  whisper_log_set(SilentLog, nullptr); ggml_log_set(SilentLog, nullptr);
  CheckLocalFile(media);
  if (!VerifyLocalSpeechModel(model, cancel)) throw std::runtime_error("Offline model verification failed");
  auto context_params = whisper_context_default_params(); context_params.use_gpu = false;
  context_params.flash_attn = false;
  context_params.dtw_token_timestamps = true;
  context_params.dtw_aheads_preset = WHISPER_AHEADS_BASE;
  FILE* file = nullptr;
  if (_wfopen_s(&file, model.c_str(), L"rb") || !file) throw std::runtime_error("Offline speech model unavailable");
  whisper_model_loader loader{file, ModelRead, ModelEof, ModelClose};
  using Context = std::unique_ptr<whisper_context, decltype(&whisper_free)>;
  Context context(whisper_init_with_params(&loader, context_params), whisper_free);
  if (!context || !whisper_is_multilingual(context.get())) throw std::runtime_error("Multilingual model unavailable");
  auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.n_threads = static_cast<int>(std::clamp(std::thread::hardware_concurrency(), 1u, 8u));
  params.language = language.c_str(); params.translate = false;
  params.initial_prompt = vocabulary.empty() ? nullptr : vocabulary.c_str();
  params.token_timestamps = true; params.split_on_word = true;
  params.print_realtime = false; params.print_progress = false;
  params.print_timestamps = false; params.print_special = false;
  params.no_context = true; params.vad = false;
  params.abort_callback = Abort; params.abort_callback_user_data = &cancel;
  std::vector<LocalSpeechWindow> result;
  size_t total_pieces = 0;
  constexpr int64_t core = 26000000, overlap = 2000000;
  for (int64_t cursor = 0; cursor < duration_us; cursor += core) {
    CheckCancel(cancel);
    const auto start = std::max<int64_t>(0, cursor - overlap);
    const auto end = std::min(duration_us, cursor + core + overlap);
    const auto samples = static_cast<size_t>((end - start) * kRate / 1000000);
    auto pcm = Decode(media, cancel, start, samples, true);
    LocalSpeechWindow window;
    window.offset_us = start; window.keep_start_us = cursor; window.keep_end_us = std::min(cursor + core, duration_us);
    window.transcript.duration_us = static_cast<int64_t>(pcm.size()) * 1000000 / kRate;
    // An overlap is unnecessary when the seam lies in digital silence. Keep
    // the neighbouring utterance in its own core instead of feeding a partial
    // sentence to this window. Never gate ordinary room tone or quiet speech.
    auto silent_seam = [&](size_t sample) {
      constexpr size_t radius = kRate / 50;
      if (sample < radius || sample + radius > pcm.size()) return false;
      return std::all_of(pcm.begin() + sample - radius, pcm.begin() + sample + radius,
          [](float value) { return std::abs(value) <= 1e-5f; });
    };
    size_t first = 0, last = pcm.size();
    const auto left = static_cast<size_t>((cursor - start) * kRate / 1000000);
    const auto right = static_cast<size_t>((window.keep_end_us - start) * kRate / 1000000);
    if (silent_seam(left)) first = left;
    if (silent_seam(right)) last = right;
    // Remove only effectively zero lead/tail samples, leaving 200ms context.
    // Their offset is added back to every timestamp; the take clock never moves.
    constexpr size_t padding = kRate / 5;
    auto voiced_first = first, voiced_last = last;
    while (voiced_first < voiced_last && std::abs(pcm[voiced_first]) <= 1e-5f) ++voiced_first;
    while (voiced_last > voiced_first && std::abs(pcm[voiced_last - 1]) <= 1e-5f) --voiced_last;
    first = voiced_first > first + padding ? voiced_first - padding : first;
    last = std::min(last, voiced_last + padding);
    const int64_t audio_offset_us = static_cast<int64_t>(first) * 1000000 / kRate;
    double energy = 0;
    for (size_t sample = first; sample < last; ++sample) energy += static_cast<double>(pcm[sample]) * pcm[sample];
    // Silence has no words. Do not give the vocabulary prompt a silent window.
    if (last > first && energy / static_cast<double>(last - first) > 1e-8) {
      if (whisper_full(context.get(), params, pcm.data() + first, static_cast<int>(last - first)) != 0) {
        CheckCancel(cancel); throw std::runtime_error("Offline speech failed");
      }
      CheckCancel(cancel);
      struct TimedToken { std::string text; int64_t start, end; float probability; };
      std::vector<TimedToken> aligned;
      for (int segment = 0; segment < whisper_full_n_segments(context.get()); ++segment) {
        for (int token = 0; token < whisper_full_n_tokens(context.get(), segment); ++token) {
          const auto data = whisper_full_get_token_data(context.get(), segment, token);
          if (data.id >= whisper_token_eot(context.get())) continue;
          const char* text = whisper_full_get_token_text(context.get(), segment, token);
          // Attention alignment places actual recognised tokens on the audio.
          // Use successive aligned boundaries, never equal word distribution.
          const auto t0 = data.t_dtw * 10000 + audio_offset_us;
          const auto t1 = whisper_full_get_segment_t1(context.get(), segment) * 10000 + audio_offset_us;
          if (!text || t0 < 0 || t1 < t0 || !std::isfinite(data.p)) throw std::runtime_error("Invalid speech timing");
          aligned.push_back({text, std::min(t0, window.transcript.duration_us),
              std::min(t1, window.transcript.duration_us), std::clamp(data.p, 0.0f, 1.0f)});
          if (++total_pieces > 100000) throw std::runtime_error("Speech output capacity reached");
        }
      }
      for (size_t token = 0; token < aligned.size(); ++token) {
        const auto& value = aligned[token];
        const auto boundary = token + 1 < aligned.size() ? std::min(value.end, aligned[token + 1].start) : value.end;
        if (boundary < value.start) throw std::runtime_error("Invalid speech timing");
        window.transcript.pieces.push_back({value.text, value.start, boundary, value.probability});
      }
    }
    result.push_back(std::move(window));
    progress(static_cast<double>(std::min(cursor + core, duration_us)) / static_cast<double>(duration_us));
  }
  return result;
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

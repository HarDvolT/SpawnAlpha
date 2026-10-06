// Generated media only. Reuse our bounded fixture generator/decoder helpers.
#define wmain RenderRiskCheckEntry
#include "render_core_check.cpp"
#undef wmain
#include "../local_render.h"
#include "../recording_probe.h"
#include <fstream>
#include <filesystem>

void GenerateExtra(ID3D11Device* device, const std::wstring& path, UINT channels, UINT rate, uint32_t color) {
  GpuVideoWriter writer;
  check_hresult(writer.Start(device, path, kWidth, kHeight, 30, channels ? GpuAudioFormat{rate, channels} : GpuAudioFormat{}));
  std::vector<uint32_t> pixels(kWidth * kHeight, color);
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = kWidth; desc.Height = kHeight; desc.MipLevels = 1; desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  D3D11_SUBRESOURCE_DATA data{pixels.data(), kWidth * 4, 0}; com_ptr<ID3D11Texture2D> texture;
  check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
  for (UINT frame = 0; frame < 30; ++frame) {
    check_hresult(writer.WriteFrame(texture.get(), kWidth, kHeight, frame * kSecond / 30));
    if (!channels) continue;
    std::vector<int16_t> pcm(rate / 30 * channels);
    for (UINT index = 0; index < rate / 30; ++index) for (UINT ch = 0; ch < channels; ++ch) {
      const double hz = ch == 0 ? 330.0 : 990.0;
      pcm[index * channels + ch] = static_cast<int16_t>(std::sin((frame * (rate / 30) + index) * hz * 6.283185307179586 / rate) * 12000);
    }
    check_hresult(writer.WriteAudio(pcm.data(), rate / 30, frame * kSecond / 30));
  }
  check_hresult(writer.Finish());
}

void VerifyStereo(const std::wstring& path) {
  com_ptr<IMFSourceReader> reader; check_hresult(MFCreateSourceReaderFromURL(path.c_str(), nullptr, reader.put()));
  com_ptr<IMFMediaType> type; check_hresult(reader->GetNativeMediaType(kAudioStream, 0, type.put()));
  UINT channels = 0; check_hresult(type->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels)); Require(channels == 2);
  type = nullptr; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio)); check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16)); check_hresult(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kRate)); check_hresult(reader->SetCurrentMediaType(kAudioStream, nullptr, type.get()));
  std::vector<int16_t> left(kRate * 2), right(kRate * 2);
  while (true) {
    DWORD flags = 0; int64_t time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kAudioStream, 0, nullptr, &flags, &time, sample.put()));
    if (sample) {
      com_ptr<IMFMediaBuffer> buffer; check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
      BYTE* bytes = nullptr; DWORD length = 0; check_hresult(buffer->Lock(&bytes, nullptr, &length));
      const auto start = std::max<int64_t>(0, time * kRate / kSecond);
      const DWORD count = length / 4;
      bool valid = start + count <= static_cast<int64_t>(left.size()) && length % 4 == 0;
      if (valid) for (DWORD i = 0; i < count; ++i) {
        left[start + i] = reinterpret_cast<const int16_t*>(bytes)[i * 2];
        right[start + i] = reinterpret_cast<const int16_t*>(bytes)[i * 2 + 1];
      }
      check_hresult(buffer->Unlock()); Require(valid);
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  Require(ToneAt(left, 12000, 330) > 9000 && ToneAt(left, 12000, 990) < 1500);
  Require(ToneAt(right, 12000, 990) > 9000 && ToneAt(right, 12000, 330) < 1500);
}

void VerifyLocalCut(const LocalRenderRequest& request, int expected_frames, int64_t expected_us, bool early_camera = false) {
  std::atomic<bool> cancel{false}; const auto probe = ProbeRecording(request.output, cancel);
  Require(probe.readable && probe.width == static_cast<int>(request.width) && probe.height == static_cast<int>(request.height));
  Require(std::abs(probe.duration_100ns - expected_us * 10) < 100000);
  com_ptr<IMFAttributes> attributes; check_hresult(MFCreateAttributes(attributes.put(), 1));
  check_hresult(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
  com_ptr<IMFSourceReader> reader; check_hresult(MFCreateSourceReaderFromURL(request.output.c_str(), attributes.get(), reader.put()));
  com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)); check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
  check_hresult(reader->SetCurrentMediaType(kVideoStream, nullptr, type.get()));
  int frames = 0; int64_t previous = -1, end = 0;
  while (true) {
    DWORD flags = 0; int64_t time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kVideoStream, 0, nullptr, &flags, &time, sample.put()));
    if (sample) {
      Require(time > previous && std::abs(time - static_cast<int64_t>(frames) * kSecond / 30) <= 10000);
      int64_t duration = 0; check_hresult(sample->GetSampleDuration(&duration)); end = time + duration;
      previous = time;
      com_ptr<IMFMediaBuffer> buffer; check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
      BYTE* bytes = nullptr; DWORD length = 0; check_hresult(buffer->Lock(&bytes, nullptr, &length));
      const size_t center = (request.height / 2 * request.width + request.width / 2) * 4;
      int64_t offset_us = static_cast<int64_t>(frames) * 1000000 / 30, source = 0;
      for (const auto& range : request.ranges) {
        const auto length_us = range.end_us - range.start_us;
        if (offset_us < length_us) { source = range.start_us + offset_us; break; }
        offset_us -= length_us;
      }
      bool valid = length >= static_cast<size_t>(request.width) * request.height * 4;
      if (valid && expected_us == 2000000) valid = source / 1000000 == 1 ? bytes[center] > bytes[center + 2] + 80 : bytes[center + 2] > bytes[center] + 80;
      if (valid && request.height > request.width) {
        // Full-picture fit keeps all screen content; the unused margin stays black.
        valid = bytes[0] < 20 && bytes[1] < 20 && bytes[2] < 20;
      }
      if (valid && early_camera) {
        const size_t inset = (request.height * 82 / 100 * request.width + request.width * 84 / 100) * 4;
        valid = frames < 30 ? bytes[inset + 1] > bytes[inset] + 80 && bytes[inset + 1] > bytes[inset + 2] + 80
                            : bytes[inset] > bytes[inset + 2] + 80;
      }
      check_hresult(buffer->Unlock()); Require(valid); ++frames;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  Require(frames == expected_frames && std::abs(end - expected_us * 10) <= 10000);
}
int wmain(int count, wchar_t** args) {
  if (count != 2) return 2;
  const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED); if (FAILED(com)) return 3;
  const char* stage = "initialize";
  try {
    check_hresult(MFStartup(MF_VERSION));
    {
      com_ptr<ID3D11Device> device;
      check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
        nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, nullptr));
      const std::wstring prefix(args[1]), source = prefix + L"-source.mp4";
      stage = "generate"; Generate(device.get(), source);
      LocalRenderRequest request{source, source, prefix + L"-pair.mp4", 4000000, 640, 360, {{1000000, 2000000}, {3000000, 4000000}}};
      request.camera_inset = .28; request.camera_margin = .04;
      std::atomic<bool> cancel{false};
      stage = "render streaming pair"; RenderLocalVideo(request, cancel, [](double) {});
      stage = "verify pair clock and pixels"; VerifyLocalCut(request, 60, 2000000);
      stage = "verify selected audio"; const auto audio = Audio(request.output);
      Require(ToneAt(audio, 12000, 440) > 9000 && ToneAt(audio, 60000, 880) > 9000);
      Require(ToneAt(audio, 12000, 220) < 1500 && ToneAt(audio, 60000, 660) < 1500);
      request.camera.clear(); request.output = prefix + L"-reorder.mp4"; request.ranges = {{3000000, 4000000}, {1000000, 2000000}};
      stage = "render reordered ranges"; RenderLocalVideo(request, cancel, [](double) {});
      stage = "verify reordered ranges"; VerifyLocalCut(request, 60, 2000000);
      const auto reversed = Audio(request.output);
      Require(ToneAt(reversed, 12000, 880) > 9000 && ToneAt(reversed, 60000, 440) > 9000);
      const auto silent = prefix + L"-silent-source.mp4", stereo = prefix + L"-stereo-source.mp4";
      stage = "generate silent and 44.1 kHz stereo";
      GenerateExtra(device.get(), silent, 0, 0, 0xff30c050);
      GenerateExtra(device.get(), stereo, 2, 44100, 0xff30c050);
      request.source = silent; request.source_duration_us = 1000000; request.ranges = {{0, 1000000}};
      request.output = prefix + L"-silent.mp4";
      stage = "render silent video"; RenderLocalVideo(request, cancel, [](double) {});
      VerifyLocalCut(request, 30, 1000000); Require(!ProbeRecording(request.output, cancel).has_audio);
      request.source = stereo; request.output = prefix + L"-stereo.mp4";
      stage = "render resampled stereo"; RenderLocalVideo(request, cancel, [](double) {});
      stage = "verify separate stereo channels"; VerifyLocalCut(request, 30, 1000000); VerifyStereo(request.output);
      request.source = source; request.source_duration_us = 4000000;
      request.camera = silent; request.output = prefix + L"-early-camera.mp4"; request.ranges = {{0, 2000000}};
      stage = "render partial camera"; RenderLocalVideo(request, cancel, [](double) {});
      stage = "verify inset and camera end"; VerifyLocalCut(request, 60, 2000000, true);
      request.camera.clear();
      request.width = 1080; request.height = 1920; request.output = prefix + L"-portrait.mp4";
      request.ranges = {{1370000, 2137000}, {3359000, 3911000}};
      stage = "render non-frame-aligned portrait"; RenderLocalVideo(request, cancel, [](double) {});
      stage = "verify precise portrait clock"; VerifyLocalCut(request, 40, 1319000);
      request.output = prefix + L"-cancel.mp4";
      stage = "cancel render";
      bool stopped = false;
      try { RenderLocalVideo(request, cancel, [&cancel](double value) { if (value > .2) cancel = true; }); } catch (...) { stopped = true; }
      Require(stopped && GetFileAttributesW(request.output.c_str()) == INVALID_FILE_ATTRIBUTES);
      cancel = false; request.output = source;
      stage = "reject overwrite"; bool rejected = false;
      try { RenderLocalVideo(request, cancel, [](double) {}); } catch (...) { rejected = true; }
      Require(rejected && ProbeRecording(source, cancel).readable);
      const auto damaged = prefix + L"-damaged.mp4";
      { std::ofstream stream(std::filesystem::path(damaged), std::ios::binary); stream << "Generated damaged media"; }
      request.source = damaged; request.output = prefix + L"-failed.mp4";
      stage = "reject damaged media"; rejected = false;
      try { RenderLocalVideo(request, cancel, [](double) {}); } catch (...) { rejected = true; }
      Require(rejected && GetFileAttributesW(request.output.c_str()) == INVALID_FILE_ATTRIBUTES);
    }
    std::cout << "Local render check passed: streaming PCM/GPU pair, source selection/reordering, silent input, stereo resampling, camera inset/end, exact portrait duration, cancel cleanup, damaged input and overwrite protection.\n";
    MFShutdown(); CoUninitialize(); return 0;
  } catch (...) {
    std::cerr << "Local render check failed at " << stage << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    MFShutdown(); CoUninitialize(); return 1;
  }
}

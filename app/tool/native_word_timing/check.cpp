// Explicit local/generated speech fixture only; never prints recognized text.
#include "../../windows/runner/local_transcription.h"
#include "../../windows/runner/gpu_video_writer.h"
#include <mfapi.h>
#include <winrt/base.h>
#include <algorithm>
#include <chrono>
#include <cctype>
#include <cmath>
#include <future>
#include <iostream>
#include <sstream>
#include <stdexcept>

void Require(bool value) { if (!value) throw std::runtime_error("Check failed"); }

void SavePieces(const LocalTranscript& result, const std::wstring& path) {
  std::ostringstream json;
  json << "{\"durationUs\":" << result.duration_us << ",\"pieces\":[";
  bool first = true;
  for (const auto& piece : result.pieces) {
    if (!first) json << ',';
    first = false;
    json << "{\"startUs\":" << piece.start_us << ",\"endUs\":" << piece.end_us
         << ",\"probability\":" << piece.probability << ",\"bytes\":[";
    for (size_t i = 0; i < piece.bytes.size(); ++i) {
      if (i) json << ',';
      json << static_cast<unsigned int>(static_cast<unsigned char>(piece.bytes[i]));
    }
    json << "]}";
  }
  json << "]}";
  const auto output = json.str();
  Require(output.size() < 4000000);
  const auto file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, 0, nullptr);
  Require(file != INVALID_HANDLE_VALUE);
  DWORD written = 0;
  const bool ok = WriteFile(file, output.data(), static_cast<DWORD>(output.size()), &written, nullptr) &&
      written == output.size() && FlushFileBuffers(file);
  CloseHandle(file); Require(ok);
}

void GeneratedVideo(const std::vector<float>& pcm, const std::wstring& path) {
  winrt::com_ptr<ID3D11Device> device; winrt::com_ptr<ID3D11DeviceContext> context;
  winrt::check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT, nullptr, 0,
      D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
  const UINT width = 160, height = 90;
  std::vector<uint32_t> pixels(width * height, 0xff2040e0);
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = width; desc.Height = height; desc.MipLevels = 1; desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1;
  desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  const D3D11_SUBRESOURCE_DATA data{pixels.data(), width * 4, 0};
  winrt::com_ptr<ID3D11Texture2D> texture;
  winrt::check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
  GpuVideoWriter writer;
  winrt::check_hresult(writer.Start(device.get(), path, width, height, 30, {48000, 2}));
  // One half-second gap on either side, stereo/48 kHz AAC, and fixed-rate GPU
  // frames. All speech comes from the local synthetic WAV, never a microphone.
  const size_t count = (pcm.size() + 16000) * 3;
  for (size_t frame = 0; frame * 1600 < count; ++frame) {
    const int64_t time = static_cast<int64_t>(frame) * 10000000 / 30;
    winrt::check_hresult(writer.WriteFrame(texture.get(), width, height, time));
    std::vector<int16_t> stereo(3200);
    for (size_t sample = 0; sample < 1600; ++sample) {
      const int64_t source = static_cast<int64_t>((frame * 1600 + sample) / 3) - 8000;
      const float value = source >= 0 && source < static_cast<int64_t>(pcm.size()) ? pcm[static_cast<size_t>(source)] : 0;
      stereo[sample * 2] = stereo[sample * 2 + 1] = static_cast<int16_t>(std::clamp(value, -1.0f, 1.0f) * 30000);
    }
    winrt::check_hresult(writer.WriteAudio(stereo.data(), 1600, time));
  }
  winrt::check_hresult(writer.Finish());
}

void Verify(const LocalTranscript& result) {
  std::string text;
  int64_t previous = 0;
  for (const auto& piece : result.pieces) {
    Require(piece.start_us >= previous && piece.end_us >= piece.start_us &&
        piece.end_us <= result.duration_us && piece.probability >= 0 && piece.probability <= 1);
    previous = piece.start_us; text += piece.bytes;
  }
  std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return static_cast<char>(tolower(c)); });
  Require(text.find("we launch today") != std::string::npos &&
      text.find("local speech timing test") != std::string::npos);
  Require(result.pieces.size() > 8 && result.duration_us > 2000000);
}
int wmain(int argc, wchar_t* argv[]) {
  if (argc != 4) return 2;
  try {
    winrt::check_hresult(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
    winrt::check_hresult(MFStartup(MF_VERSION));
    {
      std::atomic<bool> cancel{false};
      const auto start = std::chrono::steady_clock::now();
      const auto result = TranscribeLocal(argv[1], argv[2], "en", "", cancel);
      Verify(result);
      const auto elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
      const std::wstring prefix(argv[3]);
      auto pcm = DecodeLocalSpeechAudio(argv[2], cancel);
      GeneratedVideo(pcm, prefix + L"-speech.mp4");
      const auto decoded = DecodeLocalSpeechAudio(prefix + L"-speech.mp4", cancel);
      Require(decoded.size() >= pcm.size() + 15000);
      double energy = 0;
      for (size_t i = 0; i < 5600; ++i) energy += decoded[i] * decoded[i];
      Require(std::sqrt(energy / 5600) < .005);
      const auto from_video = TranscribeLocal(argv[1], prefix + L"-speech.mp4", "en", "", cancel);
      Verify(from_video);
      SavePieces(from_video, prefix + L"-pieces.json");
      auto interrupted = std::async(std::launch::async, [&]() {
        try { TranscribeLocal(argv[1], argv[2], "en", "", cancel); return false; }
        catch (...) { return true; }
      });
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
      cancel = true;
      Require(interrupted.get());
      cancel = false;
      for (const auto* remote : {L"https://example.invalid/private.wav", L"\\\\example.invalid\\share\\private.wav"}) {
        bool refused = false;
        try { DecodeLocalSpeechAudio(remote, cancel); } catch (...) { refused = true; }
        Require(refused);
      }
      const auto link = prefix + L"-link.wav";
      Require(CreateSymbolicLinkW(link.c_str(), argv[2], SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE) != 0);
      bool refused_link = false;
      try { DecodeLocalSpeechAudio(link, cancel); } catch (...) { refused_link = true; }
      Require(DeleteFileW(link.c_str()) != 0 && refused_link);
      cancel = true;
      bool cancelled = false;
      try { TranscribeLocal(argv[1], argv[2], "en", "", cancel); }
      catch (...) { cancelled = true; }
      Require(cancelled);
      std::cout << "Generated offline WAV recognition passed in " << elapsed
                << "s; stereo AAC decode/recognition, clock gap, cancellation and remote/link refusal passed; no text logged\n";
    }
    MFShutdown(); CoUninitialize(); return 0;
  } catch (...) {
    MFShutdown(); CoUninitialize();
    std::cerr << "Generated speech timing check failed\n"; return 1;
  }
}

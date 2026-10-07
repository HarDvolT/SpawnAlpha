// Owned generated pixels only. Checks every saved timestamp against input.
#include "../gpu_video_writer.h"
#include "../recording_probe.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <winrt/base.h>
#include <iostream>
#include <vector>
#include <cmath>
using winrt::com_ptr;
using winrt::check_hresult;
void Require(bool value) { if (!value) throw winrt::hresult_error(E_FAIL); }
int wmain(int count, wchar_t** args) {
  if (count != 2) return 2;
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  try {
    com_ptr<ID3D11Device> device; com_ptr<ID3D11DeviceContext> context;
    check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
        nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
    for (UINT test = 0; test < 14; ++test) {
      const UINT width = test == 0 ? 640 : 658, height = test == 0 ? 360 : 392;
      const std::wstring path = std::wstring(args[1]) + L"-" + std::to_wstring(test) + L".mp4";
      std::vector<uint32_t> pixels(width * height, 0xFF2040E0);
      D3D11_TEXTURE2D_DESC desc{};
      desc.Width = width; desc.Height = height; desc.ArraySize = desc.MipLevels = 1;
      desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1;
      desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
      const D3D11_SUBRESOURCE_DATA data{pixels.data(), width * 4, 0};
      com_ptr<ID3D11Texture2D> texture;
      check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
      GpuVideoWriter writer;
      const GpuAudioFormat audio = test >= 10 ? GpuAudioFormat{test % 2 ? 44100U : 48000U, test % 2 ? 2U : 1U} : GpuAudioFormat{};
      check_hresult(writer.Start(device.get(), path, width, height, 30, audio, nullptr, test < 5 || test >= 7));
      GpuVideoWriter paired;
      if (test == 2) check_hresult(paired.Start(device.get(), path + L".pair.mp4", width, height));
      Require(FAILED(writer.WriteFrame(texture.get(), width, height, 333333)));
      std::vector<LONGLONG> times;
      const UINT frame_count = test >= 10 ? (test < 12 ? 120 : 241) : test >= 7 ? (test - 6) * 31 + 1 : 64;
      for (UINT frame = 0; frame < frame_count; ++frame) {
        if (test == 2 && frame == 27) Sleep(1000);
        const LONGLONG time = frame * 10000000LL / 30;
        if ((test == 3 && frame == 18) || (test == 4 && frame == 28)) {
          Require(FAILED(writer.WriteFrame(texture.get(), width, height, time + 4 * 10000000LL / 30)));
        }
        times.push_back(time);
        const LONGLONG length = frame == frame_count - 1 ? (test == 5 ? 5000000 : test == 6 ? 70000 : 333333) : 333333;
        check_hresult(writer.WriteFrame(texture.get(), width, height, time, length));
        if (audio.sample_rate) {
          std::vector<int16_t> pcm(audio.sample_rate / 30 * audio.channels);
          for (size_t index = 0; index < pcm.size(); ++index)
            pcm[index] = static_cast<int16_t>(2000 * std::sin((frame * (audio.sample_rate / 30) + index / audio.channels) * 600.0 * 6.283185307179586 / audio.sample_rate));
          check_hresult(writer.WriteAudio(pcm.data(), audio.sample_rate / 30, time));
        }
        if (test == 2) check_hresult(paired.WriteFrame(texture.get(), width, height, time));
        if (test == 2) Sleep(34);
      }
      check_hresult(writer.Finish());
      check_hresult(paired.Finish());
      check_hresult(MFStartup(MF_VERSION));
      com_ptr<IMFSourceReader> reader;
      check_hresult(MFCreateSourceReaderFromURL(path.c_str(), nullptr, reader.put()));
      const auto stream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
      size_t frame = 0;
      while (true) {
        DWORD flags = 0; LONGLONG time = 0; com_ptr<IMFSample> sample;
        check_hresult(reader->ReadSample(stream, 0, nullptr, &flags, &time, sample.put()));
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
        if (!sample) continue;
        if (test < 5 || test >= 7) {
          UINT32 clean = 0;
          check_hresult(sample->GetUINT32(MFSampleExtension_CleanPoint, &clean));
          Require(clean != 0);
        }
        // MP4's 30,000Hz fragment index can round one track tick (334 hns).
        if (frame >= times.size() || std::abs(time - times[frame]) > 334) {
          std::cerr << "Clock mismatch: case=" << test << " frame=" << frame
              << " saved=" << time << " expected=" << (frame < times.size() ? times[frame] : -1) << "\n";
          throw winrt::hresult_error(E_FAIL);
        }
        ++frame;
      }
      Require(frame == times.size()); reader = nullptr; check_hresult(MFShutdown());
      const std::atomic<bool> stop{false};
      const auto info = ProbeRecording(path, stop);
      const LONGLONG final_length = test == 5 ? 5000000 : test == 6 ? 70000 : 333333;
      Require(info.readable && std::abs(info.duration_100ns - (times.back() + final_length)) <= 334);
      std::cout << "Generated video clock case " << test << " passed.\n";
    }
    winrt::uninit_apartment(); return 0;
  } catch (...) {
    std::cerr << "Generated video clock check failed.\n";
    MFShutdown(); winrt::uninit_apartment(); return 1;
  }
}

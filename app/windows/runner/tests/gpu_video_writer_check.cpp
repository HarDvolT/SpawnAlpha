#include "../gpu_video_writer.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <winrt/base.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>
#include <cstring>
#include <cstdlib>

using winrt::com_ptr;
using winrt::check_hresult;

void Require(bool condition) { if (!condition) throw winrt::hresult_error(E_FAIL); }

bool HasFragments(const std::wstring& path) {
  std::ifstream file(std::filesystem::path(path), std::ios::binary);
  bool header = false, movie = false, fragments = false, data = false;
  while (file) {
    unsigned char bytes[8]{};
    file.read(reinterpret_cast<char*>(bytes), 8);
    if (file.gcount() != 8) break;
    const uint32_t size = (uint32_t(bytes[0]) << 24) | (uint32_t(bytes[1]) << 16) | (uint32_t(bytes[2]) << 8) | bytes[3];
    if (size < 8) break;
    header |= std::memcmp(bytes + 4, "ftyp", 4) == 0;
    movie |= std::memcmp(bytes + 4, "moov", 4) == 0;
    fragments |= std::memcmp(bytes + 4, "moof", 4) == 0;
    data |= std::memcmp(bytes + 4, "mdat", 4) == 0;
    file.seekg(size - 8, std::ios::cur);
  }
  return header && movie && fragments && data;
}

int wmain(int count, wchar_t** args) {
  if (count != 2 && count != 3) return 2;
  const bool crash = count == 3 && std::wcscmp(args[2], L"--crash") == 0;
  const bool verify_crash = count == 3 && std::wcscmp(args[2], L"--verify-crash") == 0;
  if (count == 3 && !crash && !verify_crash) return 2;
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return 3;
  const char* stage = "create GPU";
  try {
    const std::wstring path(args[1]);
    if (!verify_crash) {
      com_ptr<ID3D11Device> device;
      com_ptr<ID3D11DeviceContext> context;
      check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
          nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
      GpuVideoWriter writer;
      stage = "start writer";
      Require(FAILED(writer.Start(device.get(), path, 641, 360)));
      check_hresult(writer.Start(device.get(), path, 640, 360));
      stage = "write frames";
      for (UINT frame = 0; frame < 120; ++frame) {
        const UINT width = frame < 60 ? 640 : 320, height = frame < 60 ? 360 : 240;
        std::vector<uint32_t> pixels(width * height, 0xFF2040E0);
        for (UINT y = 0; y < height; ++y) for (UINT x = 0; x < width; ++x) {
          if ((x + frame * 3) % width < width / 8) pixels[y * width + x] = 0xFFE08020;
        }
        D3D11_TEXTURE2D_DESC desc{};
        desc.Width = width; desc.Height = height; desc.MipLevels = 1; desc.ArraySize = 1;
        desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1;
        desc.Usage = D3D11_USAGE_DEFAULT; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
        const D3D11_SUBRESOURCE_DATA content{pixels.data(), width * 4, 0};
        com_ptr<ID3D11Texture2D> texture;
        check_hresult(device->CreateTexture2D(&desc, &content, texture.put()));
        if (frame == 1) Require(FAILED(writer.WriteFrame(texture.get(), width, height, 0)));
        check_hresult(writer.WriteFrame(texture.get(), width, height, frame * 10000000LL / 30));
        if (crash) Sleep(34);
      }
      if (crash) { Sleep(300); std::_Exit(0); }
      stage = "finalize";
      check_hresult(writer.Finish());
      check_hresult(writer.Finish());
      stage = "validate fragments";
      Require(HasFragments(path));
      // Never replace an existing take, including a previously generated fixture.
      Require(FAILED(writer.Start(device.get(), path, 640, 360)));
      }
    Require(HasFragments(path));
    check_hresult(MFStartup(MF_VERSION));
    stage = "open decoder";
    com_ptr<IMFSourceReader> reader;
    com_ptr<IMFAttributes> decode_options;
    check_hresult(MFCreateAttributes(decode_options.put(), 1));
    check_hresult(decode_options->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
    check_hresult(MFCreateSourceReaderFromURL(path.c_str(), decode_options.get(), reader.put()));
    com_ptr<IMFMediaType> rgb;
    check_hresult(MFCreateMediaType(rgb.put()));
    check_hresult(rgb->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
    check_hresult(rgb->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
    stage = "configure decoder";
    const DWORD video_stream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
    check_hresult(reader->SetCurrentMediaType(video_stream, nullptr, rgb.get()));
    UINT decoded = 0;
    LONGLONG previous = -1;
    stage = "decode frames";
    while (true) {
      DWORD flags = 0;
      LONGLONG time = 0;
      com_ptr<IMFSample> sample;
      check_hresult(reader->ReadSample(video_stream, 0, nullptr, &flags, &time, sample.put()));
      if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
      if (sample) {
        Require(time > previous); previous = time;
        if (decoded == 0 || decoded == 90) {
          com_ptr<IMFMediaBuffer> buffer;
          check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
          BYTE* pixels = nullptr; DWORD length = 0;
          check_hresult(buffer->Lock(&pixels, nullptr, &length));
          const bool sized = length >= 640 * 360 * 4;
          // RGB32 is B,G,R,X. Sample central rows so row orientation is immaterial.
          const size_t point = (180 * 640 + (decoded == 0 ? 150 : 320)) * 4;
          const bool blue = sized && pixels[point] > pixels[point + 2] + 60;
          const size_t margin = (180 * 640 + 10) * 4;
          const bool letterbox = decoded == 0 || (sized && pixels[margin] < 12 &&
              pixels[margin + 1] < 12 && pixels[margin + 2] < 12);
          buffer->Unlock();
          Require(blue && letterbox);
        }
        ++decoded;
      }
    }
    Require(verify_crash ? decoded >= 60 && decoded <= 120 : decoded == 120);
    reader = nullptr;
    MFShutdown();
    if (verify_crash) {
      std::cout << "Abrupt-exit check passed: " << decoded << " recoverable frames, ordered timestamps, fragmented MP4.\n";
    } else {
      std::cout << "GPU video check passed: 120 frames, resize, ordered timestamps, fragmented MP4, no overwrite.\n";
    }
    CoUninitialize();
    return 0;
  } catch (...) {
    std::cerr << "GPU video check failed at " << stage << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    CoUninitialize();
    return 1;
  }
}

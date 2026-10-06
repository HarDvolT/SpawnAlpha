// Generated media only. Reuse our bounded fixture generator/decoder helpers.
#define wmain RenderRiskCheckEntry
#include "render_core_check.cpp"
#undef wmain
#include "../local_render.h"
#include "../recording_probe.h"
#include <fstream>
#include <filesystem>
#include <wincodec.h>

void SaveCaptionPng(const std::wstring& path, UINT width, UINT height, const BYTE* bytes) {
  Require(GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES);
  com_ptr<IWICImagingFactory> factory;
  check_hresult(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(factory.put())));
  com_ptr<IWICStream> stream; check_hresult(factory->CreateStream(stream.put()));
  check_hresult(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE));
  com_ptr<IWICBitmapEncoder> encoder; check_hresult(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.put()));
  check_hresult(encoder->Initialize(stream.get(), WICBitmapEncoderNoCache));
  com_ptr<IWICBitmapFrameEncode> image; check_hresult(encoder->CreateNewFrame(image.put(), nullptr));
  check_hresult(image->Initialize(nullptr)); check_hresult(image->SetSize(width, height));
  auto format = GUID_WICPixelFormat32bppBGRA; check_hresult(image->SetPixelFormat(&format));
  Require(IsEqualGUID(format, GUID_WICPixelFormat32bppBGRA));
  std::vector<BYTE> opaque(bytes, bytes + static_cast<size_t>(width) * height * 4);
  for (size_t i = 3; i < opaque.size(); i += 4) opaque[i] = 255;
  check_hresult(image->WritePixels(height, width * 4, static_cast<UINT>(opaque.size()), opaque.data()));
  check_hresult(image->Commit()); check_hresult(encoder->Commit());
}
std::vector<BYTE> CaptionPixels(IMFSourceReader* reader, IMFSample* sample, UINT width, UINT height) {
  // Decoder storage may be wider than the visible aperture (1088 for 1080).
  // Read the negotiated format and optional 2D stride, never infer row width
  // from the export dimensions or a total buffer length.
  com_ptr<IMFMediaType> type; check_hresult(reader->GetCurrentMediaType(kVideoStream, type.put()));
  UINT decoded_width = 0, decoded_height = 0;
  check_hresult(MFGetAttributeSize(type.get(), MF_MT_FRAME_SIZE, &decoded_width, &decoded_height));
  Require(decoded_width >= width && decoded_height >= height && decoded_width <= 16384 && decoded_height <= 16384);
  UINT offset_x = 0, offset_y = 0;
  MFVideoArea area{}; UINT area_size = 0;
  if (SUCCEEDED(type->GetBlob(MF_MT_MINIMUM_DISPLAY_APERTURE, reinterpret_cast<BYTE*>(&area), sizeof(area), &area_size))) {
    Require(area_size == sizeof(area) && area.OffsetX.value >= 0 && area.OffsetY.value >= 0 &&
      area.OffsetX.fract == 0 && area.OffsetY.fract == 0 && area.Area.cx == static_cast<LONG>(width) && area.Area.cy == static_cast<LONG>(height));
    offset_x = area.OffsetX.value; offset_y = area.OffsetY.value;
  }
  Require(offset_x + width <= decoded_width && offset_y + height <= decoded_height);
  UINT stride_bits = 0; LONG stride = 0;
  if (SUCCEEDED(type->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride_bits))) stride = static_cast<LONG>(stride_bits);
  else check_hresult(MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, decoded_width, &stride));
  com_ptr<IMFMediaBuffer> buffer; check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
  const auto plane = buffer.try_as<IMF2DBuffer>();
  std::vector<BYTE> pixels(static_cast<size_t>(width) * height * 4);
  BYTE* first = nullptr; DWORD length = 0;
  if (plane) check_hresult(plane->Lock2D(&first, &stride));
  else check_hresult(buffer->Lock(&first, nullptr, &length));
  const auto row_size = std::abs(static_cast<int64_t>(stride));
  const bool valid = row_size >= decoded_width * 4 && row_size <= 16384 * 4 &&
    (plane || length >= row_size * decoded_height);
  if (valid) {
    if (!plane && stride < 0) first += row_size * (decoded_height - 1);
    for (UINT y = 0; y < height; ++y) {
      std::memcpy(pixels.data() + static_cast<size_t>(y) * width * 4,
        first + static_cast<ptrdiff_t>(y + offset_y) * stride + offset_x * 4, width * 4);
    }
  }
  if (plane) check_hresult(plane->Unlock2D()); else check_hresult(buffer->Unlock());
  Require(valid); return pixels;
}
void VerifyCaptionPixels(const LocalRenderRequest& request) {
  com_ptr<IMFAttributes> attributes; check_hresult(MFCreateAttributes(attributes.put(), 1));
  check_hresult(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
  com_ptr<IMFSourceReader> reader; check_hresult(MFCreateSourceReaderFromURL(request.output.c_str(), attributes.get(), reader.put()));
  com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)); check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
  check_hresult(reader->SetCurrentMediaType(kVideoStream, nullptr, type.get()));
  int frames = 0;
  while (true) {
    DWORD flags = 0; int64_t time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kVideoStream, 0, nullptr, &flags, &time, sample.put()));
    if (sample) {
      const auto pixels = CaptionPixels(reader.get(), sample.get(), request.width, request.height);
      const auto bytes = pixels.data(); bool valid = true;
      UINT white = 0;
      UINT min_y = request.height, max_y = 0, min_x = request.width, max_x = 0;
      if (valid) for (UINT y = 0; y < request.height; ++y) for (UINT x = 0; x < request.width; ++x) {
        const auto i = (static_cast<size_t>(y) * request.width + x) * 4;
        if (bytes[i] > 180 && bytes[i + 1] > 180 && bytes[i + 2] > 180) {
          ++white;
          min_y = std::min(min_y, y); max_y = std::max(max_y, y); min_x = std::min(min_x, x); max_x = std::max(max_x, x);
          const bool vertical = request.height > request.width;
          valid = valid && x >= request.width * .06 - 2 && x <= request.width * (vertical ? .86 : .94) + 2 &&
            y >= request.height * .13 - 2 && y <= request.height * (vertical ? .79 : .88) + 2;
        }
      }
      const bool caption = time >= 2000000 && time < 8000000;
      valid = valid && (caption ? white > 40 : white == 0);
      if (!valid) std::cout << "Generated caption pixels: frame=" << frames << " time=" << time << " white=" << white << " box=" << min_x << "," << min_y << "," << max_x << "," << max_y << "\n";
      if (frames == 10 && valid) SaveCaptionPng(request.output + L".png", request.width, request.height, bytes);
      Require(valid); ++frames;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  Require(frames == 30);
}
CaptionLayout CaptionFixture() {
  CaptionLayout style;
  style.edge = .06; style.bottom = .12; style.safe_top = .13; style.safe_bottom = .21; style.safe_right = .14;
  style.font_size = 56; style.line_height = 64; style.min_size = 28; style.weight = 700;
  style.padding = 12; style.radius = 8; style.shadow_offset = 2;
  style.text_color = 0xffffffff; style.plate_color = 0xa6000000;
  return style;
}

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

void GenerateFillerSource(ID3D11Device* device, const std::wstring& path) {
  // Three labelled tone islands, separated by actual zero PCM. The middle
  // island/red picture represents a reviewed filler, never a real speaker.
  GpuVideoWriter writer; check_hresult(writer.Start(device, path, kWidth, kHeight, 30, {kRate, 1}));
  for (UINT frame = 0; frame < 120; ++frame) {
    const auto time_us = static_cast<int64_t>(frame) * 1000000 / 30;
    const uint32_t color = time_us >= 1100000 && time_us < 1250000 ? 0xffe03030 : 0xff30c050;
    std::vector<uint32_t> pixels(kWidth * kHeight, color);
    D3D11_TEXTURE2D_DESC desc{}; desc.Width = kWidth; desc.Height = kHeight;
    desc.MipLevels = 1; desc.ArraySize = 1; desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA data{pixels.data(), kWidth * 4, 0}; com_ptr<ID3D11Texture2D> texture;
    check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
    check_hresult(writer.WriteFrame(texture.get(), kWidth, kHeight, frame * kSecond / 30));
    std::vector<int16_t> pcm(kRate / 30);
    for (UINT index = 0; index < pcm.size(); ++index) {
      const auto position = frame * (kRate / 30) + index;
      const double seconds = static_cast<double>(position) / kRate;
      const double hz = seconds >= .2 && seconds < .5 ? 330 : seconds >= 1.1 && seconds < 1.25 ? 770 : seconds >= 2 && seconds < 2.3 ? 990 : 0;
      pcm[index] = static_cast<int16_t>(std::sin(seconds * hz * 6.283185307179586) * 12000);
    }
    check_hresult(writer.WriteAudio(pcm.data(), static_cast<UINT>(pcm.size()), frame * kSecond / 30));
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

void VerifyLocalCut(const LocalRenderRequest& request, int expected_frames, int64_t expected_us, bool early_camera = false, bool filler_removed = false) {
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
      const auto pixels = CaptionPixels(reader.get(), sample.get(), request.width, request.height);
      const auto bytes = pixels.data();
      const size_t center = (request.height / 2 * request.width + request.width / 2) * 4;
      int64_t offset_us = static_cast<int64_t>(frames) * 1000000 / 30, source = 0;
      for (const auto& range : request.ranges) {
        const auto length_us = range.end_us - range.start_us;
        if (offset_us < length_us) { source = range.start_us + offset_us; break; }
        offset_us -= length_us;
      }
      bool valid = true;
      if (filler_removed) valid = bytes[center + 1] > bytes[center] + 80 && bytes[center + 1] > bytes[center + 2] + 80;
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
      Require(valid); ++frames;
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
      const auto filler_source = prefix + L"-filler-source.mp4";
      stage = "generate filler tone islands"; GenerateFillerSource(device.get(), filler_source);
      const auto uncut_filler = Audio(filler_source); Require(ToneAt(uncut_filler, 52800, 770) > 5000);
      request.source = filler_source; request.output = prefix + L"-filler-cut.mp4";
      request.ranges = {{0, 800000}, {1625000, 4000000}};
      stage = "render reviewed filler range"; RenderLocalVideo(request, cancel, [](double) {});
      stage = "verify filler picture and source clock"; VerifyLocalCut(request, 96, 3175000, false, true);
      const auto filler_audio = Audio(request.output);
      Require(ToneAt(filler_audio, 10800, 330) > 9000 && ToneAt(filler_audio, 57600, 990) > 9000);
      for (size_t first = 0; first + 12000 < filler_audio.size(); first += 4000) Require(ToneAt(filler_audio, first, 770) < 1500);
      request.output = prefix + L"-retake-cut.mp4"; request.ranges = {{0, 50000}, {1625000, 4000000}};
      stage = "render reviewed retake range"; RenderLocalVideo(request, cancel, [](double) {});
      stage = "verify retained attempt picture and clock"; VerifyLocalCut(request, 73, 2425000, false, true);
      const auto retake_audio = Audio(request.output);
      Require(ToneAt(retake_audio, 21600, 990) > 9000);
      for (size_t first = 0; first + 12000 < retake_audio.size(); first += 4000) {
        Require(ToneAt(retake_audio, first, 330) < 1500 && ToneAt(retake_audio, first, 770) < 1500);
      }
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
      const wchar_t* text[] = {L"Hello everyone.", L"Bonjour \u00e0 tous.", L"\u0645\u0631\u062d\u0628\u0627 \u0628\u0643\u0645 \u0627\u0644\u064a\u0648\u0645.",
        L"Bonjour \u00e0 tous. Cette phrase reste compl\u00e8te et lisible sur deux lignes, sans couper les mots.",
        L"\u0645\u064e\u0631\u0652\u062d\u064e\u0628\u064b\u0627 \u0628\u0650\u0643\u064f\u0645\u0652 2026 Bonjour."};
      request.source = silent; request.caption_layout = CaptionFixture();
      for (UINT language = 0; language < 5; ++language) {
        request.caption_layout.rtl = language == 2 || language == 4;
        request.captions = {{200000, 800000, text[language]}};
        request.output = prefix + L"-caption-" + std::to_wstring(language) + L".mp4";
        stage = "render complete phrase captions"; RenderLocalVideo(request, cancel, [](double) {});
        stage = "verify caption time and safe pixels"; VerifyCaptionPixels(request);
      }
      request.width = 1080; request.height = 1920;
      request.captions = {{200000, 800000, text[4]}};
      request.output = prefix + L"-caption-portrait.mp4";
      stage = "render Arabic vertical captions"; RenderLocalVideo(request, cancel, [](double) {});
      stage = "verify Arabic vertical safe pixels"; VerifyCaptionPixels(request);
      request.output = prefix + L"-caption-invalid.mp4"; request.captions = {{200000, 800000, std::wstring(4096, L'W')}};
      bool long_rejected = false;
      stage = "reject unreadable caption without clipping";
      try { RenderLocalVideo(request, cancel, [](double) {}); } catch (...) { long_rejected = true; }
      Require(long_rejected && GetFileAttributesW(request.output.c_str()) == INVALID_FILE_ATTRIBUTES);
      request.output = prefix + L"-caption-control.mp4"; request.captions = {{200000, 800000, L"Invalid\x0001" L"caption"}};
      bool control_rejected = false; stage = "reject caption control characters";
      try { RenderLocalVideo(request, cancel, [](double) {}); } catch (...) { control_rejected = true; }
      Require(control_rejected && GetFileAttributesW(request.output.c_str()) == INVALID_FILE_ATTRIBUTES);
      request.captions.clear(); request.width = 640; request.height = 360;
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
    std::cout << "Local render check passed: streaming PCM/GPU pair, source selection/reordering, reviewed filler and retake tone/picture removal, silent input, stereo resampling, EN/FR/AR caption timing/safe pixels, vertical Arabic, no clipped words, camera inset/end, exact portrait duration, cancel cleanup, damaged input and overwrite protection.\n";
    MFShutdown(); CoUninitialize(); return 0;
  } catch (...) {
    std::cerr << "Local render check failed at " << stage << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    MFShutdown(); CoUninitialize(); return 1;
  }
}

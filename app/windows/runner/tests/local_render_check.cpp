// Generated media only. Reuse our bounded fixture generator/decoder helpers.
#define wmain RenderRiskCheckEntry
#include "render_core_check.cpp"
#undef wmain
#include "../local_render.h"
#include "../recording_probe.h"
#include <fstream>
#include <filesystem>
#include <wincodec.h>
#include "../audio_join_fade.h"
void SaveCaptionPng(const std::wstring&, UINT, UINT, const BYTE*);
std::vector<BYTE> CaptionPixels(IMFSourceReader*, IMFSample*, UINT, UINT);

void CheckAudioJoinEnvelope() {
  for (uint32_t channels : {1u, 2u}) {
    std::vector<int16_t> whole(1600 * channels);
    for (size_t i = 0; i < whole.size(); ++i) whole[i] = i % channels ? -12000 : 12000;
    const auto original = whole;
    ApplyAudioJoinFade(whole, channels, 0, 0, 1600, 480, true, true);
    for (size_t frame = 0; frame < 1600; ++frame) for (uint32_t ch = 0; ch < channels; ++ch) {
      Require(std::abs(whole[frame * channels + ch]) <= 12000);
      if (frame >= 480 && frame < 1120) Require(whole[frame * channels + ch] == original[frame * channels + ch]);
      if (frame > 0 && frame < 480) Require(std::abs(whole[frame * channels + ch]) >= std::abs(whole[(frame - 1) * channels + ch]));
    }
    Require(whole.front() == 0 && whole.back() == 0);
    std::vector<int16_t> packeted;
    for (size_t first = 0; first < 1600; first += 137) {
      const auto end = std::min<size_t>(first + 137, 1600);
      std::vector<int16_t> packet(original.begin() + first * channels, original.begin() + end * channels);
      ApplyAudioJoinFade(packet, channels, first, 0, 1600, 480, true, true);
      packeted.insert(packeted.end(), packet.begin(), packet.end());
    }
    Require(packeted == whole);
    auto continuous = original; ApplyAudioJoinFade(continuous, channels, 0, 0, 1600, 480, false, false);
    Require(continuous == original);
    auto disabled = original; ApplyAudioJoinFade(disabled, channels, 0, 0, 1600, 0, true, true);
    Require(disabled == original);
    for (UINT frames = 1; frames <= 10; ++frames) {
      std::vector<int16_t> tiny(frames * channels, 12000);
      ApplyAudioJoinFade(tiny, channels, 0, 0, frames, 480, true, true);
      Require(std::all_of(tiny.begin(), tiny.end(), [](int16_t value) { return value >= 0 && value <= 12000; }));
    }
  }
  for (const auto invalid : {0u, 3u}) {
    std::vector<int16_t> pcm(100, 12000); bool rejected = false;
    try { ApplyAudioJoinFade(pcm, invalid, 0, 0, 100, 480, true, true); } catch (...) { rejected = true; }
    Require(rejected);
  }
}

double WindowRms(const std::vector<int16_t>& pcm, size_t start, size_t frames) {
  Require(start + frames <= pcm.size()); double sum = 0;
  for (size_t i = start; i < start + frames; ++i) sum += static_cast<double>(pcm[i]) * pcm[i];
  return std::sqrt(sum / frames);
}

void CheckScreenZoomCrop() {
  ScreenZoom zoom;
  zoom.Open({{200000, .8, .5, 1.8, 640, 360}, {900000, .2, .5, 2.4, 640, 360},
    {2000000, .2, .5, 1, 640, 360}}, {1, 90, 19}, 640, 360, 4000000);
  const RECT full{0, 0, 640, 360};
  Require(zoom.Crop(full, 0).right == 640);
  LONG previous_width = 640;
  for (int64_t time = 0; time < 4000000; time += 33333) {
    const auto crop = zoom.Crop(full, time);
    Require(crop.left >= 0 && crop.top >= 0 && crop.right <= 640 && crop.bottom <= 360 &&
      crop.right > crop.left && crop.bottom > crop.top);
    if (time < 900000) Require(crop.right - crop.left <= previous_width);
    previous_width = crop.right - crop.left;
  }
  Require(previous_width == 640);
  ScreenZoom resized;
  resized.Open({{0, .9, .5, 2.4, 320, 360}}, {1, 90, 19}, 640, 360, 4000000);
  const auto crop = resized.Crop(full, 1500000);
  Require(crop.left > 260 && crop.right < 640); // Account for recorded letterboxing.
  resized.Reset(2000000); Require(resized.Crop(full, 2000000).right == 640);
  bool rejected = false;
  try { ScreenZoom invalid; invalid.Open({{0, 2, .5, 2.4, 640, 360}}, {1, 90, 19}, 640, 360, 4000000); }
  catch (...) { rejected = true; }
  Require(rejected);
}

void GenerateZoomSource(ID3D11Device* device, const std::wstring& path) {
  GpuVideoWriter writer; check_hresult(writer.Start(device, path, kWidth, kHeight, 30));
  std::vector<uint32_t> pixels(kWidth * kHeight);
  for (UINT y = 0; y < kHeight; ++y) for (UINT x = 0; x < kWidth; ++x)
    pixels[y * kWidth + x] = x < kWidth * .4 ? 0xff306be0 : x > kWidth * .6 ? 0xffe04830 : 0xff25b64a;
  D3D11_TEXTURE2D_DESC desc{}; desc.Width = kWidth; desc.Height = kHeight;
  desc.MipLevels = desc.ArraySize = 1; desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  D3D11_SUBRESOURCE_DATA data{pixels.data(), kWidth * 4, 0}; com_ptr<ID3D11Texture2D> texture;
  check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
  for (UINT frame = 0; frame < 120; ++frame)
    check_hresult(writer.WriteFrame(texture.get(), kWidth, kHeight, frame * kSecond / 30));
  check_hresult(writer.Finish());
}

void VerifyZoomPixels(const LocalRenderRequest& request) {
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
      const size_t center = (request.height / 2 * request.width + request.width / 2) * 4;
      if (frames == 0 || frames == 112) Require(pixels[center + 1] > pixels[center + 2] + 80);
      if (frames == 30) {
        Require(pixels[center + 2] > pixels[center + 1] + 80);
        SaveCaptionPng(request.output + L".png", request.width, request.height, pixels.data());
      }
      ++frames;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  Require(frames == 120);
}

std::vector<BYTE> FramePixels(const std::wstring& path, UINT width, UINT height, int wanted) {
  com_ptr<IMFAttributes> attributes; check_hresult(MFCreateAttributes(attributes.put(), 1));
  check_hresult(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
  com_ptr<IMFSourceReader> reader; check_hresult(MFCreateSourceReaderFromURL(path.c_str(), attributes.get(), reader.put()));
  com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)); check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
  check_hresult(reader->SetCurrentMediaType(kVideoStream, nullptr, type.get()));
  int frame = 0;
  while (true) {
    DWORD flags = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kVideoStream, 0, nullptr, &flags, nullptr, sample.put()));
    if (sample && frame++ == wanted) return CaptionPixels(reader.get(), sample.get(), width, height);
    Require(!(flags & MF_SOURCE_READERF_ENDOFSTREAM));
  }
}

void VerifyShortcutPixels(const LocalRenderRequest& request) {
  UINT early_top = request.height, settled_top = request.height;
  for (const auto frame : {18, 21, 30, 53, 55}) {
    const auto pixels = FramePixels(request.output, request.width, request.height, frame);
    size_t white = 0; UINT top = request.height;
    for (UINT y = 0; y < request.height; ++y) for (UINT x = 0; x < request.width; ++x) {
      const size_t p = (y * request.width + x) * 4;
      if (pixels[p] > 220 && pixels[p + 1] > 220 && pixels[p + 2] > 220) {
        ++white; top = std::min(top, y);
        Require(x + 3 >= request.width * .06 && x < request.width * .86 + 3 &&
          y + 3 >= request.height * (request.height > request.width ? .13 : .06) && y < request.height * .4);
      }
    }
    if (frame == 21) { Require(white > 40); early_top = top; }
    else if (frame == 30) {
      Require(white > 40); settled_top = top;
      SaveCaptionPng(request.output + L".png", request.width, request.height, pixels.data());
    } else Require(white == 0);
  }
  Require(early_top > settled_top); // Whole plate rises; fixed signal glyphs do not reflow.
}

void VerifyClickPixels(const LocalRenderRequest& request, bool visible, const std::wstring& baseline = {}) {
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
      if (frames == 18 || frames == 25 || frames == 35) {
        const auto pixels = CaptionPixels(reader.get(), sample.get(), request.width, request.height);
        size_t amber = 0;
        for (size_t i = 0; i < pixels.size(); i += 4)
          if (pixels[i + 2] > 170 && pixels[i + 1] > 100 && pixels[i + 1] < 210 && pixels[i] < 110) ++amber;
        if (!visible) {
          Require(!baseline.empty() && pixels == FramePixels(baseline, request.width, request.height, frames));
        } else if (frames == 25) {
          Require(amber > 30); SaveCaptionPng(request.output + L".png", request.width, request.height, pixels.data());
        } else Require(amber == 0);
      }
      ++frames;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  Require(frames == 120);
}

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
  style.stress_color = 0xffffc940; style.energy_color = 0xffff6ba8;
  style.rise = 10; style.pop_start = .55; style.pop_max = 1.22; style.pop_amplitude = .22; style.punch_start = .8;
  style.stress_width = 125; style.punch_width = 135; style.slower_width = 118; style.faster_width = 82;
  style.smooth_mass = 1; style.smooth_stiffness = 260; style.smooth_damping = 32;
  style.pop_mass = 1; style.pop_stiffness = 380; style.pop_damping = 18;
  return style;
}

void VerifyKaraokePixels(const LocalRenderRequest& request) {
  com_ptr<IMFAttributes> attributes; check_hresult(MFCreateAttributes(attributes.put(), 1));
  check_hresult(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
  com_ptr<IMFSourceReader> reader; check_hresult(MFCreateSourceReaderFromURL(request.output.c_str(), attributes.get(), reader.put()));
  com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)); check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
  check_hresult(reader->SetCurrentMediaType(kVideoStream, nullptr, type.get()));
  UINT early = 0, late = 0, early_white = 0, last_white = 0;
  UINT early_left = 0, early_right = 0, late_left = 0, late_right = 0;
  int frames = 0;
  while (true) {
    DWORD flags = 0; int64_t time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kVideoStream, 0, nullptr, &flags, &time, sample.put()));
    if (sample) {
      const auto pixels = CaptionPixels(reader.get(), sample.get(), request.width, request.height);
      UINT white = 0, amber = 0, min_x = request.width, max_x = 0;
      for (UINT y = 0; y < request.height; ++y) for (UINT x = 0; x < request.width; ++x) {
        const auto i = (static_cast<size_t>(y) * request.width + x) * 4;
        const bool bright = pixels[i] > 180 && pixels[i + 1] > 180 && pixels[i + 2] > 180;
        // Thin amber lines are chroma-subsampled; compare channel differences
        // as well as brightness, rather than requiring an uncompressed RGB.
        const bool gold = pixels[i + 2] > 140 && pixels[i + 2] > pixels[i + 1] + 5 && pixels[i + 1] > pixels[i] + 20;
        if (bright || gold) {
          const bool vertical = request.height > request.width;
          Require(x >= request.width * .06 - 2 && x <= request.width * (vertical ? .86 : .94) + 2 &&
            y >= request.height * .13 - 2 && y <= request.height * (vertical ? .79 : .88) + 2);
        }
        if (bright) ++white;
        if (gold) { ++amber; min_x = std::min(min_x, x); max_x = std::max(max_x, x); }
      }
      const bool active = time >= 2000000 && time < 8000000;
      if (!(active ? white > 40 : white == 0 && amber == 0)) std::cout << "Generated Karaoke frame=" << frames << " white=" << white << " amber=" << amber << "\n";
      Require(active ? white > 40 : white == 0 && amber == 0);
      if (time >= 4000000 && time < 5000000 && amber != 0) std::cout << "Generated Karaoke gap=" << frames << " amber=" << amber << "\n";
      if (time >= 4000000 && time < 5000000) Require(amber == 0);
      if (frames == 7) { early = amber; early_white = white; early_left = min_x; early_right = max_x; }
      if (frames == 11) { late = amber; late_left = min_x; late_right = max_x; }
      if (frames == 23) { last_white = white; SaveCaptionPng(request.output + L".png", request.width, request.height, pixels.data()); }
      ++frames;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  if (!(frames == 30 && early > 0 && late > early * 2 && last_white > early_white * 1.2))
    std::cout << "Generated Karaoke summary: early=" << early << " late=" << late << " firstWhite=" << early_white << " lastWhite=" << last_white << " rtl=" << request.caption_layout.rtl << "\n";
  Require(frames == 30 && early > 0 && late > early * 2 && last_white > early_white * 1.2);
  if (request.caption_layout.rtl) Require(std::abs(static_cast<int>(early_right) - static_cast<int>(late_right)) <= 2 && late_left < early_left);
  else Require(std::abs(static_cast<int>(early_left) - static_cast<int>(late_left)) <= 2 && late_right > early_right);
}

void VerifyMotionPixels(const LocalRenderRequest& request) {
  com_ptr<IMFAttributes> attributes; check_hresult(MFCreateAttributes(attributes.put(), 1));
  check_hresult(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
  com_ptr<IMFSourceReader> reader; check_hresult(MFCreateSourceReaderFromURL(request.output.c_str(), attributes.get(), reader.put()));
  com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)); check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
  check_hresult(reader->SetCurrentMediaType(kVideoStream, nullptr, type.get()));
  UINT early_gold = 0, late_gold = 0, early_bottom = 0, late_bottom = 0;
  int frames = 0;
  while (true) {
    DWORD flags = 0; int64_t time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kVideoStream, 0, nullptr, &flags, &time, sample.put()));
    if (sample) {
      const auto pixels = CaptionPixels(reader.get(), sample.get(), request.width, request.height);
      UINT white = 0, gold = 0, bottom = 0, white_left = request.width, white_right = 0,
        gold_left = request.width, gold_right = 0; uint64_t sum_y = 0;
      for (UINT y = 0; y < request.height; ++y) for (UINT x = 0; x < request.width; ++x) {
        const auto i = (static_cast<size_t>(y) * request.width + x) * 4;
        const bool bright = pixels[i] > 180 && pixels[i + 1] > 180 && pixels[i + 2] > 180;
        const bool amber = pixels[i + 2] > 140 && pixels[i + 2] > pixels[i + 1] + 5 && pixels[i + 1] > pixels[i] + 20;
        if (bright || amber) {
          const bool vertical = request.height > request.width;
          Require(x >= request.width * .06 - 2 && x <= request.width * (vertical ? .86 : .94) + 2 &&
            y >= request.height * .13 - 2 && y <= request.height * (vertical ? .79 : .88) + 2);
          bottom = std::max(bottom, y); sum_y += y;
        }
        // Chroma subsampling can make an amber edge bright. Measure neutral
        // white ink for the neighboring-word separation check.
        if (bright) ++white;
        if (bright && pixels[i] > 220 && std::abs(static_cast<int>(pixels[i + 2]) - pixels[i]) < 20 &&
            std::abs(static_cast<int>(pixels[i + 1]) - pixels[i]) < 20) {
          white_left = std::min(white_left, x); white_right = std::max(white_right, x);
        }
        if (amber) { ++gold; gold_left = std::min(gold_left, x); gold_right = std::max(gold_right, x); }
      }
      const bool active = time >= 2000000 && time < 8000000;
      Require(active ? white + gold > 40 : white == 0 && gold == 0);
      if (time < 4000000) Require(gold == 0);
      if (frames == 7) early_bottom = bottom;
      if (frames == 11) late_bottom = bottom;
      if (frames == 13) early_gold = gold;
      if (frames == 17) {
        late_gold = gold; const auto center = static_cast<double>(sum_y) / (white + gold);
        Require(request.caption_layout.punch ? center > request.height * .35 && center < request.height * .65 : center > request.height * .6);
        SaveCaptionPng(request.output + L".png", request.width, request.height, pixels.data());
        if (request.caption_layout.cue && request.caption_layout.motion) {
          const bool separated = request.caption_layout.rtl ? white_left > gold_right + 2 : gold_left > white_right + 2;
          if (!separated) std::cout << "Generated caption spacing: rtl=" << request.caption_layout.rtl << " white=" << white_left << "," << white_right << " amber=" << gold_left << "," << gold_right << "\n";
          Require(separated);
        }
      }
      ++frames;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  if (!(frames == 30 && early_gold > 40 && late_gold > 40))
    std::cout << "Generated motion summary: early=" << early_gold << " late=" << late_gold << "\n";
  Require(frames == 30 && early_gold > 40 && late_gold > 40);
  if (request.caption_layout.motion) {
    Require(late_gold > early_gold * 1.2);
    if (request.caption_layout.cue) Require(early_bottom > late_bottom);
  } else Require(std::abs(static_cast<int>(early_gold) - static_cast<int>(late_gold)) < static_cast<int>(late_gold / 10 + 10));
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
    stage = "pure packet-independent sound join envelope"; CheckAudioJoinEnvelope();
    stage = "screen zoom springs, resize fit and cut reset"; CheckScreenZoomCrop();
    check_hresult(MFStartup(MF_VERSION));
    {
      com_ptr<ID3D11Device> device;
      check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
        nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, nullptr));
      const std::wstring prefix(args[1]), source = prefix + L"-source.mp4";
      std::atomic<bool> cancel{false};
      stage = "generate"; Generate(device.get(), source);
      const auto zoom_source = prefix + L"-zoom-source.mp4";
      stage = "generate spatial zoom source"; GenerateZoomSource(device.get(), zoom_source);
      for (bool vertical : {false, true}) {
        LocalRenderRequest zoomed{zoom_source, L"", prefix + (vertical ? L"-zoom-portrait.mp4" : L"-zoom-wide.mp4"),
          4000000, vertical ? 1080u : 1920u, vertical ? 1920u : 1080u, {{0, 4000000}}};
        zoomed.zoom_steps = {{200000, .8, .5, 1.8, kWidth, kHeight}, {2100000, .8, .5, 1, kWidth, kHeight}};
        zoomed.zoom_spring = {1, 90, 19};
        stage = "render spatial screen zoom"; RenderLocalVideo(zoomed, cancel, [](double) {});
        stage = "verify zoom and restored whole-picture pixels"; VerifyZoomPixels(zoomed);
        auto shortcut = zoomed;
        shortcut.output = prefix + (vertical ? L"-shortcut-portrait.mp4" : L"-shortcut-wide.mp4");
        shortcut.shortcut_badges = {{700000, 1800000, L"Ctrl+Shift+Z"}};
        auto& keycap = shortcut.shortcut_layout;
        keycap.keycap = true; keycap.edge = keycap.bottom = keycap.safe_bottom = .06;
        keycap.safe_top = .13; keycap.safe_right = .14;
        keycap.font_size = keycap.min_size = 32; keycap.line_height = 42; keycap.weight = 700;
        keycap.padding = 12; keycap.radius = 12; keycap.text_color = 0xfff2f2ee; keycap.plate_color = 0xb816171b;
        keycap.rise = 10; keycap.fade_us = 160000;
        keycap.smooth_mass = 1; keycap.smooth_stiffness = 260; keycap.smooth_damping = 32;
        stage = "render shortcut with private signal font"; RenderLocalVideo(shortcut, cancel, [](double) {});
        stage = "verify shortcut safe edges, entrance rise and fade"; VerifyShortcutPixels(shortcut);
        shortcut.output = prefix + (vertical ? L"-shortcut-invalid-portrait.mp4" : L"-shortcut-invalid-wide.mp4");
        shortcut.shortcut_badges.front().text = L"private typing";
        bool rejected_shortcut = false;
        try { RenderLocalVideo(shortcut, cancel, [](double) {}); } catch (...) { rejected_shortcut = true; }
        Require(rejected_shortcut && !std::filesystem::exists(shortcut.output));
        zoomed.output = prefix + (vertical ? L"-click-portrait.mp4" : L"-click-wide.mp4");
        zoomed.click_pulses = {{700000, 1120000, .8, .5, kWidth, kHeight}};
        zoomed.click_layout = {10, 4.4, 3, .12, 1, 260, 32, 0xfff2b84b};
        stage = "render click under zoom"; RenderLocalVideo(zoomed, cancel, [](double) {});
        stage = "verify decoded click onset and fade"; VerifyClickPixels(zoomed, true);
        if (!vertical) {
          zoomed.zoom_steps.clear(); zoomed.camera = zoom_source;
          zoomed.camera_inset = .28; zoomed.camera_margin = .04;
          zoomed.click_pulses = {{700000, 1120000, .9, .9, kWidth, kHeight}};
          zoomed.output = prefix + L"-click-camera-protected.mp4";
          stage = "render camera protected from click overlay"; RenderLocalVideo(zoomed, cancel, [](double) {});
          auto baseline = zoomed; baseline.click_pulses.clear(); baseline.output = prefix + L"-click-camera-baseline.mp4";
          stage = "render camera baseline without click"; RenderLocalVideo(baseline, cancel, [](double) {});
          stage = "verify click cannot paint camera"; VerifyClickPixels(zoomed, false, baseline.output);
        }
      }
      LocalRenderRequest request{source, source, prefix + L"-pair.mp4", 4000000, 640, 360, {{1000000, 2000000}, {3000000, 4000000}}};
      request.camera_inset = .28; request.camera_margin = .04;
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
      const auto join_source = prefix + L"-join-source.mp4";
      stage = "generate sound join source"; GenerateExtra(device.get(), join_source, 1, kRate, 0xff25b64a);
      auto joins = request; joins.source = join_source; joins.source_duration_us = 1000000;
      joins.ranges = {{123000, 623000}, {201000, 701000}}; joins.output = prefix + L"-join-raw.mp4";
      stage = "render untreated sound join"; RenderLocalVideo(joins, cancel, [](double) {});
      const auto raw_join = Audio(joins.output);
      joins.audio_join_fade_us = 20000; joins.output = prefix + L"-join-soft.mp4";
      stage = "render softened sound join"; RenderLocalVideo(joins, cancel, [](double) {});
      VerifyLocalCut(joins, 30, 1000000); const auto soft_join = Audio(joins.output);
      stage = "verify decoded join attenuation and untouched distant speech";
      const auto raw_level = WindowRms(raw_join, 23904, 192), soft_level = WindowRms(soft_join, 23904, 192);
      if (!(raw_level > 5000 && soft_level < raw_level * .65))
        std::cout << "Generated sound join RMS: raw=" << raw_level << " soft=" << soft_level << "\n";
      Require(raw_level > 5000 && soft_level < raw_level * .65);
      for (size_t at : {12000u, 36000u}) Require(std::abs(WindowRms(raw_join, at, 960) - WindowRms(soft_join, at, 960)) < 500);
      joins.ranges = {{0, 1000000}}; joins.audio_join_fade_us = 0; joins.output = prefix + L"-join-whole.mp4";
      stage = "render continuous sound reference"; RenderLocalVideo(joins, cancel, [](double) {}); const auto whole_join = Audio(joins.output);
      joins.ranges = {{0, 500000}, {500000, 1000000}}; joins.audio_join_fade_us = 20000; joins.output = prefix + L"-join-continuous.mp4";
      stage = "render adjacent ranges without a fade"; RenderLocalVideo(joins, cancel, [](double) {});
      Require(Audio(joins.output) == whole_join);
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
      request.caption_layout.karaoke = true;
      request.caption_layout.font_size = 52; request.caption_layout.line_height = 62; request.caption_layout.weight = 600;
      request.caption_layout.waiting_color = 0x80ffffff; request.caption_layout.underline_color = 0xffffc66d;
      request.caption_layout.underline_size = 3; request.caption_layout.underline_gap = 3;
      for (UINT language = 0; language < 5; ++language) {
        if (language == 3) continue; // Long two-line Readable phrase exceeds seven timed words.
        request.width = language == 4 ? 1080 : 1920; request.height = language == 4 ? 1920 : 1080;
        request.caption_layout.rtl = language == 2 || language == 4;
        RenderCaption phrase{200000, 800000, text[language]};
        std::vector<std::pair<UINT, UINT>> parts;
        for (UINT offset = 0; offset < phrase.text.size();) {
          const auto space = phrase.text.find(L' ', offset), end = space == std::wstring::npos ? phrase.text.size() : space;
          parts.push_back({offset, static_cast<UINT>(end - offset)}); offset = static_cast<UINT>(end + 1);
        }
        for (size_t i = 0; i < parts.size(); ++i) {
          const auto start = i == 0 ? 200000 : 500000 + static_cast<int64_t>(i - 1) * 300000 / static_cast<int64_t>(parts.size() - 1);
          const auto end = i == 0 ? 400000 : 500000 + static_cast<int64_t>(i) * 300000 / static_cast<int64_t>(parts.size() - 1);
          phrase.words.push_back({parts[i].first, parts[i].second, start, end});
        }
        request.captions = {phrase}; request.output = prefix + L"-karaoke-" + std::to_wstring(language) + L".mp4";
        stage = "render timed Karaoke"; RenderLocalVideo(request, cancel, [](double) {});
        stage = "verify word fill, RTL sweep, gap and safe pixels"; VerifyKaraokePixels(request);
      }
      request.output = prefix + L"-karaoke-invalid.mp4"; request.captions.front().words.front().offset = 1;
      bool timing_rejected = false; stage = "reject malformed Karaoke range";
      try { RenderLocalVideo(request, cancel, [](double) {}); } catch (...) { timing_rejected = true; }
      Require(timing_rejected && GetFileAttributesW(request.output.c_str()) == INVALID_FILE_ATTRIBUTES);
      request.caption_layout = CaptionFixture(); request.width = 1080; request.height = 1920;
      for (UINT language = 0; language < 3; ++language) for (bool punch : {false, true}) for (bool moving : {false, true}) {
        request.width = language == 2 ? 1080 : 1920; request.height = language == 2 ? 1920 : 1080;
        request.caption_layout = CaptionFixture(); request.caption_layout.rtl = language == 2;
        request.caption_layout.cue = !punch; request.caption_layout.punch = punch; request.caption_layout.motion = moving;
        if (punch) { request.caption_layout.font_size = 96; request.caption_layout.line_height = 100; request.caption_layout.weight = 800; }
        const wchar_t* phrases[] = {L"We launch today.", L"Nous lan\u00e7ons demain.", L"\u0646\u062d\u0646 \u0646\u0640\u0640\u0640\u0628\u062f\u0623 \u0627\u0644\u0622\u0646."};
        const std::wstring phrase(phrases[language]); request.captions.clear();
        const auto first_space = phrase.find(L' '), second_space = phrase.find(L' ', first_space + 1);
        const UINT offsets[] = {0, static_cast<UINT>(first_space + 1), static_cast<UINT>(second_space + 1)};
        const UINT lengths[] = {static_cast<UINT>(first_space), static_cast<UINT>(second_space - first_space - 1), static_cast<UINT>(phrase.size() - second_space - 1)};
        if (punch) {
          for (UINT i = 0; i < 3; ++i) request.captions.push_back({200000 + i * 200000, 400000 + i * 200000,
            phrase.substr(offsets[i], lengths[i]), {{0, lengths[i], 200000 + i * 200000, 400000 + i * 200000, i == 1, false, i == 2 ? -1 : 0}}});
        } else {
          RenderCaption caption{200000, 800000, phrase};
          for (UINT i = 0; i < 3; ++i) caption.words.push_back({offsets[i], lengths[i], 200000 + i * 200000, 400000 + i * 200000, i == 1, false, i == 2 ? -1 : 0});
          request.captions = {caption};
        }
        request.output = prefix + L"-motion-" + std::to_wstring(language) + (punch ? L"-punch" : L"-cue") + (moving ? L"-moving.mp4" : L"-still.mp4");
        stage = "render cue-shaped captions"; RenderLocalVideo(request, cancel, [](double) {});
        stage = "verify Cue/Punch reveal, emphasis, springs and safe pixels"; VerifyMotionPixels(request);
      }
      request.caption_layout = CaptionFixture(); request.width = 1080; request.height = 1920;
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
    std::cout << "Local render check passed: streaming PCM/GPU pair, source selection/reordering, reviewed filler and retake tone/picture removal, silent input, stereo resampling, EN/FR/AR Readable/Karaoke/Cue/Punch timing and safe pixels, word reveal, emphasis, spring motion and Still, RTL underline, gaps, vertical Arabic, no clipped words, camera inset/end, exact portrait duration, cancel cleanup, damaged input and overwrite protection.\n";
    MFShutdown(); CoUninitialize(); return 0;
  } catch (...) {
    std::cerr << "Local render check failed at " << stage << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    MFShutdown(); CoUninitialize(); return 1;
  }
}

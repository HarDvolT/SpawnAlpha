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

void GenerateZoomSource(ID3D11Device* device, const std::wstring& path, UINT frames = 120) {
  GpuVideoWriter writer; check_hresult(writer.Start(device, path, kWidth, kHeight, 30));
  std::vector<uint32_t> pixels(kWidth * kHeight);
  for (UINT y = 0; y < kHeight; ++y) for (UINT x = 0; x < kWidth; ++x)
    pixels[y * kWidth + x] = x < kWidth * .4 ? 0xff306be0 : x > kWidth * .6 ? 0xffe04830 : 0xff25b64a;
  D3D11_TEXTURE2D_DESC desc{}; desc.Width = kWidth; desc.Height = kHeight;
  desc.MipLevels = desc.ArraySize = 1; desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  D3D11_SUBRESOURCE_DATA data{pixels.data(), kWidth * 4, 0}; com_ptr<ID3D11Texture2D> texture;
  check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
  for (UINT frame = 0; frame < frames; ++frame)
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

ScreenFrameLayout FrameFixture() {
  return {true, .06, 12, 0xff171a20, 0xff0f1115, {{0x80000000, 0, 8, 14.356406}, {0x66000000, 0, 1, 1.654701}}};
}
void VerifyFramePixels(const LocalRenderRequest& request) {
  const auto pixels = FramePixels(request.output, request.width, request.height, 0);
  const RECT box = request.height > request.width ? RECT{64, 692, 1016, 1227} : RECT{115, 65, 1805, 1015};
  auto pixel = [&](LONG x, LONG y) { return pixels.data() + (y * request.width + x) * 4; };
  const auto* corner = pixel(box.left, box.top);
  Require(corner[0] < 60 && corner[1] < 60 && corner[2] < 60); // Rounded source corner is masked.
  for (const auto fraction : {.2, .5, .8}) {
    const auto* value = pixel(box.left + static_cast<LONG>((box.right - box.left) * fraction), (box.top + box.bottom) / 2);
    if (fraction == .2) Require(value[0] > value[2] + 80);
    if (fraction == .5) Require(value[1] > value[2] + 80);
    if (fraction == .8) Require(value[2] > value[1] + 80);
  }
  const auto* outer = pixel(10, 10);
  Require(outer[0] > 15 && outer[0] < 45 && outer[2] > 8 && outer[2] < 35); // Generated dark backdrop, not black.
  SaveCaptionPng(request.output + L".frame.png", request.width, request.height, pixels.data());
  const auto late = FramePixels(request.output, request.width, request.height, 30);
  const auto center = ((box.top + box.bottom) / 2 * request.width + (box.left + box.right) / 2) * 4;
  Require(late[center + 2] > late[center + 1] + 80); // Zoom inside the fixed inset.
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
        RECT region{0, 0, static_cast<LONG>(request.width), static_cast<LONG>(request.height)};
        if (request.screen_frame.enabled) {
          // Inset resampling blends unrelated bar boundaries into amber. Inspect
          // only the real retained click's neighborhood on its current crop.
          ScreenZoom zoom; zoom.Open(request.zoom_steps, request.zoom_spring, kWidth, kHeight, 4000000);
          const auto crop = zoom.Crop({0, 0, static_cast<LONG>(kWidth), static_cast<LONG>(kHeight)}, time / 10);
          const RECT box = request.height > request.width ? RECT{64, 692, 1016, 1227} : RECT{115, 65, 1805, 1015};
          const auto x = box.left + static_cast<LONG>((kWidth * .8 - crop.left) / (crop.right - crop.left) * (box.right - box.left));
          const auto y = box.top + static_cast<LONG>((kHeight * .5 - crop.top) / (crop.bottom - crop.top) * (box.bottom - box.top));
          region = {x - 60, y - 60, x + 60, y + 60};
        }
        for (LONG y = region.top; y < region.bottom; ++y) for (LONG x = region.left; x < region.right; ++x) {
          const size_t i = (y * request.width + x) * 4;
          if (pixels[i + 2] > 170 && pixels[i + 1] > 100 && pixels[i + 1] < 210 && pixels[i] < 110) ++amber;
        }
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

void GenerateExtra(ID3D11Device* device, const std::wstring& path, UINT channels, UINT rate, uint32_t color, double amplitude = 12000) {
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
      pcm[index * channels + ch] = static_cast<int16_t>(std::sin((frame * (rate / 30) + index) * hz * 6.283185307179586 / rate) * amplitude);
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

void VerifyLocalCut(const LocalRenderRequest& request, int expected_frames, int64_t expected_us, bool early_camera = false, bool filler_removed = false, bool aac_padding = false) {
  std::atomic<bool> cancel{false}; const auto probe = ProbeRecording(request.output, cancel);
  Require(probe.readable && probe.width == static_cast<int>(request.width) && probe.height == static_cast<int>(request.height));
  // Some AAC streams advertise final packet padding in container duration;
  // decoded video presentation times/end below must still be exact.
  Require(std::abs(probe.duration_100ns - expected_us * 10) < (aac_padding ? kSecond * 1024 / kRate : 100000));
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
RECT PunchPicture(const LocalRenderRequest& request) {
  RECT box{0, 0, static_cast<LONG>(request.width), static_cast<LONG>(request.height)};
  if (!request.punch_main) {
    const LONG margin = static_cast<LONG>(std::min(request.width, request.height) * request.camera_margin);
    const LONG width = static_cast<LONG>(request.width * request.camera_inset);
    const LONG height = std::min(static_cast<LONG>(request.height * request.camera_inset), width);
    box = {box.right - margin - width, box.bottom - margin - height, box.right - margin, box.bottom - margin};
  }
  const auto scale = std::min(static_cast<double>(box.right - box.left) / kWidth,
    static_cast<double>(box.bottom - box.top) / kHeight);
  const LONG width = static_cast<LONG>(kWidth * scale), height = static_cast<LONG>(kHeight * scale);
  const LONG x = box.left + (box.right - box.left - width) / 2, y = box.top + (box.bottom - box.top - height) / 2;
  return {x, y, x + width, y + height};
}
int GreenWidth(const std::vector<BYTE>& pixels, UINT width, const RECT& box) {
  const auto y = (box.top + box.bottom) / 2; int green = 0;
  for (LONG x = box.left; x < box.right; ++x) {
    const auto* value = pixels.data() + (y * width + x) * 4;
    if (value[1] > value[0] + 60 && value[1] > value[2] + 60) ++green;
  }
  return green;
}
void CheckCameraPunch(ID3D11Device* device, const std::wstring& prefix, const char*& stage) {
  const auto source = prefix + L"-punch-source.mp4";
  stage = "generate 25-second camera emphasis bars"; GenerateZoomSource(device, source, 750);
  std::atomic<bool> cancel{false};
  for (bool main : {true, false}) for (bool portrait : {false, true}) {
    LocalRenderRequest request{source, main ? L"" : source, L"", 25000000,
      portrait ? 540u : 960u, portrait ? 960u : 540u, {{0, 25000000}}};
    request.camera_inset = .28; request.camera_margin = .04;
    request.punch_main = main; request.punch_factor = 1.12; request.punch_spring = {1, 90, 19};
    request.punch_steps = {{1000000, true}, {2600000, false}, {9000000, true}, {10600000, false}};
    if (!main) request.screen_frame = FrameFixture();
    request.output = prefix + (main ? L"-punch-main" : L"-punch-pair") + (portrait ? L"-portrait.mp4" : L"-wide.mp4");
    stage = "render centre camera emphasis on a fixed rectangle";
    std::cout << "Generated camera render: " << (main ? "main" : "pair") << (portrait ? " portrait" : " wide") << std::endl;
    RenderLocalVideo(request, cancel, [](double) {});
    const auto before = FramePixels(request.output, request.width, request.height, 0);
    const auto during = FramePixels(request.output, request.width, request.height, 60);
    const auto after = FramePixels(request.output, request.width, request.height, 120);
    const auto box = PunchPicture(request);
    stage = "verify subtle camera crop and full-picture return";
    const auto original = GreenWidth(before, request.width, box), zoomed = GreenWidth(during, request.width, box);
    Require(original > 20 && zoomed >= original * 1.08 && zoomed <= original * 1.18);
    Require(std::abs(GreenWidth(after, request.width, box) - original) <= 2);
    const auto center = ((box.top + box.bottom) / 2 * request.width + (box.left + box.right) / 2) * 4;
    Require(during[center + 1] > during[center] + 60 && during[center + 1] > during[center + 2] + 60);
    if (!main) {
      const auto bounds = ScreenFrameBounds(request.width, request.height, request.screen_frame);
      RECT screen{bounds.left, static_cast<LONG>(request.height / 2), bounds.right, static_cast<LONG>(request.height / 2 + 2)};
      Require(GreenWidth(before, request.width, screen) == GreenWidth(during, request.width, screen));
      for (const auto fraction : {.1, .9}) {
        const auto location = ((box.top + box.bottom) / 2 * request.width + box.left + static_cast<LONG>((box.right - box.left) * fraction)) * 4;
        Require(std::abs(static_cast<int>(before[location]) - during[location]) < 12 &&
          std::abs(static_cast<int>(before[location + 2]) - during[location + 2]) < 12);
      }
    }
    SaveCaptionPng(request.output + L".png", request.width, request.height, during.data());
    auto cut = request; cut.output = request.output + L"-cut.mp4"; cut.ranges = {{0, 2000000}, {4000000, 25000000}};
    cut.punch_steps[1].time_us = 2000000;
    stage = "render camera return at source cut"; RenderLocalVideo(cut, cancel, [](double) {});
    const auto reset = FramePixels(cut.output, cut.width, cut.height, 60);
    Require(std::abs(GreenWidth(reset, cut.width, box) - original) <= 2);
    const auto probe = ProbeRecording(cut.output, cancel);
    Require(probe.readable && std::abs(probe.duration_100ns - 230000000) < 100000);
  }
  LocalRenderRequest invalid{source, L"", prefix + L"-punch-invalid.mp4", 25000000, 640, 360, {{0, 25000000}}};
  invalid.punch_main = true; invalid.punch_factor = 1.12; invalid.punch_spring = {1, 90, 19};
  invalid.punch_steps = {{1000000, true}, {2600000, false}};
  for (int variation = 0; variation < 5; ++variation) {
    auto bad = invalid;
    if (variation == 0) bad.ranges = {{0, 19000000}};
    if (variation == 1) bad.punch_factor = 2;
    if (variation == 2) bad.punch_steps.push_back({3000000, true});
    if (variation == 3) { bad.punch_steps.push_back({4000000, true}); bad.punch_steps.push_back({5000000, false}); }
    if (variation == 4) bad.punch_main = false;
    stage = "reject short or malformed camera emphasis before creating output";
    bool rejected = false; try { RenderLocalVideo(bad, cancel, [](double) {}); } catch (...) { rejected = true; }
    Require(rejected && GetFileAttributesW(bad.output.c_str()) == INVALID_FILE_ATTRIBUTES);
  }
}
void CheckCameraPlacement(ID3D11Device* device, const std::wstring& prefix, const char*& stage) {
  stage = "verify camera placement geometry, stability, zoom and source resets";
  const RECT screen{0, 0, 1000, 1000}, camera{700, 700, 960, 960};
  CameraClearLayout layout{true, 24, 1400000, {1, 90, 19}};
  CameraPlacement movement;
  movement.Open({{100000, 900000, .8, .8, 1000, 1000}, {2000000, 3000000, .1, .8, 1000, 1000}}, {}, layout, 4000000, 1000, 1000);
  movement.Reset(0);
  Require(movement.Place(0, screen, screen, screen, camera, 40).left == 700);
  const auto first = movement.Place(100000, screen, screen, screen, camera, 40);
  Require(first.left == 700);
  const auto moving = movement.Place(400000, screen, screen, screen, camera, 40);
  Require(moving.left > 40 && moving.left < 700 && moving.top == camera.top && moving.right - moving.left == 260);
  Require(movement.Place(1500000, screen, screen, screen, camera, 40).left <= 41);
  movement.Place(2000000, screen, screen, screen, camera, 40);
  Require(movement.Place(3400000, screen, screen, screen, camera, 40).left >= 699);
  movement.Reset(3500000);
  Require(movement.Place(3500000, screen, screen, screen, camera, 40).left == 700);
  CameraPlacement zoom;
  zoom.Open({}, {{0, .8, .8, 1.8, 1000, 1000}, {2000000, .8, .8, 1, 1000, 1000}}, layout, 4000000, 1000, 1000);
  zoom.Reset(0); zoom.Place(0, screen, screen, screen, camera, 40);
  Require(zoom.Place(1500000, screen, screen, screen, camera, 40).left <= 41);
  // An out-of-viewport target must not displace the camera.
  CameraPlacement cropped;
  cropped.Open({{0, 4000000, .9, .9, 1000, 1000}}, {}, layout, 4000000, 1000, 1000);
  cropped.Reset(0); const RECT crop{0, 0, 500, 500};
  Require(cropped.Place(0, screen, crop, screen, camera, 40).left == 700);
  Require(cropped.Place(1500000, screen, crop, screen, camera, 40).left == 700);
  for (int variant = 0; variant < 4; ++variant) {
    auto bad = layout; if (variant == 0) bad.gap = NAN;
    if (variant == 1) bad.interval_us = 0;
    if (variant == 2) bad.spring.mass = 0;
    std::vector<CameraTarget> t{{0, variant == 3 ? 5000000 : 4000000, .8, .8, 1000, 1000}};
    bool rejected = false; try { CameraPlacement invalid; invalid.Open(t, {}, bad, 4000000, 1000, 1000); } catch (...) { rejected = true; }
    Require(rejected);
  }
  const auto source = prefix + L"-clear-screen.mp4", paired = prefix + L"-clear-camera.mp4";
  stage = "generate camera placement screen and camera colours";
  GenerateZoomSource(device, source); GenerateZoomSource(device, paired);
  std::atomic<bool> cancel{false};
  for (bool framed : {false, true}) {
    LocalRenderRequest request{source, paired, prefix + (framed ? L"-clear-frame.mp4" : L"-clear.mp4"), 4000000, 960, 540, {{0, 4000000}}};
    request.camera_inset = .28; request.camera_margin = .04; request.camera_clear = layout;
    request.camera_targets = {{100000, 3000000, .85, .85, kWidth, kHeight}};
    if (framed) request.screen_frame = FrameFixture();
    stage = "render moving camera with shared frame and click geometry";
    RenderLocalVideo(request, cancel, [](double) {});
    const auto before = FramePixels(request.output, request.width, request.height, 0);
    const auto during = FramePixels(request.output, request.width, request.height, 45);
    const UINT left = (440 * request.width + 40) * 4, right = (440 * request.width + 710) * 4;
    // Camera bars replace the blue screen at the left and reveal red screen at the right.
    Require(before[left + 2] < 100 && during[left + 2] < 100);
    const UINT center_left = (440 * request.width + 154) * 4;
    Require(before[center_left + 1] < 130 && during[center_left + 1] > 150);
    Require(before[right] > 150 && during[right + 2] > 150);
    SaveCaptionPng(request.output + L".png", request.width, request.height, during.data());
    auto split = request; split.output += L"-split.mp4"; split.ranges = {{0, 700000}, {700000, 4000000}};
    stage = "verify continuous split leaves camera pixels identical"; RenderLocalVideo(split, cancel, [](double) {});
    Require(FramePixels(split.output, split.width, split.height, 45) == during);
    auto cut = request; cut.output += L"-cut.mp4"; cut.ranges = {{0, 2000000}, {3000000, 4000000}};
    cut.camera_targets.front().end_us = 2000000;
    stage = "verify camera reset at a discontinuous source cut"; RenderLocalVideo(cut, cancel, [](double) {});
    const auto reset = FramePixels(cut.output, cut.width, cut.height, 60);
    Require(reset[center_left + 1] < 130 && reset[right] > 150);
  }
}
void CheckScreenMotionBlur(ID3D11Device* device, const std::wstring& prefix, const char*& stage) {
  stage = "verify screen blur motion cap, direction, stillness and reset";
  const ScreenBlurLayout layout{true, 6, .5, 16000};
  ViewportMotion motion; motion.Open(layout, 1920, 1080);
  const RECT full{0, 0, 1000, 1000}, picture{0, 0, 1920, 1080};
  Require(motion.Sample(full, picture, 0).radius == 0);
  Require(motion.Sample(full, picture, 33333).radius == 0);
  const RECT pan{100, 0, 1100, 1000};
  const auto moving = motion.Sample(pan, picture, 66666);
  Require(moving.radius == 6 && std::abs(std::abs(moving.angle) - 180) < .001);
  Require(motion.Sample(pan, picture, 99999).radius == 0);
  motion.Reset(); Require(motion.Sample(full, picture, 200000).radius == 0);
  for (int variant = 0; variant < 3; ++variant) {
    auto bad = layout; if (variant == 0) bad.maximum = NAN;
    if (variant == 1) bad.minimum = 10; if (variant == 2) bad.shutter_us = 0;
    bool rejected = false; try { ViewportMotion invalid; invalid.Open(bad, 1920, 1080); } catch (...) { rejected = true; }
    Require(rejected);
  }
  const auto source = prefix + L"-blur-source.mp4";
  stage = "generate sharp bars for screen motion blur"; GenerateZoomSource(device, source);
  std::atomic<bool> cancel{false};
  for (bool paired : {false, true}) {
    LocalRenderRequest request{source, paired ? source : L"", L"", 4000000, 960, 540, {{0, 4000000}}};
    request.camera_inset = .28; request.camera_margin = .04; request.screen_frame = FrameFixture();
    request.zoom_spring = {1, 90, 19}; request.zoom_steps = {{100000, .5, .5, 1.8, kWidth, kHeight}, {2000000, .5, .5, 1, kWidth, kHeight}};
    request.output = prefix + (paired ? L"-blur-pair-plain.mp4" : L"-blur-plain.mp4");
    stage = "render unblurred comparison"; RenderLocalVideo(request, cancel, [](double) {});
    const auto plain = request.output;
    request.output = prefix + (paired ? L"-blur-pair.mp4" : L"-blur.mp4"); request.screen_blur = layout;
    stage = "render screen motion blur before independent camera"; RenderLocalVideo(request, cancel, [](double) {});
    stage = "verify initial screen blur frame stays sharp";
    const auto before = FramePixels(request.output, request.width, request.height, 0);
    Require(before == FramePixels(plain, request.width, request.height, 0));
    stage = "verify motion changes screen edges only";
    const auto blurred = FramePixels(request.output, request.width, request.height, 6);
    const auto sharp = FramePixels(plain, request.width, request.height, 6);
    int changed = 0;
    for (UINT y = 100; y < 300; ++y) for (UINT x = 100; x < 860; ++x) {
      const auto i = (y * request.width + x) * 4;
      if (std::abs(static_cast<int>(blurred[i]) - sharp[i]) +
          std::abs(static_cast<int>(blurred[i + 1]) - sharp[i + 1]) +
          std::abs(static_cast<int>(blurred[i + 2]) - sharp[i + 2]) > 12) ++changed;
    }
    Require(changed > 200 && changed < 12000);
    stage = "verify paired camera stays sharp during screen blur";
    if (paired) {
      int64_t difference = 0, pixels = 0;
      for (UINT y = 400; y < 500; ++y) for (UINT x = 700; x < 920; ++x) {
        const auto i = (y * request.width + x) * 4;
        for (UINT c = 0; c < 3; ++c) difference += std::abs(static_cast<int>(blurred[i + c]) - sharp[i + c]);
        ++pixels;
      }
      Require(difference < pixels * 3);
    }
    stage = "verify settled screen blur frame stays sharp";
    const auto after = FramePixels(request.output, request.width, request.height, 110);
    Require(after == FramePixels(plain, request.width, request.height, 110));
    SaveCaptionPng(request.output + L".png", request.width, request.height, blurred.data());
    auto split = request; split.output += L"-split.mp4"; split.ranges = {{0, 300000}, {300000, 4000000}};
    stage = "verify continuous split preserves blur pixels"; RenderLocalVideo(split, cancel, [](double) {});
    Require(FramePixels(split.output, split.width, split.height, 6) == blurred);
    auto cut = request; cut.output += L"-cut.mp4"; cut.ranges = {{0, 700000}, {2000000, 4000000}};
    cut.zoom_steps.back().time_us = 700000;
    stage = "verify source cut resets blur without a flash"; RenderLocalVideo(cut, cancel, [](double) {});
    auto cut_plain = cut; cut_plain.output += L"-plain.mp4"; cut_plain.screen_blur.enabled = false;
    RenderLocalVideo(cut_plain, cancel, [](double) {});
    const auto reset = FramePixels(cut.output, cut.width, cut.height, 21), reset_plain = FramePixels(cut_plain.output, cut.width, cut.height, 21);
    int64_t delta = 0; int maximum = 0;
    for (size_t i = 0; i < reset.size(); ++i) {
      const auto d = std::abs(static_cast<int>(reset[i]) - reset_plain[i]); delta += d; maximum = std::max(maximum, d);
    }
    std::cout << "Generated source-reset pixel difference: total=" << delta << " maximum=" << maximum << std::endl;
    Require(delta < static_cast<int64_t>(reset.size()) / 10 && maximum <= 8);
  }
}
void CheckWriterUnwind(ID3D11Device* device, const std::wstring& prefix) {
  for (bool queued : {false, true}) {
    const auto output = prefix + (queued ? L"-failed-queued.mp4" : L"-failed-empty.mp4");
    const auto started = GetTickCount64(); bool caught = false, injected = false;
    try {
      GpuVideoWriter writer; check_hresult(writer.Start(device, output, kWidth, kHeight, 30, {}, nullptr, false));
      if (queued) {
        std::vector<uint32_t> pixels(kWidth * kHeight, 0xff25b64a);
        D3D11_TEXTURE2D_DESC desc{}; desc.Width = kWidth; desc.Height = kHeight; desc.MipLevels = desc.ArraySize = 1;
        desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
        D3D11_SUBRESOURCE_DATA data{pixels.data(), kWidth * 4, 0}; com_ptr<ID3D11Texture2D> texture;
        check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
        check_hresult(writer.WriteFrame(texture.get(), kWidth, kHeight, 0));
      }
      injected = true; throw std::runtime_error("Generated failure after startup");
    } catch (...) { caught = true; }
    Require(caught && injected && GetTickCount64() - started < 5000 && DeleteFileW(output.c_str()));
  }
}
double MeasureSound(const std::vector<int16_t>& pcm, UINT channels, double* peak = nullptr) {
  AudioLoudness meter(channels);
  for (size_t first = 0; first < pcm.size(); first += 1024 * channels) {
    const auto end = std::min(pcm.size(), first + 1024 * channels);
    meter.Add({pcm.begin() + first, pcm.begin() + end});
  }
  const auto gain = meter.Finish({true});
  Require(std::isfinite(gain));
  if (peak) *peak = meter.peak();
  return meter.loudness();
}
void CheckSoundMeter() {
  constexpr double pi = 6.283185307179586;
  for (UINT channels : {1u, 2u}) {
    std::vector<int16_t> sine(96000 * channels);
    for (size_t f = 0; f < 96000; ++f) for (UINT c = 0; c < channels; ++c)
      sine[f * channels + c] = static_cast<int16_t>(32768 * std::pow(10.0, -18.0 / 20) * std::sin(f * 1000 * pi / 48000));
    double reference = 0;
    for (size_t packet : {1u, 7u, 1024u, 48000u}) {
      AudioLoudness meter(channels);
      for (size_t first = 0; first < sine.size(); first += packet * channels)
        meter.Add({sine.begin() + first, sine.begin() + std::min(sine.size(), first + packet * channels)});
      const auto gain = meter.Finish({true});
      Require(std::abs(meter.loudness() - (channels == 1 ? -21.0 : -17.99)) < .1);
      if (reference) Require(std::abs(reference - gain) < 1e-12); else reference = gain;
      auto normalized = sine; ApplySoundGain(normalized, gain);
      Require(std::abs(MeasureSound(normalized, channels) + 14) < .03);
      bool rejected = false; try { meter.Finish({true}); } catch (...) { rejected = true; } Require(rejected);
    }
    for (size_t frames : {1u, 19199u, 19200u, 96000u}) {
      AudioLoudness silent(channels);
      for (size_t first = 0; first < frames; first += 48000)
        silent.Add(std::vector<int16_t>(std::min<size_t>(48000, frames - first) * channels, 0));
      Require(silent.Finish({true}) == 1);
    }
    AudioLoudness short_sound(channels); short_sound.Add(std::vector<int16_t>(19199 * channels, 100));
    Require(short_sound.Finish({true}) == 1);
    AudioLoudness disabled(channels); disabled.Add({sine.begin(), sine.begin() + 48000 * channels});
    Require(disabled.Finish({false}) == 1);
    auto low = sine; for (auto& value : low) value = static_cast<int16_t>(value / 1000);
    Require(!std::isfinite(MeasureSound(low, channels))); // Below the absolute gate.
    AudioLoudness gated(channels);
    for (size_t first = 0; first < sine.size(); first += 48000 * channels)
      gated.Add({sine.begin() + first, sine.begin() + first + 48000 * channels});
    for (size_t first = 0; first < low.size(); first += 48000 * channels)
      gated.Add({low.begin() + first, low.begin() + first + 48000 * channels});
    gated.Finish({true}); Require(std::abs(gated.loudness() - (channels == 1 ? -21.0 : -17.99)) < .5);
  }
  std::vector<int16_t> overs(48000);
  for (size_t i = 0; i < overs.size(); ++i) overs[i] = static_cast<int16_t>(i % 4 < 2 ? 22937 : -22937);
  AudioLoudness peak(1); peak.Add(overs); const auto gain = peak.Finish({true});
  Require(peak.peak() > .9 && gain * peak.peak() <= std::pow(10.0, -2.0 / 20) + 1e-12);
  std::vector<int16_t> transient(48000, 0);
  for (size_t i = 0; i < transient.size(); ++i) transient[i] = static_cast<int16_t>(100 * std::sin(i * 1000 * pi / 48000));
  transient[24000] = 30000;
  AudioLoudness limited(1); limited.Add(transient); const auto capped = limited.Finish({true});
  Require(capped <= std::pow(10.0, 12.0 / 20) && capped * limited.peak() <= std::pow(10.0, -2.0 / 20) + 1e-12);
  auto treated = transient; ApplySoundGain(treated, capped); Require(treated.size() == transient.size());
  for (UINT channels : {0u, 3u}) { bool caught = false; try { AudioLoudness invalid(channels); } catch (...) { caught = true; } Require(caught); }
  for (double target : {1.0, -100.0, std::numeric_limits<double>::quiet_NaN()}) {
    bool caught = false; try { AudioLoudness invalid(1); invalid.Finish({true, target}); } catch (...) { caught = true; } Require(caught);
  }
  bool caught = false; try { AudioLoudness invalid(2); invalid.Add({1}); } catch (...) { caught = true; } Require(caught);
}
void CheckSoundBalance(ID3D11Device* device, const std::wstring& prefix, const char*& stage) {
  std::atomic<bool> cancel{false};
  const auto source = prefix + L"-sound-source.mp4";
  stage = "generate four-second sound fixture"; Generate(device, source);
  for (UINT channels : {1u, 2u}) for (UINT rate : {48000u, 44100u}) for (UINT amplitude : {2000u, 12000u}) {
    const auto extra = prefix + L"-sound-" + std::to_wstring(channels) + L"-" + std::to_wstring(rate) + L"-" + std::to_wstring(amplitude);
    GenerateExtra(device, extra + L"-source.mp4", channels, rate, 0xff25b64a, amplitude);
    LocalRenderRequest request{extra + L"-source.mp4", L"", extra + L"-raw.mp4", 1000000, 640, 360, {{0, 1000000}}};
    stage = "render original sound reference"; RenderLocalVideo(request, cancel, [](double) {});
    const auto raw = Audio(request.output, channels); const auto raw_loudness = MeasureSound(raw, channels);
    request.sound_balance = {true}; request.output = extra + L"-balanced.mp4";
    stage = "render balanced mono/stereo resampled sound";
    double previous = 0; RenderLocalVideo(request, cancel, [&](double value) { Require(value >= previous && value <= 1); previous = value; });
    const auto balanced = Audio(request.output, channels);
    stage = "verify decoded loudness, exact clocks and channel preservation";
    Require(previous == 1 && raw.size() == balanced.size());
    VerifyLocalCut(request, 30, 1000000);
    double decoded_peak = 0; const auto level = MeasureSound(balanced, channels, &decoded_peak);
    Require(decoded_peak < std::pow(10.0, -1.0 / 20)); // AAC headroom is retained.
    const auto expected = std::min(-14.0, raw_loudness + 12);
    if (std::abs(level - expected) >= .3) std::cout << "Generated LUFS raw=" << raw_loudness << " balanced=" << level << "\n";
    Require(std::abs(level - expected) < .3);
    for (UINT c = 0; c < channels; ++c) {
      std::vector<int16_t> a, b; for (size_t f = 0; f < raw.size() / channels; ++f) { a.push_back(raw[f * channels + c]); b.push_back(balanced[f * channels + c]); }
      Require(ToneAt(b, 12000, c ? 990 : 330) > 1000);
      const auto ratio = WindowRms(b, 12000, 12000) / WindowRms(a, 12000, 12000);
      Require(std::abs(20 * std::log10(ratio) - (expected - raw_loudness)) < .4);
    }
    request.output = extra + L"-continuous.mp4"; request.ranges = {{0, 500000}, {500000, 1000000}}; request.audio_join_fade_us = 20000;
    stage = "verify sound balance continuous splits are identical"; RenderLocalVideo(request, cancel, [](double) {});
    Require(Audio(request.output, channels) == balanced);
    request.ranges = {{0, 200000}}; request.output = extra + L"-short-balanced.mp4";
    stage = "verify short sound remains unchanged"; RenderLocalVideo(request, cancel, [](double) {}); const auto short_balanced = Audio(request.output, channels);
    request.sound_balance.enabled = false; request.output = extra + L"-short-raw.mp4"; RenderLocalVideo(request, cancel, [](double) {});
    Require(Audio(request.output, channels) == short_balanced);
  }
  LocalRenderRequest cut{source, L"", prefix + L"-sound-cut.mp4", 4000000, 640, 360, {{3000000, 4000000}, {1000000, 2000000}}};
  cut.sound_balance = {true}; cut.audio_join_fade_us = 20000;
  stage = "verify retained/reordered sound balance and joins"; RenderLocalVideo(cut, cancel, [](double) {});
  const auto pcm = Audio(cut.output); Require(std::abs(MeasureSound(pcm, 1) + 14) < .3);
  Require(ToneAt(pcm, 12000, 880) > 1000 && ToneAt(pcm, 60000, 440) > 1000);
  VerifyLocalCut(cut, 60, 2000000);
  stage = "verify measurement cancellation before output ownership"; cut.output = prefix + L"-sound-cancel.mp4";
  bool stopped = false; try { RenderLocalVideo(cut, cancel, [&](double value) { if (value > .02) cancel = true; }); } catch (...) { stopped = true; }
  Require(stopped && GetFileAttributesW(cut.output.c_str()) == INVALID_FILE_ATTRIBUTES);
  cancel = false; const auto silent = prefix + L"-sound-silent.mp4"; GenerateExtra(device, silent, 0, 0, 0xff25b64a);
  cut.source = silent; cut.source_duration_us = 1000000; cut.ranges = {{0, 1000000}}; cut.output = prefix + L"-sound-silent-output.mp4";
  stage = "verify silent video has no invented audio"; RenderLocalVideo(cut, cancel, [](double) {}); Require(!ProbeRecording(cut.output, cancel).has_audio);
  const auto zero = prefix + L"-sound-zero.mp4"; GenerateExtra(device, zero, 1, 48000, 0xff25b64a, 0);
  cut.source = zero; cut.output = prefix + L"-sound-zero-balanced.mp4";
  stage = "verify silent PCM is unchanged"; RenderLocalVideo(cut, cancel, [](double) {}); const auto zero_pcm = Audio(cut.output);
  cut.sound_balance.enabled = false; cut.output = prefix + L"-sound-zero-raw.mp4"; RenderLocalVideo(cut, cancel, [](double) {});
  Require(Audio(cut.output) == zero_pcm); cut.sound_balance.enabled = true;
  cut.sound_balance.target = 1; cut.output = prefix + L"-sound-invalid.mp4";
  bool rejected = false; try { RenderLocalVideo(cut, cancel, [](double) {}); } catch (...) { rejected = true; }
  Require(rejected && GetFileAttributesW(cut.output.c_str()) == INVALID_FILE_ATTRIBUTES);
}
void CheckDeEsser() {
  for (UINT channels : {1u, 2u}) {
    std::vector<int16_t> original(48000 * channels), low(48000 * channels);
    for (size_t f = 0; f < 48000; ++f) for (UINT c = 0; c < channels; ++c) {
      const auto amplitude = c ? 6000 : 12000;
      original[f * channels + c] = static_cast<int16_t>(amplitude * std::sin(f * 8000 * 6.283185307179586 / 48000));
      low[f * channels + c] = static_cast<int16_t>(amplitude * std::sin(f * 330 * 6.283185307179586 / 48000));
    }
    auto processed = original; AudioDeEsser whole(channels, {true}); whole.Apply(processed);
    const auto ratio = WindowRms(processed, 24000 * channels, 12000 * channels) / WindowRms(original, 24000 * channels, 12000 * channels);
    Require(std::abs(20 * std::log10(ratio) + 3) < .01);
    for (size_t i = 0; i < original.size(); ++i) {
      Require(std::abs(processed[i]) <= std::abs(original[i]));
      if (channels == 2 && i % 2) Require(std::abs(processed[i - 1] - 2 * processed[i]) <= 2);
    }
    for (size_t size : {1u, 7u, 480u, 1024u}) {
      AudioDeEsser packets(channels, {true}); std::vector<int16_t> actual;
      for (size_t first = 0; first < original.size(); first += size * channels) {
        std::vector<int16_t> part(original.begin() + first, original.begin() + std::min(original.size(), first + size * channels));
        packets.Apply(part); actual.insert(actual.end(), part.begin(), part.end());
      }
      Require(actual == processed);
    }
    auto low_processed = low; AudioDeEsser fresh(channels, {true}); fresh.Apply(low_processed); Require(low_processed == low);
    whole.Reset(); low_processed = low; whole.Apply(low_processed); Require(low_processed == low);
    auto quiet = original; for (auto& value : quiet) value = static_cast<int16_t>(value / 100);
    const auto quiet_original = quiet; AudioDeEsser below_floor(channels, {true}); below_floor.Apply(quiet); Require(quiet == quiet_original);
    std::vector<int16_t> silent(48000 * channels, 0); whole.Apply(silent); Require(std::all_of(silent.begin(), silent.end(), [](int16_t value) { return value == 0; }));
    auto disabled = original; AudioDeEsser bypass(channels, {false}); bypass.Apply(disabled); Require(disabled == original);
  }
  for (double invalid : {0.0, 20000.0, std::numeric_limits<double>::quiet_NaN()}) {
    bool caught = false; try { AudioDeEsser bad(1, {true, invalid}); } catch (...) { caught = true; } Require(caught);
  }
  bool caught = false; try { AudioDeEsser bad(2, {true}); std::vector<int16_t> invalid{1}; bad.Apply(invalid); } catch (...) { caught = true; } Require(caught);
}
void GenerateEssSource(ID3D11Device* device, const std::wstring& path, UINT channels) {
  GpuVideoWriter writer; check_hresult(writer.Start(device, path, kWidth, kHeight, 30, {48000, channels}));
  std::vector<uint32_t> pixels(kWidth * kHeight, 0xff25b64a);
  D3D11_TEXTURE2D_DESC desc{}; desc.Width = kWidth; desc.Height = kHeight;
  desc.MipLevels = desc.ArraySize = 1; desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  D3D11_SUBRESOURCE_DATA data{pixels.data(), kWidth * 4, 0}; com_ptr<ID3D11Texture2D> texture;
  check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
  for (UINT frame = 0; frame < 120; ++frame) {
    check_hresult(writer.WriteFrame(texture.get(), kWidth, kHeight, frame * kSecond / 30));
    std::vector<int16_t> pcm(1600 * channels);
    for (UINT f = 0; f < 1600; ++f) for (UINT c = 0; c < channels; ++c) {
      const auto at = frame * 1600 + f; const auto hz = (at / 48000) % 2 ? 8000 : 330;
      pcm[f * channels + c] = static_cast<int16_t>((c ? 6000 : 12000) * std::sin(at * hz * 6.283185307179586 / 48000));
    }
    check_hresult(writer.WriteAudio(pcm.data(), 1600, frame * kSecond / 30));
  }
  check_hresult(writer.Finish());
}
void CheckDeEssExports(ID3D11Device* device, const std::wstring& prefix, const char*& stage) {
  std::atomic<bool> cancel{false};
  for (UINT channels : {1u, 2u}) {
    const auto source = prefix + L"-ess-source-" + std::to_wstring(channels) + L".mp4";
    stage = "generate alternating low and sibilant sound"; GenerateEssSource(device, source, channels);
    LocalRenderRequest request{source, L"", prefix + L"-ess-raw-" + std::to_wstring(channels) + L".mp4", 4000000, 640, 360, {{0, 4000000}}};
    stage = "render de-essing reference"; RenderLocalVideo(request, cancel, [](double) {}); const auto raw = Audio(request.output, channels);
    request.de_ess = {true}; request.output = prefix + L"-ess-soft-" + std::to_wstring(channels) + L".mp4";
    stage = "render linked de-essing without changing clocks"; RenderLocalVideo(request, cancel, [](double) {}); const auto soft = Audio(request.output, channels);
    stage = "verify de-essed video and audio sample clocks";
    if (raw.size() != soft.size()) std::cout << "Generated de-essing samples: " << raw.size() << " " << soft.size() << "\n";
    Require(raw.size() == soft.size()); VerifyLocalCut(request, 120, 4000000, false, false, true);
    stage = "verify distant low-frequency audio stays unchanged";
    for (size_t frame : {12000u, 108000u}) Require(std::abs(WindowRms(soft, frame * channels, 12000 * channels) / WindowRms(raw, frame * channels, 12000 * channels) - 1) < .03);
    stage = "verify decoded sibilant attenuation";
    for (size_t frame : {60000u, 156000u}) Require(std::abs(20 * std::log10(WindowRms(soft, frame * channels, 12000 * channels) / WindowRms(raw, frame * channels, 12000 * channels)) + 3) < .3);
    request.ranges = {{0, 1100000}, {1100000, 4000000}}; request.audio_join_fade_us = 20000;
    request.output = prefix + L"-ess-continuous-" + std::to_wstring(channels) + L".mp4";
    stage = "verify de-essing is identical across contiguous ranges"; RenderLocalVideo(request, cancel, [](double) {}); Require(Audio(request.output, channels) == soft);
    request.ranges = {{1250000, 1750000}, {250000, 750000}};
    request.output = prefix + L"-ess-cut-" + std::to_wstring(channels) + L".mp4";
    stage = "verify source cuts reset the detector"; RenderLocalVideo(request, cancel, [](double) {}); const auto cut = Audio(request.output, channels);
    Require(WindowRms(cut, 36000 * channels, 6000 * channels) > 7500 / (channels == 1 ? 1 : 1.3));
    VerifyLocalCut(request, 30, 1000000);
    request.ranges = {{0, 4000000}}; request.sound_balance = {true}; request.output = prefix + L"-ess-balanced-" + std::to_wstring(channels) + L".mp4";
    stage = "verify volume balance measures the softened sound"; RenderLocalVideo(request, cancel, [](double) {}); const auto balanced = Audio(request.output, channels);
    Require(std::abs(MeasureSound(balanced, channels) + 14) < .3);
    request.ranges = {{1250000, 1450000}}; request.sound_balance.enabled = false;
    request.output = prefix + L"-ess-short-" + std::to_wstring(channels) + L".mp4"; RenderLocalVideo(request, cancel, [](double) {}); const auto short_soft = Audio(request.output, channels);
    request.de_ess.enabled = false; request.output = prefix + L"-ess-short-raw-" + std::to_wstring(channels) + L".mp4"; RenderLocalVideo(request, cancel, [](double) {});
    Require(Audio(request.output, channels) == short_soft);
  }
}
int wmain(int count, wchar_t** args) {
  if (count != 2 && (count != 3 || (std::wstring(args[2]) != L"--camera-only" && std::wstring(args[2]) != L"--cleanup-only" && std::wstring(args[2]) != L"--placement-only" && std::wstring(args[2]) != L"--blur-only" && std::wstring(args[2]) != L"--sound-only" && std::wstring(args[2]) != L"--ess-only"))) return 2;
  const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED); if (FAILED(com)) return 3;
  const char* stage = "initialize";
  try {
    stage = "pure packet-independent sound join envelope"; CheckAudioJoinEnvelope();
    stage = "calibrated packet-independent loudness, gating and oversampled peak"; CheckSoundMeter();
    stage = "linked de-essing detection, cap, floor and packet independence"; CheckDeEsser();
    stage = "screen zoom springs, resize fit and cut reset"; CheckScreenZoomCrop();
    check_hresult(MFStartup(MF_VERSION));
    {
      com_ptr<ID3D11Device> device;
      check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
        nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, nullptr));
      const std::wstring prefix(args[1]), source = prefix + L"-source.mp4";
      std::atomic<bool> cancel{false};
      stage = "failed encoder cleanup without blocking finalization"; CheckWriterUnwind(device.get(), prefix);
      if (count == 2) {
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
        auto framed = zoomed; framed.screen_frame = FrameFixture();
        framed.output = prefix + (vertical ? L"-frame-portrait.mp4" : L"-frame-wide.mp4");
        framed.click_pulses = {{700000, 1120000, .8, .5, kWidth, kHeight}};
        framed.click_layout = {10, 4.4, 3, .12, 1, 260, 32, 0xfff2b84b};
        stage = "render generated inset backdrop and shadow"; RenderLocalVideo(framed, cancel, [](double) {});
        stage = "verify rounded corners, whole picture and inset zoom"; VerifyFramePixels(framed);
        stage = "verify click stays mapped inside screen frame"; VerifyClickPixels(framed, true);
        if (!vertical) {
          framed.camera = zoom_source; framed.camera_inset = .28; framed.camera_margin = .04;
          framed.output = prefix + L"-frame-camera.mp4";
          stage = "render framed screen with fixed camera"; RenderLocalVideo(framed, cancel, [](double) {});
          const auto pixels = FramePixels(framed.output, framed.width, framed.height, 30);
          const auto cw = static_cast<LONG>(framed.width * .28), ch = static_cast<LONG>(framed.height * .28), margin = static_cast<LONG>(framed.height * .04);
          const auto center = ((framed.height - margin - ch / 2) * framed.width + framed.width - margin - cw / 2) * 4;
          Require(pixels[center + 1] > pixels[center + 2] + 80); // Unzoomed camera remains green at its original corner.
        }
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
      if (count == 2 || std::wstring(args[2]) == L"--camera-only") CheckCameraPunch(device.get(), prefix, stage);
      if (count == 2 || std::wstring(args[2]) == L"--placement-only") CheckCameraPlacement(device.get(), prefix, stage);
      if (count == 2 || std::wstring(args[2]) == L"--blur-only") CheckScreenMotionBlur(device.get(), prefix, stage);
      if (count == 2 || std::wstring(args[2]) == L"--sound-only") CheckSoundBalance(device.get(), prefix, stage);
      if (count == 2 || std::wstring(args[2]) == L"--ess-only") CheckDeEssExports(device.get(), prefix, stage);
    }
    if (count == 3) std::cout << "Focused local render check passed: " <<
      (std::wstring(args[2]) == L"--cleanup-only" ? "injected zero/one-sample failure cleanup" :
       std::wstring(args[2]) == L"--placement-only" ? "camera placement geometry/pixels, frame mapping and source resets" :
       std::wstring(args[2]) == L"--blur-only" ? "screen blur direction/cap, sharp camera/still frames and source resets" :
       std::wstring(args[2]) == L"--sound-only" ? "loudness/gating/peak calibration, mono/stereo clocks, resampling, retained joins and cancellation" :
       std::wstring(args[2]) == L"--ess-only" ? "linked de-essing caps/floor/stereo, continuous/source-cut clocks, decoded attenuation and balanced volume" :
       "camera crops/cut resets and failure cleanup") << ".\n";
    else std::cout << "Local render check passed: streaming PCM/GPU pair, source selection/reordering, reviewed filler and retake tone/picture removal, silent input, stereo resampling, EN/FR/AR Readable/Karaoke/Cue/Punch timing and safe pixels, word reveal, emphasis, spring motion and Still, RTL underline, gaps, vertical Arabic, no clipped words, camera inset/end, exact portrait duration, cancel cleanup, damaged input, overwrite protection, centred main/paired camera crops/cut resets, camera placement, screen motion blur, volume balance/gates/peaks/mono/stereo/joins and injected zero/one-sample failure cleanup.\n";
    MFShutdown(); CoUninitialize(); return 0;
  } catch (...) {
    std::cerr << "Local render check failed at " << stage << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    MFShutdown(); CoUninitialize(); return 1;
  }
}

#include "local_render.h"
#include "gpu_video_writer.h"
#include "local_media_path.h"
#include "audio_join_fade.h"
#include <d3d11_4.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <propvarutil.h>
#include <winrt/base.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <stdexcept>

namespace {
using winrt::com_ptr;
using winrt::check_hresult;
constexpr int64_t kSecond = 10000000, kRate = 48000;
constexpr DWORD kAll = static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS);
constexpr DWORD kVideo = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
constexpr DWORD kAudio = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
void Require(bool value) { if (!value) throw std::runtime_error("Invalid local render"); }
void Cancel(std::atomic<bool>& value) { if (value) throw std::runtime_error("Render cancelled"); }
int64_t SampleAtUs(int64_t value) { return (value * kRate + 500000) / 1000000; }
void Seek(IMFSourceReader* reader, int64_t ticks) {
  PROPVARIANT position{}; check_hresult(InitPropVariantFromInt64(ticks, &position));
  const auto hr = reader->SetCurrentPosition(GUID_NULL, position);
  PropVariantClear(&position); check_hresult(hr);
}
struct Frame {
  com_ptr<IMFSample> sample;
  com_ptr<ID3D11Texture2D> image;
  UINT slice = 0;
  int64_t time = 0, duration = 0;
};
class VideoReader {
 public:
  void Open(const std::wstring& path, IMFDXGIDeviceManager* manager) {
    com_ptr<IMFAttributes> attributes; check_hresult(MFCreateAttributes(attributes.put(), 3));
    check_hresult(attributes->SetUnknown(MF_SOURCE_READER_D3D_MANAGER, manager));
    check_hresult(attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE));
    check_hresult(MFCreateSourceReaderFromURL(path.c_str(), attributes.get(), reader_.put()));
    check_hresult(reader_->SetStreamSelection(kAll, FALSE));
    check_hresult(reader_->SetStreamSelection(kVideo, TRUE));
    com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
    check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
    check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12));
    check_hresult(reader_->SetCurrentMediaType(kVideo, nullptr, type.get()));
    type = nullptr;
    check_hresult(reader_->GetCurrentMediaType(kVideo, type.put()));
    check_hresult(MFGetAttributeSize(type.get(), MF_MT_FRAME_SIZE, &width, &height));
    Require(width > 0 && height > 0 && width <= 16384 && height <= 16384);
    MFVideoArea aperture{}; UINT32 size = 0;
    HRESULT area = type->GetBlob(MF_MT_MINIMUM_DISPLAY_APERTURE, reinterpret_cast<UINT8*>(&aperture), sizeof(aperture), &size);
    if (FAILED(area)) area = type->GetBlob(MF_MT_GEOMETRIC_APERTURE, reinterpret_cast<UINT8*>(&aperture), sizeof(aperture), &size);
    if (SUCCEEDED(area) && size == sizeof(aperture)) {
      Require(aperture.OffsetX.value >= 0 && aperture.OffsetY.value >= 0 &&
        aperture.OffsetX.fract == 0 && aperture.OffsetY.fract == 0 &&
        aperture.Area.cx > 0 && aperture.Area.cy > 0 &&
        static_cast<UINT>(aperture.OffsetX.value + aperture.Area.cx) <= width &&
        static_cast<UINT>(aperture.OffsetY.value + aperture.Area.cy) <= height);
      x = aperture.OffsetX.value; y = aperture.OffsetY.value;
      width = static_cast<UINT>(aperture.Area.cx); height = static_cast<UINT>(aperture.Area.cy);
    }
  }
  void Reset(int64_t ticks) { Seek(reader_.get(), ticks); current_ = {}; next_ = {}; eos_ = false; }
  Frame At(int64_t wanted, bool main, std::atomic<bool>& cancel) {
    if (!current_.sample && !eos_) current_ = Read(cancel);
    if (!next_.sample && !eos_) next_ = Read(cancel);
    while (next_.sample && next_.time <= wanted + 10) {
      current_ = std::move(next_); next_ = Read(cancel);
    }
    if (!current_.sample || current_.time > wanted + 10) return {};
    if (eos_ && wanted >= current_.time + current_.duration) {
      if (!main) return {};
      Require(wanted < current_.time + current_.duration + kSecond / 4);
    }
    return current_;
  }
  UINT width = 0, height = 0;
  LONG x = 0, y = 0;
 private:
  Frame Read(std::atomic<bool>& cancel) {
    while (!eos_) {
      Cancel(cancel); Frame frame; DWORD flags = 0;
      check_hresult(reader_->ReadSample(kVideo, 0, nullptr, &flags, &frame.time, frame.sample.put()));
      if (flags & MF_SOURCE_READERF_ERROR) throw std::runtime_error("Video decode failed");
      if (flags & MF_SOURCE_READERF_ENDOFSTREAM) eos_ = true;
      if (!frame.sample) continue;
      check_hresult(frame.sample->GetSampleDuration(&frame.duration));
      Require(frame.duration > 0);
      com_ptr<IMFMediaBuffer> buffer; check_hresult(frame.sample->GetBufferByIndex(0, buffer.put()));
      const auto surface = buffer.as<IMFDXGIBuffer>();
      check_hresult(surface->GetResource(__uuidof(ID3D11Texture2D), frame.image.put_void()));
      check_hresult(surface->GetSubresourceIndex(&frame.slice));
      return frame;
    }
    return {};
  }
  com_ptr<IMFSourceReader> reader_;
  Frame current_, next_;
  bool eos_ = false;
};

class AudioReader {
 public:
  bool Open(const std::wstring& path) {
    check_hresult(MFCreateSourceReaderFromURL(path.c_str(), nullptr, reader_.put()));
    com_ptr<IMFMediaType> native;
    const auto hr = reader_->GetNativeMediaType(kAudio, 0, native.put());
    if (hr == MF_E_INVALIDSTREAMNUMBER) { reader_ = nullptr; return false; }
    check_hresult(hr);
    check_hresult(native->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels));
    Require(channels == 1 || channels == 2);
    check_hresult(reader_->SetStreamSelection(kAll, FALSE));
    check_hresult(reader_->SetStreamSelection(kAudio, TRUE));
    com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
    check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
    check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM));
    check_hresult(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16));
    check_hresult(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels));
    check_hresult(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, static_cast<UINT>(kRate)));
    check_hresult(reader_->SetCurrentMediaType(kAudio, nullptr, type.get()));
    return true;
  }
  void Reset(int64_t ticks) { Seek(reader_.get(), ticks); pcm_.clear(); eos_ = false; last_end_ = -1; }
  std::vector<int16_t> At(int64_t wanted, UINT count, std::atomic<bool>& cancel) {
    Require(count <= kRate && wanted >= 0);
    std::vector<int16_t> output(static_cast<size_t>(count) * channels, 0);
    UINT copied = 0;
    while (copied < count) {
      Cancel(cancel);
      const auto position = wanted + copied;
      while (pcm_.empty() || first_ + static_cast<int64_t>(pcm_.size() / channels) <= position) {
        if (eos_) {
          Require(last_end_ >= 0 && wanted + count - last_end_ <= kRate / 4);
          return output; // Preserve the short uncovered tail on the source clock.
        }
        Read(cancel);
      }
      if (first_ > position) {
        Require(first_ - position <= kRate / 4);
        copied += static_cast<UINT>(std::min<int64_t>(count - copied, first_ - position));
        continue;
      }
      const auto available = first_ + static_cast<int64_t>(pcm_.size() / channels) - position;
      const auto amount = static_cast<UINT>(std::min<int64_t>(count - copied, available));
      std::copy_n(pcm_.data() + (position - first_) * channels,
        static_cast<size_t>(amount) * channels, output.data() + static_cast<size_t>(copied) * channels);
      copied += amount;
    }
    return output;
  }
  UINT channels = 0;
 private:
  void Read(std::atomic<bool>& cancel) {
    pcm_.clear();
    while (!eos_ && pcm_.empty()) {
      Cancel(cancel); DWORD flags = 0; int64_t time = 0; com_ptr<IMFSample> sample;
      check_hresult(reader_->ReadSample(kAudio, 0, nullptr, &flags, &time, sample.put()));
      if (flags & (MF_SOURCE_READERF_ERROR | MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED)) throw std::runtime_error("Audio decode failed");
      if (flags & MF_SOURCE_READERF_ENDOFSTREAM) eos_ = true;
      if (!sample) continue;
      com_ptr<IMFMediaBuffer> buffer; check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
      DWORD length = 0; check_hresult(buffer->GetCurrentLength(&length));
      Require(length > 0 && length % (channels * sizeof(int16_t)) == 0 && length <= kRate * channels * sizeof(int16_t));
      pcm_.resize(length / sizeof(int16_t));
      BYTE* bytes = nullptr; check_hresult(buffer->Lock(&bytes, nullptr, nullptr));
      std::memcpy(pcm_.data(), bytes, length); check_hresult(buffer->Unlock());
      first_ = static_cast<int64_t>(std::llround(static_cast<double>(time) * kRate / kSecond));
      Require(first_ >= -kRate / 4 && (last_end_ < 0 || first_ >= last_end_ - 2));
      last_end_ = first_ + static_cast<int64_t>(pcm_.size() / channels);
    }
  }
  com_ptr<IMFSourceReader> reader_;
  std::vector<int16_t> pcm_;
  int64_t first_ = 0, last_end_ = -1;
  bool eos_ = false;
};

RECT Fit(UINT w, UINT h, const RECT& box) {
  const double scale = std::min(double(box.right - box.left) / w, double(box.bottom - box.top) / h);
  const auto width = static_cast<LONG>(w * scale), height = static_cast<LONG>(h * scale);
  const auto x = box.left + (box.right - box.left - width) / 2;
  const auto y = box.top + (box.bottom - box.top - height) / 2;
  return {x, y, x + width, y + height};
}
class Compositor {
 public:
  void Open(ID3D11Device* device, UINT width, UINT height, bool paired, double inset, double margin) {
    device_.copy_from(device); device->GetImmediateContext(context_.put());
    video_ = device_.as<ID3D11VideoDevice>(); control_ = context_.as<ID3D11VideoContext1>();
    D3D11_VIDEO_PROCESSOR_CONTENT_DESC desc{};
    desc.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    desc.InputWidth = desc.OutputWidth = width; desc.InputHeight = desc.OutputHeight = height;
    desc.InputFrameRate = desc.OutputFrameRate = {30, 1}; desc.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
    check_hresult(video_->CreateVideoProcessorEnumerator(&desc, enumerator_.put()));
    D3D11_VIDEO_PROCESSOR_CAPS caps{}; check_hresult(enumerator_->GetVideoProcessorCaps(&caps));
    Require(caps.MaxInputStreams >= (paired ? 2U : 1U));
    check_hresult(video_->CreateVideoProcessor(enumerator_.get(), 0, processor_.put()));
    control_->VideoProcessorSetOutputColorSpace1(processor_.get(), DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709);
    const D3D11_VIDEO_COLOR black{}; control_->VideoProcessorSetOutputBackgroundColor(processor_.get(), FALSE, &black);
    D3D11_TEXTURE2D_DESC image{};
    image.Width = width; image.Height = height; image.MipLevels = 1; image.ArraySize = 1;
    image.Format = DXGI_FORMAT_B8G8R8A8_UNORM; image.SampleDesc.Count = 1;
    image.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    check_hresult(device_->CreateTexture2D(&image, nullptr, output_.put()));
    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC view{}; view.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
    check_hresult(video_->CreateVideoProcessorOutputView(output_.get(), enumerator_.get(), &view, target_.put()));
    check_hresult(device_->CreateRenderTargetView(output_.get(), nullptr, clear_.put()));
    width_ = width; height_ = height;
    inset_ = inset; margin_ = margin;
  }
  com_ptr<ID3D11Texture2D> Compose(const Frame& main, const Frame& camera,
      const RECT& main_box, const RECT& camera_box, UINT index, const RECT& main_crop, const RECT& picture_bounds, const RECT& camera_crop) {
    const UINT mw = main_box.right - main_box.left, mh = main_box.bottom - main_box.top;
    const UINT cw = camera_box.right - camera_box.left, ch = camera_box.bottom - camera_box.top;
    const FLOAT black[4] = {0, 0, 0, 1}; context_->ClearRenderTargetView(clear_.get(), black);
    const Frame frames[] = {main, camera};
    com_ptr<ID3D11VideoProcessorInputView> inputs[2];
    D3D11_VIDEO_PROCESSOR_STREAM streams[2]{};
    const RECT full{0, 0, static_cast<LONG>(width_), static_cast<LONG>(height_)};
    // Keep the frame placement fixed while the selected source viewport moves.
    const LONG margin = static_cast<LONG>(std::min(width_, height_) * margin_);
    const LONG inset_w = static_cast<LONG>(width_ * inset_);
    const LONG inset_h = std::min(static_cast<LONG>(height_ * inset_), inset_w);
    const RECT inset{full.right - margin - inset_w, full.bottom - margin - inset_h, full.right - margin, full.bottom - margin};
    const RECT sources[] = {main_crop, camera_crop};
    const RECT destinations[] = {Fit(mw, mh, picture_bounds), camera.image ? Fit(cw, ch, inset) : inset};
    UINT count = 1;
    for (UINT stream = 0; stream < 2; ++stream) {
      if (!frames[stream].image) continue;
      D3D11_TEXTURE2D_DESC desc{}; frames[stream].image->GetDesc(&desc);
      D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC view{}; view.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
      view.Texture2D.MipSlice = frames[stream].slice % desc.MipLevels;
      view.Texture2D.ArraySlice = frames[stream].slice / desc.MipLevels;
      check_hresult(video_->CreateVideoProcessorInputView(frames[stream].image.get(), enumerator_.get(), &view, inputs[stream].put()));
      control_->VideoProcessorSetStreamFrameFormat(processor_.get(), stream, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
      control_->VideoProcessorSetStreamColorSpace1(processor_.get(), stream, DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709);
      control_->VideoProcessorSetStreamAutoProcessingMode(processor_.get(), stream, FALSE);
      control_->VideoProcessorSetStreamSourceRect(processor_.get(), stream, TRUE, &sources[stream]);
      control_->VideoProcessorSetStreamDestRect(processor_.get(), stream, TRUE, &destinations[stream]);
      streams[stream].Enable = TRUE; streams[stream].pInputSurface = inputs[stream].get(); count = stream + 1;
    }
    if (main.image || camera.image) check_hresult(control_->VideoProcessorBlt(processor_.get(), target_.get(), index, count, streams));
    context_->Flush(); return output_;
  }
 private:
  com_ptr<ID3D11Device> device_; com_ptr<ID3D11DeviceContext> context_;
  com_ptr<ID3D11VideoDevice> video_; com_ptr<ID3D11VideoContext1> control_;
  com_ptr<ID3D11VideoProcessorEnumerator> enumerator_; com_ptr<ID3D11VideoProcessor> processor_;
  com_ptr<ID3D11Texture2D> output_; com_ptr<ID3D11VideoProcessorOutputView> target_;
  com_ptr<ID3D11RenderTargetView> clear_;
  UINT width_ = 0, height_ = 0;
  double inset_ = 0, margin_ = 0;
};
}

void RenderLocalVideo(const LocalRenderRequest& request, std::atomic<bool>& cancel,
    const std::function<void(double)>& progress) {
  Cancel(cancel); CheckLocalMediaPath(request.source); CheckLocalMediaPath(request.output, true);
  if (!request.camera.empty()) CheckLocalMediaPath(request.camera);
  Require(std::isfinite(request.camera_inset) && std::isfinite(request.camera_margin) &&
    (request.camera.empty() || (request.camera_inset >= .05 && request.camera_inset <= .5 &&
      request.camera_margin >= 0 && request.camera_margin <= .2)));
  Require(request.source_duration_us > 0 && request.source_duration_us <= 24LL * 60 * 60 * 1000000 &&
    !request.ranges.empty() && request.ranges.size() <= 20001 && request.width >= 2 && request.height >= 2 &&
    request.width <= 4096 && request.height <= 4096 && request.width % 2 == 0 && request.height % 2 == 0);
  Require(request.audio_join_fade_us >= 0 && request.audio_join_fade_us <= 100000);
  int64_t total_us = 0;
  std::vector<int64_t> starts;
  for (const auto& range : request.ranges) {
    Require(range.start_us >= 0 && range.end_us > range.start_us && range.end_us <= request.source_duration_us);
    starts.push_back(total_us); total_us += range.end_us - range.start_us;
    Require(total_us <= 24LL * 60 * 60 * 1000000);
  }
  bool owned = false;
  try {
    com_ptr<ID3D11Device> device; com_ptr<ID3D11DeviceContext> context;
    check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
      nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
    context.as<ID3D11Multithread>()->SetMultithreadProtected(TRUE);
    UINT token = 0; com_ptr<IMFDXGIDeviceManager> manager;
    check_hresult(MFCreateDXGIDeviceManager(&token, manager.put())); check_hresult(manager->ResetDevice(device.get(), token));
    VideoReader main, camera; main.Open(request.source, manager.get());
    ScreenZoom zoom;
    zoom.Open(request.zoom_steps, request.zoom_spring, main.width, main.height, total_us);
    if (!request.camera.empty()) camera.Open(request.camera, manager.get());
    ScreenZoom punch;
    if (!request.punch_steps.empty()) {
      Require(request.punch_steps.size() <= 20000 && request.punch_steps.size() % 2 == 0 &&
        total_us >= 20000000 && request.source_duration_us >= 20000000 &&
        std::isfinite(request.punch_factor) && request.punch_factor >= 1.01 && request.punch_factor <= 1.2 &&
        (request.punch_main ? request.camera.empty() && request.zoom_steps.empty() && !request.screen_frame.enabled : !request.camera.empty()));
      const auto width = request.punch_main ? main.width : camera.width, height = request.punch_main ? main.height : camera.height;
      std::vector<ScreenZoomStep> steps;
      int64_t previous = 0, entered = -1;
      for (size_t i = 0; i < request.punch_steps.size(); ++i) {
        const auto& step = request.punch_steps[i];
        Require(step.time_us >= previous && step.time_us <= total_us && step.zoomed == (i % 2 == 0));
        if (step.zoomed) { Require(entered < 0 || step.time_us - entered >= 8000000); entered = step.time_us; }
        else Require(step.time_us > previous);
        steps.push_back({step.time_us, .5, .5, step.zoomed ? request.punch_factor : 1, width, height});
        previous = step.time_us;
      }
      punch.Open(steps, request.punch_spring, width, height, total_us);
    }
    AudioReader audio; const bool has_audio = audio.Open(request.source);
    Compositor compositor; compositor.Open(device.get(), request.width, request.height, !request.camera.empty(),
      request.camera_inset, request.camera_margin);
    CaptionOverlay captions;
    CaptionOverlay shortcuts;
    const auto picture_bounds = ScreenFrameBounds(request.width, request.height, request.screen_frame);
    const auto picture = Fit(main.width, main.height, picture_bounds);
    ScreenFrame screen_frame;
    screen_frame.Open(device.get(), request.width, request.height, picture, request.screen_frame);
    ClickOverlay clicks;
    clicks.Open(device.get(), request.width, request.height, total_us, request.click_pulses, request.click_layout);
    captions.Open(device.get(), request.width, request.height, total_us, request.captions, request.caption_layout);
    shortcuts.Open(device.get(), request.width, request.height, total_us, request.shortcut_badges, request.shortcut_layout);
    GpuVideoWriter writer;
    check_hresult(writer.Start(device.get(), request.output, request.width, request.height, 30,
      has_audio ? GpuAudioFormat{static_cast<UINT>(kRate), audio.channels} : GpuAudioFormat{}, &owned, false));
    size_t video_range = 0, audio_range = 0;
    size_t previous_video_range = request.ranges.size(), previous_audio_range = request.ranges.size();
    int64_t audio_position = 0;
    const auto total_samples = SampleAtUs(total_us);
    const auto total_ticks = total_us * 10;
    for (UINT frame = 0; static_cast<int64_t>(frame) * kSecond / 30 < total_ticks; ++frame) {
      Cancel(cancel);
      const auto output_ticks = static_cast<int64_t>(frame) * kSecond / 30;
      const auto end_ticks = std::min(total_ticks, static_cast<int64_t>(frame + 1) * kSecond / 30);
      while (video_range + 1 < request.ranges.size() && starts[video_range + 1] * 10 <= output_ticks) ++video_range;
      const auto source_ticks = request.ranges[video_range].start_us * 10 + output_ticks - starts[video_range] * 10;
      if (video_range != previous_video_range) {
        main.Reset(source_ticks); if (!request.camera.empty()) camera.Reset(source_ticks); previous_video_range = video_range;
        if (video_range == 0 || request.ranges[video_range - 1].end_us != request.ranges[video_range].start_us)
          { zoom.Reset(starts[video_range]); punch.Reset(starts[video_range]); }
      }
      const RECT main_box{main.x, main.y, main.x + static_cast<LONG>(main.width), main.y + static_cast<LONG>(main.height)};
      const auto main_crop = request.punch_main ? punch.Crop(main_box, output_ticks / 10) : zoom.Crop(main_box, output_ticks / 10);
      const RECT full{0, 0, static_cast<LONG>(request.width), static_cast<LONG>(request.height)};
      const LONG margin = static_cast<LONG>(std::min(request.width, request.height) * request.camera_margin);
      const LONG inset_w = static_cast<LONG>(request.width * request.camera_inset);
      const LONG inset_h = std::min(static_cast<LONG>(request.height * request.camera_inset), inset_w);
      const RECT inset{full.right - margin - inset_w, full.bottom - margin - inset_h, full.right - margin, full.bottom - margin};
      const auto camera_frame = request.camera.empty() ? Frame{} : camera.At(source_ticks, false, cancel);
      const RECT camera_box{camera.x, camera.y, camera.x + static_cast<LONG>(camera.width), camera.y + static_cast<LONG>(camera.height)};
      const auto camera_crop = request.punch_main ? camera_box : punch.Crop(camera_box, output_ticks / 10);
      const auto image = compositor.Compose(main.At(source_ticks, true, cancel),
        camera_frame, main_box, camera_box, frame, main_crop, picture_bounds, camera_crop);
      const auto camera_destination = camera_frame.image ? Fit(camera.width, camera.height, inset) : RECT{};
      clicks.Draw(image.get(), output_ticks / 10, main_box, main_crop,
        picture, camera_destination);
      screen_frame.Draw(image.get(), camera_destination);
      captions.Draw(image.get(), output_ticks / 10);
      shortcuts.Draw(image.get(), output_ticks / 10);
      check_hresult(writer.WriteFrame(image.get(), request.width, request.height, output_ticks, end_ticks - output_ticks));
      if (has_audio) {
        const auto end_sample = std::min(total_samples, (end_ticks * kRate + kSecond / 2) / kSecond);
        while (audio_position < end_sample) {
          Cancel(cancel);
          while (audio_range + 1 < request.ranges.size() && SampleAtUs(starts[audio_range + 1]) <= audio_position) ++audio_range;
          const auto range_end = audio_range + 1 < starts.size() ? SampleAtUs(starts[audio_range + 1]) : total_samples;
          const auto count = static_cast<UINT>(std::min(end_sample, range_end) - audio_position);
          Require(count > 0);
          const auto source_sample = SampleAtUs(request.ranges[audio_range].start_us) + audio_position - SampleAtUs(starts[audio_range]);
          if (audio_range != previous_audio_range) { audio.Reset(request.ranges[audio_range].start_us * 10); previous_audio_range = audio_range; }
          auto pcm = audio.At(source_sample, count, cancel);
          ApplyAudioJoinFade(pcm, audio.channels, audio_position,
            SampleAtUs(starts[audio_range]), range_end, request.audio_join_fade_us * kRate / 2000000,
            audio_range > 0 && request.ranges[audio_range - 1].end_us != request.ranges[audio_range].start_us,
            audio_range + 1 < request.ranges.size() && request.ranges[audio_range].end_us != request.ranges[audio_range + 1].start_us);
          check_hresult(writer.WriteAudio(pcm.data(), count, audio_position * kSecond / kRate));
          audio_position += count;
        }
      }
      progress(static_cast<double>(end_ticks) / total_ticks);
    }
    Cancel(cancel); check_hresult(writer.Finish()); Cancel(cancel);
  } catch (...) {
    // MF writer/reader handles have been released during unwinding. This path
    // was exclusively created by this job, never an original or pre-existing file.
    if (owned) DeleteFileW(request.output.c_str());
    throw;
  }
}

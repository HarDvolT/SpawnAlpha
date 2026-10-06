#include "camera_capture.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <winrt/base.h>
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstring>
#include <mutex>

namespace {
constexpr DWORD kVideo = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
LONGLONG CameraQpc() {
  LARGE_INTEGER now{}, frequency{}; QueryPerformanceCounter(&now); QueryPerformanceFrequency(&frequency);
  return now.QuadPart / frequency.QuadPart * 10000000 + now.QuadPart % frequency.QuadPart * 10000000 / frequency.QuadPart;
}
}
struct CameraCapture::Impl : std::enable_shared_from_this<Impl> {
  struct Callback : IMFSourceReaderCallback {
    explicit Callback(std::weak_ptr<Impl> state) : state(std::move(state)) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** object) override {
      if (!object) return E_POINTER; *object = nullptr;
      if (id == __uuidof(IUnknown) || id == __uuidof(IMFSourceReaderCallback)) {
        *object = static_cast<IMFSourceReaderCallback*>(this); AddRef(); return S_OK;
      }
      return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
    ULONG STDMETHODCALLTYPE Release() override { const auto count = --references; if (!count) delete this; return count; }
    HRESULT STDMETHODCALLTYPE OnReadSample(HRESULT hr, DWORD, DWORD flags, LONGLONG, IMFSample* sample) override {
      if (const auto owner = state.lock()) owner->Read(hr, flags, sample);
      return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnEvent(DWORD, IMFMediaEvent* event) override {
      if (const auto owner = state.lock()) {
        MediaEventType type{};
        if (event && SUCCEEDED(event->GetType(&type)) && type == MEError) owner->MarkFailed();
      }
      return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnFlush(DWORD) override { return S_OK; }
    std::atomic<ULONG> references{1};
    std::weak_ptr<Impl> state;
  };
  void MarkFailed(HRESULT error = E_FAIL) { std::lock_guard<std::mutex> lock(mutex); if (!stopping) { failed = true; last_error = error; } }
  HRESULT Open(const std::wstring& input, bool fixture) {
    Stop();
    if (input.empty()) return E_INVALIDARG;
    try {
      winrt::check_hresult(MFStartup(MF_VERSION)); initialized = true;
      { std::lock_guard<std::mutex> lock(mutex); stopping = false; failed = false; last_error = S_OK; latest.reset(); }
      is_fixture = fixture;
      winrt::com_ptr<IMFAttributes> options;
      winrt::check_hresult(MFCreateAttributes(options.put(), 3));
      winrt::check_hresult(options->SetUINT32(MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE));
      winrt::com_ptr<IMFSourceReaderCallback> callback;
      callback.attach(new Callback(weak_from_this()));
      winrt::check_hresult(options->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, callback.get()));
      if (fixture) {
        // Caller exists only in native checks. Production Open always pins a
        // chosen opaque device link; it cannot interpret a URL or a file path.
        winrt::check_hresult(MFCreateSourceReaderFromURL(input.c_str(), options.get(), reader.put()));
      } else {
        winrt::com_ptr<IMFAttributes> device;
        winrt::check_hresult(MFCreateAttributes(device.put(), 2));
        winrt::check_hresult(device->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID));
        winrt::check_hresult(device->SetString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, input.c_str()));
        winrt::check_hresult(MFCreateDeviceSource(device.get(), source.put()));
        winrt::check_hresult(MFCreateSourceReaderFromMediaSource(source.get(), options.get(), reader.put()));
      }
      winrt::check_hresult(reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE));
      winrt::check_hresult(reader->SetStreamSelection(kVideo, TRUE));
      // Choose a bounded native camera format before RGB conversion. Never
      // upsample a low-resolution source just to hit a preset.
      if (!fixture) {
        winrt::com_ptr<IMFMediaType> best; UINT64 score = 0;
        for (DWORD index = 0; index < 256; ++index) {
          winrt::com_ptr<IMFMediaType> type;
          if (FAILED(reader->GetNativeMediaType(kVideo, index, type.put()))) break;
          UINT w = 0, h = 0, numerator = 0, denominator = 0;
          if (FAILED(MFGetAttributeSize(type.get(), MF_MT_FRAME_SIZE, &w, &h)) || w < 2 || h < 2 || w > 1280 || h > 720) continue;
          if (FAILED(MFGetAttributeRatio(type.get(), MF_MT_FRAME_RATE, &numerator, &denominator)) || !denominator) continue;
          const double fps = static_cast<double>(numerator) / denominator;
          if (fps < 15 || fps > 30.1) continue;
          const UINT64 value = static_cast<UINT64>(w) * h * 100 + static_cast<UINT>(fps);
          if (value > score) { score = value; best = std::move(type); }
        }
        if (best) winrt::check_hresult(reader->SetCurrentMediaType(kVideo, nullptr, best.get()));
      }
      winrt::com_ptr<IMFMediaType> rgb;
      winrt::check_hresult(MFCreateMediaType(rgb.put()));
      winrt::check_hresult(rgb->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
      winrt::check_hresult(rgb->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
      winrt::check_hresult(reader->SetCurrentMediaType(kVideo, nullptr, rgb.get()));
      rgb = nullptr;
      winrt::check_hresult(reader->GetCurrentMediaType(kVideo, rgb.put()));
      winrt::check_hresult(MFGetAttributeSize(rgb.get(), MF_MT_FRAME_SIZE, &width, &height));
      if (width < 2 || height < 2 || width > 4096 || height > 4096) throw winrt::hresult_error(E_INVALIDARG);
      UINT32 stride_bits = 0;
      if (SUCCEEDED(rgb->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride_bits))) stride = static_cast<LONG>(stride_bits);
      else winrt::check_hresult(MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, width, &stride));
      winrt::check_hresult(reader->ReadSample(kVideo, 0, nullptr, nullptr, nullptr, nullptr));
      return S_OK;
    } catch (...) {
      const auto error = winrt::to_hresult(); Stop(); return error;
    }
  }
  void Read(HRESULT hr, DWORD flags, IMFSample* sample) noexcept {
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (stopping) return;
      ++callbacks;
    }
    try {
      winrt::check_hresult(hr);
      if (flags & (MF_SOURCE_READERF_ERROR | MF_SOURCE_READERF_ENDOFSTREAM)) throw winrt::hresult_error(E_FAIL);
      if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
        winrt::com_ptr<IMFMediaType> type;
        winrt::check_hresult(reader->GetCurrentMediaType(kVideo, type.put()));
        winrt::check_hresult(MFGetAttributeSize(type.get(), MF_MT_FRAME_SIZE, &width, &height));
        if (width < 2 || height < 2 || width > 4096 || height > 4096) throw winrt::hresult_error(E_INVALIDARG);
        UINT32 bits = 0;
        if (SUCCEEDED(type->GetUINT32(MF_MT_DEFAULT_STRIDE, &bits))) stride = static_cast<LONG>(bits);
        else winrt::check_hresult(MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, width, &stride));
      }
      if (sample) {
        auto frame = std::make_shared<CameraFrame>(); frame->width = width; frame->height = height;
        frame->bgra.resize(static_cast<size_t>(width) * height * 4);
        winrt::com_ptr<IMFMediaBuffer> buffer;
        winrt::check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
        winrt::com_ptr<IMF2DBuffer> surface;
        BYTE* pixels = nullptr; LONG pitch = stride; DWORD length = 0;
        bool locked_2d = SUCCEEDED(buffer->QueryInterface(__uuidof(IMF2DBuffer), surface.put_void()));
        if (locked_2d) winrt::check_hresult(surface->Lock2D(&pixels, &pitch));
        else {
          winrt::check_hresult(buffer->Lock(&pixels, nullptr, &length));
          if (static_cast<UINT64>(std::abs(pitch)) * height > length) {
            buffer->Unlock(); throw winrt::hresult_error(E_FAIL);
          }
          if (pitch < 0) pixels += static_cast<size_t>(height - 1) * static_cast<size_t>(-pitch);
        }
        if (static_cast<UINT>(std::abs(pitch)) < width * 4) {
          if (locked_2d) surface->Unlock2D(); else buffer->Unlock();
          throw winrt::hresult_error(E_FAIL);
        }
        for (UINT y = 0; y < height; ++y) {
          std::memcpy(frame->bgra.data() + static_cast<size_t>(y) * width * 4,
            pixels + static_cast<ptrdiff_t>(y) * pitch, static_cast<size_t>(width) * 4);
        }
        winrt::check_hresult(locked_2d ? surface->Unlock2D() : buffer->Unlock());
        frame->arrived_100ns = CameraQpc();
        std::lock_guard<std::mutex> lock(mutex); if (!stopping) latest = std::move(frame);
      }
#ifdef SPAWNALPHA_CAMERA_FIXTURE
      if (is_fixture) Sleep(33); // Generated file behaves like a 30 fps camera.
#endif
      winrt::com_ptr<IMFSourceReader> next;
      { std::lock_guard<std::mutex> lock(mutex); if (!stopping) next = reader; }
      if (next) winrt::check_hresult(next->ReadSample(kVideo, 0, nullptr, nullptr, nullptr, nullptr));
    } catch (...) { MarkFailed(winrt::to_hresult()); }
    { std::lock_guard<std::mutex> lock(mutex); --callbacks; }
    drained.notify_all();
  }
  void Stop() {
    { std::lock_guard<std::mutex> lock(mutex); stopping = true; }
    // No callback mutex is held across media-source shutdown/flush.
    if (reader) reader->Flush(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS));
    if (source) source->Shutdown();
    winrt::com_ptr<IMFSourceReader> old_reader;
    winrt::com_ptr<IMFMediaSource> old_source;
    {
      std::unique_lock<std::mutex> lock(mutex);
      drained.wait(lock, [this] { return callbacks == 0; });
      old_reader = std::move(reader); old_source = std::move(source); latest.reset();
    }
    old_reader = nullptr; old_source = nullptr;
    if (initialized) { MFShutdown(); initialized = false; }
  }
  mutable std::mutex mutex;
  std::condition_variable drained;
  int callbacks = 0;
  bool stopping = true, failed = false, initialized = false, is_fixture = false;
  UINT width = 0, height = 0;
  LONG stride = 0;
  HRESULT last_error = S_OK;
  std::shared_ptr<const CameraFrame> latest;
  winrt::com_ptr<IMFSourceReader> reader;
  winrt::com_ptr<IMFMediaSource> source;
};
CameraCapture::CameraCapture() : impl_(std::make_shared<Impl>()) {}
CameraCapture::~CameraCapture() { Stop(); }
HRESULT CameraCapture::Open(const std::wstring& link) { return impl_->Open(link, false); }
#ifdef SPAWNALPHA_CAMERA_FIXTURE
HRESULT CameraCapture::OpenFixture(const std::wstring& path) { return impl_->Open(path, true); }
HRESULT CameraCapture::FixtureError() const { std::lock_guard<std::mutex> lock(impl_->mutex); return impl_->last_error; }
#endif
std::shared_ptr<const CameraFrame> CameraCapture::Latest() const { std::lock_guard<std::mutex> lock(impl_->mutex); return impl_->latest; }
bool CameraCapture::Failed() const { std::lock_guard<std::mutex> lock(impl_->mutex); return impl_->failed; }
void CameraCapture::Stop() { impl_->Stop(); }

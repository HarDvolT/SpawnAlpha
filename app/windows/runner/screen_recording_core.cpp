#include "screen_recording_core.h"
#include "gpu_video_writer.h"
#include "microphone_capture.h"
#include "recording_clock.h"
#include <d3d11_4.h>
#include <dxgi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <mutex>
#include <thread>

namespace {
using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using winrt::Windows::Graphics::SizeInt32;
using ::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess;
constexpr UINT kFramesPerSecond = 30;
constexpr LONGLONG kSecond = 10000000;
constexpr UINT kAudioRate = 48000;

LONGLONG QpcTime() {
  LARGE_INTEGER now{}, frequency{};
  QueryPerformanceCounter(&now); QueryPerformanceFrequency(&frequency);
  // Split to avoid overflow after long Windows uptimes.
  return now.QuadPart / frequency.QuadPart * kSecond +
      now.QuadPart % frequency.QuadPart * kSecond / frequency.QuadPart;
}
double Db(double value) { return value > 0.00001 ? 20 * std::log10(value) : -100; }
struct CapturedFrame {
  com_ptr<ID3D11Texture2D> texture;
  UINT width = 0, height = 0;
};
}  // namespace

struct ScreenRecordingCore::Impl : std::enable_shared_from_this<Impl> {
  ~Impl() { StopAndJoin(); }
  HRESULT Start(HMONITOR monitor, HWND window, const std::wstring& path,
                const std::wstring& microphone_id, bool record_audio) {
    if (worker.joinable() || (!monitor && !window) || (monitor && window) || path.empty()) return E_INVALIDARG;
    try {
      worker = std::thread([this, monitor, window, path, microphone_id, record_audio] {
        Run(monitor, window, path, microphone_id, record_audio);
      });
      return S_OK;
    } catch (...) { return winrt::to_hresult(); }
  }
  void StopAndJoin() {
    stop = true;
    if (worker.joinable()) worker.join();
  }
  ScreenRecordingStatus Status() const {
    std::lock_guard<std::mutex> lock(status_mutex);
    return status;
  }
  void Fail(ScreenRecordingReason reason) {
    std::lock_guard<std::mutex> lock(status_mutex);
    status.reason = reason;
  }
  void SetState(ScreenRecordingState state) {
    std::lock_guard<std::mutex> lock(status_mutex);
    status.state = state;
  }
  void OnFrame(const Direct3D11CaptureFramePool& sender) noexcept {
    std::lock_guard<std::mutex> lock(frame_mutex);
    if (stop || source_closed || capture_failed) return;
    try {
      auto frame = sender.TryGetNextFrame();
      if (!frame) return;
      const auto content = frame.ContentSize();
      if (content.Width <= 0 || content.Height <= 0) { frame.Close(); return; }
      const auto access = frame.Surface().as<IDirect3DDxgiInterfaceAccess>();
      com_ptr<ID3D11Texture2D> texture;
      check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), texture.put_void()));
      D3D11_TEXTURE2D_DESC desc{}; texture->GetDesc(&desc);
      auto next = std::make_shared<CapturedFrame>();
      next->width = std::min(desc.Width, static_cast<UINT>(content.Width));
      next->height = std::min(desc.Height, static_cast<UINT>(content.Height));
      desc.Usage = D3D11_USAGE_DEFAULT; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
      desc.CPUAccessFlags = 0; desc.MiscFlags = 0;
      check_hresult(device->CreateTexture2D(&desc, nullptr, next->texture.put()));
      context->CopyResource(next->texture.get(), texture.get());
      // The capture pool can immediately reuse its surface after Close. Retain
      // our own GPU snapshot, never a reference to that reusable pool surface.
      latest = std::move(next);
      frame.Close();
      if (content.Width != size.Width || content.Height != size.Height) {
        sender.Recreate(rt_device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, content);
        size = content;
      }
    } catch (...) { capture_failed = true; }
  }
  void CloseCapture() {
    Direct3D11CaptureFramePool old_pool{nullptr};
    GraphicsCaptureSession old_capture{nullptr};
    GraphicsCaptureItem old_item{nullptr};
    {
      std::lock_guard<std::mutex> lock(frame_mutex);
      old_pool = std::exchange(pool, nullptr);
      old_capture = std::exchange(capture, nullptr);
      old_item = std::exchange(item, nullptr);
    }
    // Close may wait for the last event handler. Never hold its mutex here.
    try { if (old_pool) old_pool.FrameArrived(frame_token); } catch (...) {}
    try { if (old_item) old_item.Closed(closed_token); } catch (...) {}
    try { if (old_capture) old_capture.Close(); } catch (...) {}
    try { if (old_pool) old_pool.Close(); } catch (...) {}
    std::lock_guard<std::mutex> lock(frame_mutex);
    latest.reset();
  }
  void DrainAudio(MicrophoneCapture& microphone, GpuVideoWriter& writer,
                  const RecordingClock& clock, LONGLONG end, LONGLONG& written_audio_frames,
                  bool& got_audio) {
    while (true) {
      MicrophonePacket packet;
      const HRESULT read = microphone.Read(packet);
      if (read == S_FALSE) return;
      if (FAILED(read)) { Fail(ScreenRecordingReason::microphone); check_hresult(read); }
      // Losing the clock or samples is explicit, never a silently corrupt take.
      // WASAPI may mark only its very first packet discontinuous at startup.
      if (packet.timestamp_error || (got_audio && packet.discontinuity)) {
        Fail(ScreenRecordingReason::microphone); throw hresult_error(E_FAIL);
      }
      got_audio = true;
      double peak = 0, squares = 0;
      for (const auto sample : packet.pcm) {
        const double value = sample / 32768.0;
        peak = std::max(peak, std::abs(value)); squares += value * value;
      }
      {
        std::lock_guard<std::mutex> lock(status_mutex);
        status.peak_db = Db(peak);
        status.rms_db = Db(std::sqrt(squares / static_cast<double>(packet.pcm.size())));
      }
      for (const auto& slice : clock.Audio(static_cast<LONGLONG>(packet.qpc_100ns), packet.pcm.size(), kAudioRate)) {
        LONGLONG first = static_cast<LONGLONG>(std::llround(static_cast<double>(slice.time_100ns) * kAudioRate / kSecond));
        size_t trim = 0;
        if (first < written_audio_frames) {
          trim = static_cast<size_t>(written_audio_frames - first);
          first = written_audio_frames;
        }
        if (trim >= slice.count) continue;
        size_t count = slice.count - trim;
        if (end >= 0) {
          const LONGLONG limit = end * kAudioRate / kSecond;
          if (first >= limit) continue;
          count = std::min(count, static_cast<size_t>(limit - first));
        }
        if (!count) continue;
        const auto* pcm = packet.pcm.data() + slice.offset + trim;
        const HRESULT saved = writer.WriteAudio(pcm, static_cast<UINT>(count), first * kSecond / kAudioRate);
        if (FAILED(saved)) { Fail(ScreenRecordingReason::encoder); check_hresult(saved); }
        written_audio_frames = first + static_cast<LONGLONG>(count);
        std::lock_guard<std::mutex> lock(status_mutex);
        status.audio_frames += count;
        status.loudest_rms_db = std::max(status.loudest_rms_db, status.rms_db);
      }
    }
  }
  void Run(HMONITOR monitor, HWND window, const std::wstring& path,
           const std::wstring& microphone_id, bool record_audio) noexcept {
    bool initialized = false, writer_started = false;
    GpuVideoWriter writer;
    MicrophoneCapture microphone;
    ScreenRecordingReason stage = ScreenRecordingReason::source;
    try {
      init_apartment(apartment_type::multi_threaded); initialized = true;
      if (!GraphicsCaptureSession::IsSupported()) throw hresult_error(E_NOTIMPL);
      const auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
      if (window) check_hresult(interop->CreateForWindow(window, guid_of<GraphicsCaptureItem>(), put_abi(item)));
      else check_hresult(interop->CreateForMonitor(monitor, guid_of<GraphicsCaptureItem>(), put_abi(item)));
      size = item.Size();
      if (size.Width < 2 || size.Height < 2) throw hresult_error(E_INVALIDARG);
      check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
          nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
      context.as<ID3D11Multithread>()->SetMultithreadProtected(TRUE);
      com_ptr<IInspectable> inspectable;
      check_hresult(CreateDirect3D11DeviceFromDXGIDevice(device.as<IDXGIDevice>().get(), inspectable.put()));
      rt_device = inspectable.as<IDirect3DDevice>();
      const auto weak = weak_from_this();
      pool = Direct3D11CaptureFramePool::CreateFreeThreaded(rt_device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
      frame_token = pool.FrameArrived([weak](const auto& sender, const auto&) {
        if (const auto self = weak.lock()) self->OnFrame(sender);
      });
      closed_token = item.Closed([weak](const auto&, const auto&) {
        if (const auto self = weak.lock()) self->source_closed = true;
      });
      capture = pool.CreateCaptureSession(item);
      capture.StartCapture();  // Keep the Windows capture border enabled.
      const LONGLONG started_waiting = QpcTime();
      std::shared_ptr<CapturedFrame> first;
      while (!stop && !source_closed && !capture_failed && QpcTime() - started_waiting < 5 * kSecond) {
        { std::lock_guard<std::mutex> lock(frame_mutex); first = latest; }
        if (first) break;
        Sleep(5);
      }
      if (stop) { Fail(ScreenRecordingReason::cancelled); throw hresult_error(E_ABORT); }
      if (!first || source_closed || capture_failed || (window && IsIconic(window))) throw hresult_error(E_FAIL);
      const double scale = std::min(1.0, 1920.0 / std::max(first->width, first->height));
      const UINT width = std::max<UINT>(2, static_cast<UINT>(first->width * scale) / 2 * 2);
      const UINT height = std::max<UINT>(2, static_cast<UINT>(first->height * scale) / 2 * 2);
      if (record_audio) {
        stage = ScreenRecordingReason::microphone;
        check_hresult(microphone.Open(microphone_id));
      }
      stage = ScreenRecordingReason::encoder;
      check_hresult(writer.Start(device.get(), path, width, height, kFramesPerSecond,
          record_audio ? GpuAudioFormat{kAudioRate, 1} : GpuAudioFormat{}));
      writer_started = true;
      if (stop) { Fail(ScreenRecordingReason::cancelled); throw hresult_error(E_ABORT); }
      if (record_audio) {
        stage = ScreenRecordingReason::microphone;
        check_hresult(microphone.Start());
      }
      const LONGLONG origin = QpcTime();
      RecordingClock clock(origin);
      bool paused = false;
      { std::lock_guard<std::mutex> lock(status_mutex); status.width = width; status.height = height; }
      SetState(ScreenRecordingState::recording);
      UINT64 next_frame = 0;
      LONGLONG audio_frames = 0;
      bool got_audio = false;
      while (!stop) {
        if (source_closed || capture_failed || (window && (!IsWindow(window) || IsIconic(window)))) {
          Fail(ScreenRecordingReason::source); break;
        }
        const LONGLONG now = QpcTime();
        if (paused != wanted_paused.load()) {
          paused = wanted_paused.load();
          clock.Pause(paused, now);
          SetState(paused ? ScreenRecordingState::paused : ScreenRecordingState::recording);
        }
        const LONGLONG elapsed = clock.Time(now);
        if (record_audio) DrainAudio(microphone, writer, clock, -1, audio_frames, got_audio);
        if (!paused && elapsed >= static_cast<LONGLONG>(next_frame) * kSecond / kFramesPerSecond) {
          // If the encoder fell behind, drop to the latest cadence slot instead
          // of building an unbounded queue. Audio and video keep common times.
          next_frame = std::max(next_frame, static_cast<UINT64>(elapsed * kFramesPerSecond / kSecond));
          std::shared_ptr<CapturedFrame> frame;
          { std::lock_guard<std::mutex> lock(frame_mutex); frame = latest; }
          if (frame) {
            const LONGLONG time = static_cast<LONGLONG>(next_frame) * kSecond / kFramesPerSecond;
            stage = ScreenRecordingReason::encoder;
            check_hresult(writer.WriteFrame(frame->texture.get(), frame->width, frame->height, time));
            std::lock_guard<std::mutex> lock(status_mutex);
            ++status.frames; status.duration_100ns = time + kSecond / kFramesPerSecond;
          }
          ++next_frame;
        }
        Sleep(2);
      }
      SetState(ScreenRecordingState::saving);
      if (record_audio) DrainAudio(microphone, writer, clock, Status().duration_100ns, audio_frames, got_audio);
    } catch (...) {
      if (Status().reason == ScreenRecordingReason::none) Fail(stage);
    }
    stop = true;
    microphone.Stop();
    CloseCapture();
    if (writer_started) {
      SetState(ScreenRecordingState::saving);
      if (FAILED(writer.Finish())) Fail(ScreenRecordingReason::encoder);
    }
    // Release all WinRT/COM objects before uninitializing the worker apartment.
    writer.Finish();
    rt_device = nullptr; context = nullptr; device = nullptr;
    if (initialized) uninit_apartment();
    const auto result = Status();
    SetState(result.frames ? ScreenRecordingState::finished : ScreenRecordingState::failed);
  }
  std::thread worker;
  std::atomic<bool> stop{false}, source_closed{false}, capture_failed{false}, wanted_paused{false};
  mutable std::mutex status_mutex;
  ScreenRecordingStatus status{};
  std::mutex frame_mutex;
  std::shared_ptr<CapturedFrame> latest;
  com_ptr<ID3D11Device> device;
  com_ptr<ID3D11DeviceContext> context;
  IDirect3DDevice rt_device{nullptr};
  GraphicsCaptureItem item{nullptr};
  Direct3D11CaptureFramePool pool{nullptr};
  GraphicsCaptureSession capture{nullptr};
  SizeInt32 size{};
  event_token frame_token{}, closed_token{};
};

ScreenRecordingCore::ScreenRecordingCore() : impl_(std::make_shared<Impl>()) {}
ScreenRecordingCore::~ScreenRecordingCore() { impl_->StopAndJoin(); }
HRESULT ScreenRecordingCore::Start(HMONITOR monitor, HWND window, const std::wstring& path,
                                  const std::wstring& microphone_id, bool record_audio) {
  return impl_->Start(monitor, window, path, microphone_id, record_audio);
}
void ScreenRecordingCore::RequestStop() { impl_->stop = true; }
void ScreenRecordingCore::SetPaused(bool paused) { impl_->wanted_paused = paused; }
ScreenRecordingStatus ScreenRecordingCore::Status() const { return impl_->Status(); }

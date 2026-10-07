#include "screen_recording_core.h"
#include "gpu_video_writer.h"
#include "microphone_capture.h"
#include "recording_clock.h"
#include "recording_audio_mixer.h"
#include "camera_capture.h"
#include "recording_activity.h"
#include <d3d11_4.h>
#include <dxgi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <algorithm>
#ifdef SPAWNALPHA_RECORDING_FIXTURE
namespace { DWORD fixture_stall = 0; }
void ConfigureRecordingStall(DWORD milliseconds) { fixture_stall = milliseconds; }
#endif
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
                const std::wstring& microphone_id, bool record_audio,
                const std::wstring& camera_id, const std::wstring& camera_path, bool record_system_audio, const std::wstring& activity_path,
                const std::wstring& cursor_free_path) {
    if (worker.joinable() || (!monitor && !window) || (monitor && window) || path.empty() ||
        camera_id.empty() != camera_path.empty() || (!camera_path.empty() && camera_path == path) ||
        (!cursor_free_path.empty() && (cursor_free_path == path || cursor_free_path == camera_path || cursor_free_path == activity_path))) return E_INVALIDARG;
    try {
      worker = std::thread([this, monitor, window, path, microphone_id, record_audio, camera_id, camera_path, record_system_audio, activity_path, cursor_free_path] {
        Run(monitor, window, path, microphone_id, record_audio, camera_id, camera_path, record_system_audio, activity_path, cursor_free_path);
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
  void OnFrame(const Direct3D11CaptureFramePool& sender, bool cursor_free = false) noexcept {
    std::lock_guard<std::mutex> lock(frame_mutex);
    if (stop || source_closed || capture_failed || (cursor_free && cursor_free_failed)) return;
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
      if (cursor_free) cursor_free_latest = std::move(next);
      else latest = std::move(next);
      frame.Close();
      auto& current_size = cursor_free ? cursor_free_size : size;
      if (content.Width != current_size.Width || content.Height != current_size.Height) {
        sender.Recreate(rt_device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, content);
        current_size = content;
      }
    } catch (...) { if (cursor_free) cursor_free_failed = true; else capture_failed = true; }
  }
  void CloseCapture() {
    Direct3D11CaptureFramePool old_pool{nullptr};
    GraphicsCaptureSession old_capture{nullptr};
    GraphicsCaptureItem old_item{nullptr};
    Direct3D11CaptureFramePool old_cursor_pool{nullptr};
    GraphicsCaptureSession old_cursor_capture{nullptr};
    {
      std::lock_guard<std::mutex> lock(frame_mutex);
      old_pool = std::exchange(pool, nullptr);
      old_capture = std::exchange(capture, nullptr);
      old_item = std::exchange(item, nullptr);
      old_cursor_pool = std::exchange(cursor_free_pool, nullptr);
      old_cursor_capture = std::exchange(cursor_free_capture, nullptr);
    }
    // Close may wait for the last event handler. Never hold its mutex here.
    try { if (old_pool) old_pool.FrameArrived(frame_token); } catch (...) {}
    try { if (old_cursor_pool) old_cursor_pool.FrameArrived(cursor_free_token); } catch (...) {}
    try { if (old_item) old_item.Closed(closed_token); } catch (...) {}
    try { if (old_capture) old_capture.Close(); } catch (...) {}
    try { if (old_pool) old_pool.Close(); } catch (...) {}
    try { if (old_cursor_capture) old_cursor_capture.Close(); } catch (...) {}
    try { if (old_cursor_pool) old_cursor_pool.Close(); } catch (...) {}
    std::lock_guard<std::mutex> lock(frame_mutex);
    latest.reset();
    cursor_free_latest.reset();
  }
  void DrainAudio(MicrophoneCapture& microphone, GpuVideoWriter& writer,
                  const RecordingClock& clock, LONGLONG end, LONGLONG& written_audio_frames,
                  bool& got_audio, RecordingAudioMixer* mixer = nullptr) {
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
        if (mixer) {
          if (!mixer->Add(true, first, pcm, count)) { Fail(ScreenRecordingReason::microphone); throw hresult_error(E_FAIL); }
        } else {
          const HRESULT saved = writer.WriteAudio(pcm, static_cast<UINT>(count), first * kSecond / kAudioRate);
          if (FAILED(saved)) { Fail(ScreenRecordingReason::encoder); check_hresult(saved); }
        }
        written_audio_frames = first + static_cast<LONGLONG>(count);
        std::lock_guard<std::mutex> lock(status_mutex);
        if (!mixer) status.audio_frames += count;
        status.loudest_rms_db = std::max(status.loudest_rms_db, status.rms_db);
      }
    }
  }
  void DrainSystem(SystemAudioCapture& system, RecordingAudioMixer& mixer,
                   const RecordingClock& clock, LONGLONG end) {
    while (true) {
      SystemAudioPacket packet;
      const auto read = system.Read(packet);
      if (read == S_FALSE) return;
      if (FAILED(read) || packet.timestamp_error || packet.pcm.empty() || packet.pcm.size() % 2 != 0) {
        Fail(ScreenRecordingReason::systemAudio); throw hresult_error(FAILED(read) ? read : E_FAIL);
      }
      // A loopback endpoint may stop emitting packets when Windows is idle.
      // QPC placement and silent ring slots retain that gap, including a normal
      // discontinuity when playback restarts. Timestamp/device errors still stop.
      for (const auto& slice : clock.Audio(static_cast<LONGLONG>(packet.qpc_100ns), packet.pcm.size() / 2, kAudioRate)) {
        const auto first = static_cast<LONGLONG>(std::llround(static_cast<double>(slice.time_100ns) * kAudioRate / kSecond));
        auto count = slice.count;
        if (end >= 0) {
          const auto limit = end * kAudioRate / kSecond;
          if (first >= limit) continue;
          count = std::min(count, static_cast<size_t>(limit - first));
        }
        if (!count) continue;
        const auto* pcm = packet.pcm.data() + slice.offset * 2;
        if (!mixer.Add(false, first, pcm, count)) { Fail(ScreenRecordingReason::systemAudio); throw hresult_error(E_FAIL); }
        double squares = 0;
        for (size_t sample = 0; sample < count * 2; ++sample) {
          const double value = pcm[sample] / 32768.0; squares += value * value;
        }
        std::lock_guard<std::mutex> lock(status_mutex);
        status.system_audio_frames += count;
        status.loudest_system_rms_db = std::max(status.loudest_system_rms_db, Db(std::sqrt(squares / (count * 2))));
      }
    }
  }
  void FlushMixed(GpuVideoWriter& writer, RecordingAudioMixer& mixer, LONGLONG end) {
    const auto limit = std::max<LONGLONG>(0, end) * kAudioRate / kSecond;
    std::vector<int16_t> pcm;
    while (mixer.Position() < limit) {
      const auto count = static_cast<size_t>(std::min<LONGLONG>(480, limit - mixer.Position()));
      const auto time = mixer.Position() * kSecond / kAudioRate;
      if (!mixer.Read(count, pcm)) throw hresult_error(E_FAIL);
      const auto saved = writer.WriteAudio(pcm.data(), static_cast<UINT>(count), time);
      if (FAILED(saved)) { Fail(ScreenRecordingReason::encoder); check_hresult(saved); }
      std::lock_guard<std::mutex> lock(status_mutex); status.audio_frames += count;
    }
  }
  void Run(HMONITOR monitor, HWND window, const std::wstring& path,
           const std::wstring& microphone_id, bool record_audio,
           const std::wstring& camera_id, const std::wstring& camera_path, bool record_system_audio, const std::wstring& activity_path,
           const std::wstring& cursor_free_path) noexcept {
    bool initialized = false, writer_started = false, camera_writer_started = false;
    GpuVideoWriter writer;
    GpuVideoWriter camera_writer;
    GpuVideoWriter cursor_free_writer;
    bool cursor_free_started = false;
    MicrophoneCapture microphone;
    SystemAudioCapture system;
    RecordingAudioMixer mixer;
    RecordingActivity activity;
    ActivityWriter activity_writer;
    std::unique_ptr<RecordingClock> activity_clock;
    std::vector<ActivityEvent> activity_pending;
    auto drain_activity = [&](bool final) {
      if (activity_path.empty() || !activity_clock) return;
      auto events = activity.Drain();
      activity_pending.insert(activity_pending.end(), events.begin(), events.end());
      if (activity_pending.size() > 8192 || activity.Failed()) {
        Fail(ScreenRecordingReason::activity); throw hresult_error(E_FAIL);
      }
      const auto end = Status().duration_100ns;
      std::vector<ActivityEvent> later;
      for (const auto& event : activity_pending) {
        int64_t time = 0;
        if (!activity_clock->Event(event.qpc_100ns, time)) continue;
        if (time >= end) { if (!final) later.push_back(event); continue; }
        const auto saved = activity_writer.Write(event, time);
        if (FAILED(saved)) { Fail(ScreenRecordingReason::activity); check_hresult(saved); }
      }
      activity_pending.swap(later);
      std::lock_guard<std::mutex> lock(status_mutex); status.activity_events = activity_writer.Count();
    };
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
      if (!cursor_free_path.empty()) {
        try {
          capture.IsCursorCaptureEnabled(true);
          if (!capture.IsCursorCaptureEnabled()) throw hresult_error(E_FAIL);
          cursor_free_size = size;
          cursor_free_pool = Direct3D11CaptureFramePool::CreateFreeThreaded(rt_device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
          cursor_free_token = cursor_free_pool.FrameArrived([weak](const auto& sender, const auto&) {
            if (const auto self = weak.lock()) self->OnFrame(sender, true);
          });
          cursor_free_capture = cursor_free_pool.CreateCaptureSession(item);
          cursor_free_capture.IsCursorCaptureEnabled(false);
          if (cursor_free_capture.IsCursorCaptureEnabled()) throw hresult_error(E_FAIL);
          cursor_free_capture.StartCapture();
        } catch (...) { cursor_free_failed = true; }
      }
      capture.StartCapture();  // Keep the Windows capture border enabled.
      const LONGLONG started_waiting = QpcTime();
      std::shared_ptr<CapturedFrame> first;
      while (!stop && !source_closed && !capture_failed && QpcTime() - started_waiting < 5 * kSecond) {
        { std::lock_guard<std::mutex> lock(frame_mutex); first = latest; }
        bool clean_ready;
        { std::lock_guard<std::mutex> lock(frame_mutex); clean_ready = cursor_free_latest != nullptr; }
        if (first && (cursor_free_path.empty() || cursor_free_failed || clean_ready)) break;
        Sleep(5);
      }
      if (stop) { Fail(ScreenRecordingReason::cancelled); throw hresult_error(E_ABORT); }
      if (!first || source_closed || capture_failed || (window && IsIconic(window))) throw hresult_error(E_FAIL);
      const double scale = std::min(1.0, 1920.0 / std::max(first->width, first->height));
      const UINT width = std::max<UINT>(2, static_cast<UINT>(first->width * scale) / 2 * 2);
      const UINT height = std::max<UINT>(2, static_cast<UINT>(first->height * scale) / 2 * 2);
      if (!camera_id.empty()) {
        stage = ScreenRecordingReason::camera;
#ifdef SPAWNALPHA_CAMERA_FIXTURE
        check_hresult(camera.OpenFixture(camera_id));
#else
        check_hresult(camera.Open(camera_id));
#endif
        const auto camera_wait = QpcTime();
        std::shared_ptr<const CameraFrame> camera_first;
        while (!stop && !camera.Failed() && QpcTime() - camera_wait < 5 * kSecond) {
          camera_first = camera.Latest(); if (camera_first) break; Sleep(5);
        }
        if (stop) { Fail(ScreenRecordingReason::cancelled); throw hresult_error(E_ABORT); }
        if (!camera_first || camera.Failed()) throw hresult_error(E_FAIL);
        const double camera_scale = std::min(1.0, 1280.0 / std::max(camera_first->width, camera_first->height));
        const UINT camera_width = std::max<UINT>(2, static_cast<UINT>(camera_first->width * camera_scale) / 2 * 2);
        const UINT camera_height = std::max<UINT>(2, static_cast<UINT>(camera_first->height * camera_scale) / 2 * 2);
        stage = ScreenRecordingReason::encoder;
        // Camera stays a separate, silent fragmented MP4. Chosen microphone
        // audio lives in the screen file once, on the same recording clock.
        check_hresult(camera_writer.Start(device.get(), camera_path, camera_width, camera_height, kFramesPerSecond));
        camera_writer_started = true;
      }
      if (record_audio) {
        stage = ScreenRecordingReason::microphone;
        check_hresult(microphone.Open(microphone_id));
      }
      if (record_system_audio) {
        stage = ScreenRecordingReason::systemAudio;
        check_hresult(system.Open());
      }
      stage = ScreenRecordingReason::encoder;
      check_hresult(writer.Start(device.get(), path, width, height, kFramesPerSecond,
          record_system_audio ? GpuAudioFormat{kAudioRate, 2} :
              record_audio ? GpuAudioFormat{kAudioRate, 1} : GpuAudioFormat{}));
      writer_started = true;
      if (!cursor_free_path.empty() && !cursor_free_failed) {
        bool clean_ready;
        { std::lock_guard<std::mutex> lock(frame_mutex); clean_ready = cursor_free_latest != nullptr; }
        if (clean_ready) {
          // Reserve required screen/camera encoders first. An optional silent
          // picture must never take their hardware slot. Original video/audio
          // keeps the Windows pointer; partial companions are never eligible.
          const auto result = cursor_free_writer.Start(device.get(), cursor_free_path, width, height, kFramesPerSecond);
          cursor_free_started = SUCCEEDED(result);
          if (!cursor_free_started) cursor_free_failed = true;
        } else cursor_free_failed = true;
      }
      if (stop) { Fail(ScreenRecordingReason::cancelled); throw hresult_error(E_ABORT); }
      if (record_audio) {
        stage = ScreenRecordingReason::microphone;
        check_hresult(microphone.Start());
      }
      if (record_system_audio) {
        stage = ScreenRecordingReason::systemAudio;
        check_hresult(system.Start());
      }
      if (!activity_path.empty()) {
        stage = ScreenRecordingReason::activity;
        check_hresult(activity_writer.Start(activity_path));
        check_hresult(activity.Start(monitor, window));
        check_hresult(activity_writer.Flush());
      }
      // File flush/input startup belongs to setup, not the saved take clock.
      // Windows fragmented MP4 can shift a stream whose first sample is late.
      const LONGLONG origin = QpcTime();
      RecordingClock clock(origin);
      if (!activity_path.empty()) activity_clock = std::make_unique<RecordingClock>(origin);
      LONGLONG activity_flush = origin;
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
        const auto camera_frame = camera_id.empty() ? nullptr : camera.Latest();
        if (!camera_id.empty() && (camera.Failed() || !camera_frame || now - camera_frame->arrived_100ns > 5 * kSecond)) {
          Fail(ScreenRecordingReason::camera); break;
        }
        if (paused != wanted_paused.load()) {
          paused = wanted_paused.load();
          clock.Pause(paused, now);
          if (activity_clock) activity_clock->Pause(paused, now);
          SetState(paused ? ScreenRecordingState::paused : ScreenRecordingState::recording);
        }
        const LONGLONG elapsed = clock.Time(now);
        const auto lag = elapsed - static_cast<LONGLONG>(next_frame) * kSecond / kFramesPerSecond;
        // Check pressure before draining sound. Otherwise a stalled encoder
        // could save audio beyond the final useful video frame before stopping.
        if (!paused && next_frame != 0 && lag > kSecond) {
          Fail(ScreenRecordingReason::encoder); break;
        }
        if (!paused && cursor_free_started && !cursor_free_failed && lag > kSecond / 2) {
          cursor_free_failed = true;
          cursor_free_writer.Finish(false);
        }
        if (record_audio) DrainAudio(microphone, writer, clock, -1, audio_frames, got_audio, record_system_audio ? &mixer : nullptr);
        if (record_system_audio) {
          DrainSystem(system, mixer, clock, -1);
          // Give both endpoints a bounded 100 ms arrival margin. Final stop
          // flushes exactly to the saved video end, removing pauses from all.
          FlushMixed(writer, mixer, std::min(elapsed - kSecond / 10, Status().duration_100ns));
        }
        if (!paused && elapsed >= static_cast<LONGLONG>(next_frame) * kSecond / kFramesPerSecond) {
          // Encode a continuous cadence from the bounded latest snapshots.
          // Sparse timestamps are rewritten inside Windows MP4 fragments and
          // can move picture away from sound/activity. Brief stalls repeat the
          // latest picture while catching up; no frame queue grows.
          std::shared_ptr<CapturedFrame> frame;
          { std::lock_guard<std::mutex> lock(frame_mutex); frame = latest; }
          if (frame) {
            const LONGLONG time = static_cast<LONGLONG>(next_frame) * kSecond / kFramesPerSecond;
            stage = ScreenRecordingReason::encoder;
            check_hresult(writer.WriteFrame(frame->texture.get(), frame->width, frame->height, time));
            if (cursor_free_started && !cursor_free_failed) {
              std::shared_ptr<CapturedFrame> clean_frame;
              { std::lock_guard<std::mutex> lock(frame_mutex); clean_frame = cursor_free_latest; }
              if (!clean_frame || FAILED(cursor_free_writer.WriteFrame(clean_frame->texture.get(), clean_frame->width, clean_frame->height, time))) {
                cursor_free_failed = true;
              } else {
                std::lock_guard<std::mutex> lock(status_mutex); ++status.cursor_free_frames;
              }
            }
            if (camera_frame) {
              D3D11_TEXTURE2D_DESC camera_desc{};
              camera_desc.Width = camera_frame->width; camera_desc.Height = camera_frame->height;
              camera_desc.MipLevels = 1; camera_desc.ArraySize = 1;
              camera_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
              camera_desc.SampleDesc.Count = 1; camera_desc.Usage = D3D11_USAGE_DEFAULT;
              camera_desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
              const D3D11_SUBRESOURCE_DATA pixels{camera_frame->bgra.data(), camera_frame->width * 4, 0};
              com_ptr<ID3D11Texture2D> camera_texture;
              check_hresult(device->CreateTexture2D(&camera_desc, &pixels, camera_texture.put()));
              check_hresult(camera_writer.WriteFrame(camera_texture.get(), camera_frame->width, camera_frame->height, time));
            }
            std::lock_guard<std::mutex> lock(status_mutex);
            ++status.frames; if (camera_frame) ++status.camera_frames;
            status.duration_100ns = time + kSecond / kFramesPerSecond;
          }
          ++next_frame;
#ifdef SPAWNALPHA_RECORDING_FIXTURE
          if (next_frame == 10 && fixture_stall) Sleep(fixture_stall);
#endif
        }
        drain_activity(false);
        if (!activity_path.empty() && now - activity_flush >= kSecond) {
          const auto flushed = activity_writer.Flush();
          if (FAILED(flushed)) { Fail(ScreenRecordingReason::activity); check_hresult(flushed); }
          activity_flush = now;
        }
        Sleep(2);
      }
      SetState(ScreenRecordingState::saving);
      if (record_audio) DrainAudio(microphone, writer, clock, Status().duration_100ns, audio_frames, got_audio, record_system_audio ? &mixer : nullptr);
      if (record_system_audio) {
        DrainSystem(system, mixer, clock, Status().duration_100ns);
        FlushMixed(writer, mixer, Status().duration_100ns);
      }
    } catch (...) {
      if (Status().reason == ScreenRecordingReason::none) Fail(stage);
    }
    stop = true;
    activity.Stop();
    try { drain_activity(true); }
    catch (...) { Fail(ScreenRecordingReason::activity); }
    if (FAILED(activity_writer.Finish(Status().duration_100ns, Status().reason == ScreenRecordingReason::none))) Fail(ScreenRecordingReason::activity);
    if (writer_started && record_system_audio) {
      try { FlushMixed(writer, mixer, Status().duration_100ns); }
      catch (...) { Fail(ScreenRecordingReason::encoder); }
    }
    microphone.Stop();
    system.Stop();
    camera.Stop();
    CloseCapture();
    if (writer_started) {
      SetState(ScreenRecordingState::saving);
      if (FAILED(writer.Finish())) Fail(ScreenRecordingReason::encoder);
    }
    // Release all WinRT/COM objects before uninitializing the worker apartment.
    writer.Finish();
    if (camera_writer_started && FAILED(camera_writer.Finish())) Fail(ScreenRecordingReason::encoder);
    camera_writer.Finish();
    if (cursor_free_started && FAILED(cursor_free_writer.Finish(!cursor_free_failed))) cursor_free_failed = true;
    cursor_free_writer.Finish();
    {
      std::lock_guard<std::mutex> lock(status_mutex);
      status.cursor_free_complete = cursor_free_started && !cursor_free_failed && status.frames > 0 && status.cursor_free_frames == status.frames;
    }
    rt_device = nullptr; context = nullptr; device = nullptr;
    if (initialized) uninit_apartment();
    const auto result = Status();
    SetState(result.frames ? ScreenRecordingState::finished : ScreenRecordingState::failed);
  }
  std::thread worker;
  CameraCapture camera;
  std::atomic<bool> stop{false}, source_closed{false}, capture_failed{false}, wanted_paused{false};
  std::atomic<bool> cursor_free_failed{false};
  mutable std::mutex status_mutex;
  ScreenRecordingStatus status{};
  std::mutex frame_mutex;
  std::shared_ptr<CapturedFrame> latest;
  std::shared_ptr<CapturedFrame> cursor_free_latest;
  com_ptr<ID3D11Device> device;
  com_ptr<ID3D11DeviceContext> context;
  IDirect3DDevice rt_device{nullptr};
  GraphicsCaptureItem item{nullptr};
  Direct3D11CaptureFramePool pool{nullptr};
  GraphicsCaptureSession capture{nullptr};
  Direct3D11CaptureFramePool cursor_free_pool{nullptr};
  GraphicsCaptureSession cursor_free_capture{nullptr};
  SizeInt32 cursor_free_size{};
  event_token cursor_free_token{};
  SizeInt32 size{};
  event_token frame_token{}, closed_token{};
};

ScreenRecordingCore::ScreenRecordingCore() : impl_(std::make_shared<Impl>()) {}
ScreenRecordingCore::~ScreenRecordingCore() { impl_->StopAndJoin(); }
HRESULT ScreenRecordingCore::Start(HMONITOR monitor, HWND window, const std::wstring& path,
                                  const std::wstring& microphone_id, bool record_audio,
                                  const std::wstring& camera_id, const std::wstring& camera_path, bool record_system_audio, const std::wstring& activity_path,
                                  const std::wstring& cursor_free_path) {
  return impl_->Start(monitor, window, path, microphone_id, record_audio, camera_id, camera_path, record_system_audio, activity_path, cursor_free_path);
}
void ScreenRecordingCore::RequestStop() { impl_->stop = true; }
void ScreenRecordingCore::SetPaused(bool paused) { impl_->wanted_paused = paused; }
ScreenRecordingStatus ScreenRecordingCore::Status() const { return impl_->Status(); }
std::shared_ptr<const CameraFrame> ScreenRecordingCore::LatestCamera() const { return impl_->camera.Latest(); }

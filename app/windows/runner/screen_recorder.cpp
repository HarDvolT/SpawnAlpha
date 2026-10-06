#include "screen_recorder.h"
#include "screen_recording_core.h"
#include "screen_sources.h"
#include "recording_probe.h"
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/base.h>
#include <thread>
#include <mutex>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
const std::string* StringArgument(const EncodableMap& map, const char* name) {
  const auto found = map.find(EncodableValue(name));
  return found == map.end() ? nullptr : std::get_if<std::string>(&found->second);
}
int64_t SessionId(const EncodableMap& map) {
  const auto found = map.find(EncodableValue("sessionId"));
  if (found == map.end()) return -1;
  if (const auto id = std::get_if<int64_t>(&found->second)) return *id;
  if (const auto id = std::get_if<int32_t>(&found->second)) return *id;
  return -1;
}
std::string State(ScreenRecordingState state) {
  switch (state) {
    case ScreenRecordingState::starting: return "starting";
    case ScreenRecordingState::recording: return "recording";
    case ScreenRecordingState::paused: return "paused";
    case ScreenRecordingState::saving: return "saving";
    case ScreenRecordingState::finished: return "finished";
    default: return "failed";
  }
}
std::string Reason(ScreenRecordingReason reason) {
  switch (reason) {
    case ScreenRecordingReason::cancelled: return "cancelled";
    case ScreenRecordingReason::source: return "source";
    case ScreenRecordingReason::microphone: return "microphone";
    case ScreenRecordingReason::encoder: return "encoder";
    case ScreenRecordingReason::camera: return "camera";
    case ScreenRecordingReason::systemAudio: return "systemAudio";
    default: return "none";
  }
}
EncodableMap Status(const ScreenRecordingStatus& status) {
  return {
    {EncodableValue("state"), EncodableValue(State(status.state))},
    {EncodableValue("reason"), EncodableValue(Reason(status.reason))},
    {EncodableValue("width"), EncodableValue(static_cast<int32_t>(status.width))},
    {EncodableValue("height"), EncodableValue(static_cast<int32_t>(status.height))},
    {EncodableValue("frames"), EncodableValue(static_cast<int64_t>(status.frames))},
    {EncodableValue("audioFrames"), EncodableValue(static_cast<int64_t>(status.audio_frames))},
    {EncodableValue("cameraFrames"), EncodableValue(static_cast<int64_t>(status.camera_frames))},
    {EncodableValue("systemAudioFrames"), EncodableValue(static_cast<int64_t>(status.system_audio_frames))},
    {EncodableValue("durationUs"), EncodableValue(status.duration_100ns / 10)},
    {EncodableValue("peakDb"), EncodableValue(status.peak_db)},
    {EncodableValue("rmsDb"), EncodableValue(status.rms_db)},
    {EncodableValue("loudestRmsDb"), EncodableValue(status.loudest_rms_db)},
    {EncodableValue("loudestSystemRmsDb"), EncodableValue(status.loudest_system_rms_db)},
  };
}
struct ProbeJob {
  explicit ProbeJob(std::wstring path) {
    worker = std::thread([this, path] {
      const auto result = ProbeRecording(path, cancelled);
      std::lock_guard<std::mutex> lock(mutex);
      info = result; ready = true;
    });
  }
  ~ProbeJob() { cancelled = true; if (worker.joinable()) worker.join(); }
  EncodableMap Status() {
    std::lock_guard<std::mutex> lock(mutex);
    return {{EncodableValue("ready"), EncodableValue(ready)},
      {EncodableValue("readable"), EncodableValue(info.readable)},
      {EncodableValue("hasAudio"), EncodableValue(info.has_audio)},
      {EncodableValue("width"), EncodableValue(static_cast<int32_t>(info.width))},
      {EncodableValue("height"), EncodableValue(static_cast<int32_t>(info.height))},
      {EncodableValue("durationUs"), EncodableValue(info.duration_100ns / 10)}};
  }
  bool Ready() { std::lock_guard<std::mutex> lock(mutex); return ready; }
  std::atomic<bool> cancelled{false};
  std::mutex mutex;
  RecordingInfo info{};
  bool ready = false;
  std::thread worker;
};
}  // namespace

struct ScreenRecorder::Impl {
  explicit Impl(flutter::BinaryMessenger* messenger)
      : channel(messenger, "spawnalpha/screen_recording", &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid", "Choose the screen and microphone first."); return; }
      try {
        if (call.method_name() == "inspectStart") {
          const auto path = StringArgument(*args, "path");
          if (!path || path->size() < 4 || (*path)[1] != ':' ||
              ((*path)[2] != '\\' && (*path)[2] != '/') || path->find('\0') != std::string::npos) {
            result->Error("invalid", "Choose a local recording."); return;
          }
          if (probe && !probe->Ready()) { result->Error("busy", "A recording is being checked."); return; }
          probe.reset();
          probe = std::make_unique<ProbeJob>(winrt::to_hstring(*path).c_str());
          result->Success(EncodableValue(++probe_generation));
        } else if (call.method_name() == "inspectStatus") {
          if (!probe || SessionId(*args) != probe_generation) {
            result->Error("expired", "Recording check expired."); return;
          }
          result->Success(EncodableValue(probe->Status()));
        } else if (call.method_name() == "inspectCancel") {
          if (probe && SessionId(*args) == probe_generation) probe->cancelled = true;
          result->Success();
        } else if (call.method_name() == "start") {
          if (active) {
            const auto state = active->Status().state;
            if (state != ScreenRecordingState::finished && state != ScreenRecordingState::failed) {
              result->Error("busy", "Stop the current recording first."); return;
            }
            active.reset();
          }
          const auto source = StringArgument(*args, "sourceId");
          const auto path = StringArgument(*args, "path");
          const auto microphone = StringArgument(*args, "microphoneId");
          const auto camera = StringArgument(*args, "cameraId");
          const auto camera_path = StringArgument(*args, "cameraPath");
          const auto audio = args->find(EncodableValue("recordAudio"));
          const auto system_audio = args->find(EncodableValue("recordSystemAudio"));
          if (!source || !path || path->empty() || audio == args->end() || !std::holds_alternative<bool>(audio->second)) {
            result->Error("invalid", "Choose the screen and microphone first."); return;
          }
          if (system_audio != args->end() && !std::holds_alternative<bool>(system_audio->second)) {
            result->Error("invalid", "Choose whether to record computer sound."); return;
          }
          if ((camera == nullptr) != (camera_path == nullptr) || (camera && (camera->empty() || camera_path->empty() || *camera_path == *path))) {
            result->Error("invalid", "Choose a camera and a separate file."); return;
          }
          HMONITOR monitor = nullptr; HWND window = nullptr;
          if (!ResolveScreenSource(*source, &monitor, &window)) {
            result->Error("source", "This source is unavailable. Choose another."); return;
          }
          auto next = std::make_unique<ScreenRecordingCore>();
          winrt::check_hresult(next->Start(monitor, window, winrt::to_hstring(*path).c_str(),
              microphone ? winrt::to_hstring(*microphone).c_str() : L"", std::get<bool>(audio->second),
              camera ? winrt::to_hstring(*camera).c_str() : L"", camera_path ? winrt::to_hstring(*camera_path).c_str() : L"",
              system_audio != args->end() && std::get<bool>(system_audio->second)));
          active = std::move(next); ++generation;
          result->Success(EncodableValue(EncodableMap{{EncodableValue("sessionId"), EncodableValue(generation)}}));
        } else if (call.method_name() == "status") {
          result->Success(EncodableValue(active && SessionId(*args) == generation ? Status(active->Status()) :
            EncodableMap{{EncodableValue("state"), EncodableValue("failed")},
                         {EncodableValue("reason"), EncodableValue("cancelled")}}));
        } else if (call.method_name() == "pause") {
          const auto paused = args->find(EncodableValue("paused"));
          if (paused == args->end() || !std::holds_alternative<bool>(paused->second)) {
            result->Error("invalid", "Choose pause or resume."); return;
          }
          if (active && SessionId(*args) == generation) active->SetPaused(std::get<bool>(paused->second));
          result->Success();
        } else if (call.method_name() == "stop") {
          if (active && SessionId(*args) == generation) active->RequestStop();
          result->Success();
        } else if (call.method_name() == "release") {
          // Destruction requests Stop and joins the worker/finalizer. Dart must
          // await this acknowledgement before restoring main-window affinity.
          if (active && SessionId(*args) == generation) active.reset();
          result->Success();
        } else { result->NotImplemented(); }
      } catch (...) {
        result->Error("unavailable", "Could not start recording. Check the source and microphone.");
      }
    });
  }
  ~Impl() { channel.SetMethodCallHandler(nullptr); active.reset(); probe.reset(); }
  flutter::MethodChannel<EncodableValue> channel;
  std::unique_ptr<ScreenRecordingCore> active;
  int64_t generation = 0;
  std::unique_ptr<ProbeJob> probe;
  int64_t probe_generation = 0;
};
ScreenRecorder::ScreenRecorder(flutter::BinaryMessenger* messenger) : impl_(std::make_unique<Impl>(messenger)) {}
std::shared_ptr<const CameraFrame> ScreenRecorder::LatestCamera() const {
  if (!impl_->active) return nullptr;
  const auto phase = impl_->active->Status().state;
  return phase == ScreenRecordingState::recording || phase == ScreenRecordingState::paused
      ? impl_->active->LatestCamera() : nullptr;
}
ScreenRecorder::~ScreenRecorder() = default;

#include "screen_recorder.h"
#include "screen_recording_core.h"
#include "screen_sources.h"
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/base.h>

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
    {EncodableValue("durationUs"), EncodableValue(status.duration_100ns / 10)},
    {EncodableValue("peakDb"), EncodableValue(status.peak_db)},
    {EncodableValue("rmsDb"), EncodableValue(status.rms_db)},
    {EncodableValue("loudestRmsDb"), EncodableValue(status.loudest_rms_db)},
  };
}
}  // namespace

struct ScreenRecorder::Impl {
  explicit Impl(flutter::BinaryMessenger* messenger)
      : channel(messenger, "spawnalpha/screen_recording", &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid", "Choose the screen and microphone first."); return; }
      try {
        if (call.method_name() == "start") {
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
          const auto audio = args->find(EncodableValue("recordAudio"));
          if (!source || !path || path->empty() || audio == args->end() || !std::holds_alternative<bool>(audio->second)) {
            result->Error("invalid", "Choose the screen and microphone first."); return;
          }
          HMONITOR monitor = nullptr; HWND window = nullptr;
          if (!ResolveScreenSource(*source, &monitor, &window)) {
            result->Error("source", "This source is unavailable. Choose another."); return;
          }
          auto next = std::make_unique<ScreenRecordingCore>();
          winrt::check_hresult(next->Start(monitor, window, winrt::to_hstring(*path).c_str(),
              microphone ? winrt::to_hstring(*microphone).c_str() : L"", std::get<bool>(audio->second)));
          active = std::move(next); ++generation;
          result->Success(EncodableValue(EncodableMap{{EncodableValue("sessionId"), EncodableValue(generation)}}));
        } else if (call.method_name() == "status") {
          result->Success(EncodableValue(active && SessionId(*args) == generation ? Status(active->Status()) :
            EncodableMap{{EncodableValue("state"), EncodableValue("failed")},
                         {EncodableValue("reason"), EncodableValue("cancelled")}}));
        } else if (call.method_name() == "stop") {
          if (active && SessionId(*args) == generation) active->RequestStop();
          result->Success();
        } else { result->NotImplemented(); }
      } catch (...) {
        result->Error("unavailable", "Could not start recording. Check the source and microphone.");
      }
    });
  }
  ~Impl() { channel.SetMethodCallHandler(nullptr); active.reset(); }
  flutter::MethodChannel<EncodableValue> channel;
  std::unique_ptr<ScreenRecordingCore> active;
  int64_t generation = 0;
};
ScreenRecorder::ScreenRecorder(flutter::BinaryMessenger* messenger) : impl_(std::make_unique<Impl>(messenger)) {}
ScreenRecorder::~ScreenRecorder() = default;

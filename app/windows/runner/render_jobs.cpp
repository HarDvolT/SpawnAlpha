#include "render_jobs.h"
#include "local_render.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mfapi.h>
#include <winrt/base.h>
#include <mutex>
#include <thread>
#include <stdexcept>
#include <cmath>
namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
const Value& Field(const Map& args, const char* key) {
  const auto found = args.find(Value(key));
  if (found == args.end()) throw std::runtime_error("Invalid render request");
  return found->second;
}
int64_t Integer(const Map& args, const char* key) {
  const auto& value = Field(args, key);
  if (const auto number = std::get_if<int64_t>(&value)) return *number;
  if (const auto number = std::get_if<int32_t>(&value)) return *number;
  throw std::runtime_error("Invalid render request");
}
std::wstring Path(const Map& args, const char* key) {
  const auto& value = Field(args, key);
  const auto text = std::get_if<std::string>(&value);
  if (!text || text->size() > 131040) throw std::runtime_error("Invalid render request");
  return std::wstring(winrt::to_hstring(*text));
}
LocalRenderRequest Request(const Map& args) {
  LocalRenderRequest request;
  request.source = Path(args, "source"); request.camera = Path(args, "camera"); request.output = Path(args, "output");
  request.source_duration_us = Integer(args, "sourceDurationUs");
  const auto* inset = std::get_if<double>(&Field(args, "cameraInset"));
  const auto* margin = std::get_if<double>(&Field(args, "cameraMargin"));
  if (!inset || !margin || !std::isfinite(*inset) || !std::isfinite(*margin)) throw std::runtime_error("Invalid render layout");
  request.camera_inset = *inset; request.camera_margin = *margin;
  const auto width = Integer(args, "width"), height = Integer(args, "height");
  if (width < 2 || width > 4096 || height < 2 || height > 4096) throw std::runtime_error("Invalid render size");
  request.width = static_cast<UINT>(width); request.height = static_cast<UINT>(height);
  const auto* ranges = std::get_if<flutter::EncodableList>(&Field(args, "ranges"));
  if (!ranges || ranges->empty() || ranges->size() > 20001) throw std::runtime_error("Invalid render ranges");
  for (const auto& value : *ranges) {
    const auto* range = std::get_if<Map>(&value);
    if (!range) throw std::runtime_error("Invalid render range");
    request.ranges.push_back({Integer(*range, "startUs"), Integer(*range, "endUs")});
  }
  return request;
}
}
struct RenderJobs::Impl {
  explicit Impl(flutter::BinaryMessenger* messenger)
      : channel(messenger, "spawnalpha/render", &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this](const auto& call, auto reply) {
      try {
        if (!call.arguments() || !std::holds_alternative<Map>(*call.arguments())) throw std::runtime_error("Invalid render request");
        const auto& args = std::get<Map>(*call.arguments());
        const auto& method = call.method_name();
        if (method == "start") {
          { std::lock_guard<std::mutex> lock(mutex); if (state == "working") { reply->Error("busy", "Video export is busy"); return; } }
          if (worker.joinable()) worker.join();
          const auto request = Request(args);
          cancel = false;
          { std::lock_guard<std::mutex> lock(mutex); ++session; state = "working"; progress = 0; }
          worker = std::thread([this, request] {
            const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED); bool mf = false;
            try {
              winrt::check_hresult(com); winrt::check_hresult(MFStartup(MF_VERSION)); mf = true;
              RenderLocalVideo(request, cancel, [this](double value) { std::lock_guard<std::mutex> lock(mutex); progress = value; });
              std::lock_guard<std::mutex> lock(mutex);
              if (cancel) { DeleteFileW(request.output.c_str()); state = "cancelled"; }
              else { state = "ready"; progress = 1; }
            } catch (...) { std::lock_guard<std::mutex> lock(mutex); state = cancel ? "cancelled" : "failed"; }
            if (mf) MFShutdown(); if (SUCCEEDED(com)) CoUninitialize();
          });
          reply->Success(Value(session)); return;
        }
        const auto id = Integer(args, "sessionId");
        std::lock_guard<std::mutex> lock(mutex);
        if (id != session) { reply->Error("session", "Video export unavailable"); return; }
        if (method == "cancel") { if (state == "working") cancel = true; reply->Success(); return; }
        if (method == "status") { reply->Success(Value(Map{{Value("state"), Value(state)}, {Value("progress"), Value(progress)}})); return; }
        reply->NotImplemented();
      } catch (...) { reply->Error("invalid", "Video export unavailable"); }
    });
  }
  ~Impl() { channel.SetMethodCallHandler(nullptr); cancel = true; if (worker.joinable()) worker.join(); }
  flutter::MethodChannel<Value> channel;
  std::mutex mutex; std::thread worker;
  std::atomic<bool> cancel{false}; int64_t session = 0;
  std::string state = "idle"; double progress = 0;
};
RenderJobs::RenderJobs(flutter::BinaryMessenger* messenger) : impl_(std::make_unique<Impl>(messenger)) {}
RenderJobs::~RenderJobs() = default;

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
double Number(const Map& args, const char* key) {
  const auto* value = std::get_if<double>(&Field(args, key));
  if (!value || !std::isfinite(*value)) throw std::runtime_error("Invalid render layout");
  return *value;
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
  if (args.find(Value("audioJoinFadeUs")) != args.end())
    request.audio_join_fade_us = Integer(args, "audioJoinFadeUs");
  if (request.audio_join_fade_us < 0 || request.audio_join_fade_us > 100000)
    throw std::runtime_error("Invalid sound joins");
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
  if (const auto found = args.find(Value("captions")); found != args.end()) {
    const auto* captions = std::get_if<flutter::EncodableList>(&found->second);
    if (!captions || captions->size() > 100000) throw std::runtime_error("Invalid captions");
    size_t text_total = 0;
    for (const auto& value : *captions) {
      const auto* caption = std::get_if<Map>(&value);
      if (!caption) throw std::runtime_error("Invalid caption");
      const auto text = Path(*caption, "text"); text_total += text.size();
      if (text.empty() || text.size() > 4096 || text_total > 4 * 1024 * 1024) throw std::runtime_error("Invalid caption");
      RenderCaption phrase{Integer(*caption, "startUs"), Integer(*caption, "endUs"), text};
      if (const auto found_words = caption->find(Value("words")); found_words != caption->end()) {
        const auto* words = std::get_if<flutter::EncodableList>(&found_words->second);
        if (!words || words->size() > 7) throw std::runtime_error("Invalid caption words");
        for (const auto& item : *words) {
          const auto* word = std::get_if<Map>(&item);
          if (!word) throw std::runtime_error("Invalid caption word");
          const auto offset = Integer(*word, "offset"), length = Integer(*word, "length");
          if (offset < 0 || offset > 4096 || length < 1 || length > 4096) throw std::runtime_error("Invalid caption range");
          phrase.words.push_back({static_cast<UINT>(offset), static_cast<UINT>(length), Integer(*word, "startUs"), Integer(*word, "endUs")});
          auto& timed = phrase.words.back();
          for (const auto* key : {"stress", "energy"}) {
            if (const auto field = word->find(Value(key)); field != word->end()) {
              const auto* enabled = std::get_if<bool>(&field->second);
              if (!enabled) throw std::runtime_error("Invalid caption cue");
              if (std::string(key) == "stress") timed.stress = *enabled; else timed.energy = *enabled;
            }
          }
          if (const auto field = word->find(Value("pace")); field != word->end()) {
            const auto* pace = std::get_if<std::string>(&field->second);
            if (!pace || (*pace != "normal" && *pace != "slower" && *pace != "faster")) throw std::runtime_error("Invalid caption pace");
            timed.pace = *pace == "slower" ? -1 : *pace == "faster" ? 1 : 0;
          }
        }
      }
      request.captions.push_back(std::move(phrase));
    }
    if (!captions->empty()) {
      const auto* style = std::get_if<Map>(&Field(args, "captionLayout"));
      if (!style) throw std::runtime_error("Invalid caption layout");
      auto& layout = request.caption_layout;
      const auto* rtl = std::get_if<bool>(&Field(*style, "rtl"));
      const auto text_color = Integer(*style, "textColor"), plate_color = Integer(*style, "plateColor"), weight = Integer(*style, "weight");
      if (!rtl || text_color < 0 || text_color > UINT32_MAX || plate_color < 0 || plate_color > UINT32_MAX || weight < 100 || weight > 900) throw std::runtime_error("Invalid caption layout");
      layout.rtl = *rtl; layout.text_color = static_cast<uint32_t>(text_color); layout.plate_color = static_cast<uint32_t>(plate_color); layout.weight = static_cast<UINT>(weight);
      layout.edge = Number(*style, "edge"); layout.bottom = Number(*style, "bottom");
      layout.safe_top = Number(*style, "safeTop"); layout.safe_bottom = Number(*style, "safeBottom"); layout.safe_right = Number(*style, "safeRight");
      layout.font_size = Number(*style, "fontSize"); layout.line_height = Number(*style, "lineHeight"); layout.min_size = Number(*style, "minSize");
      layout.padding = Number(*style, "padding"); layout.radius = Number(*style, "radius"); layout.shadow_offset = Number(*style, "shadowOffset");
      if (const auto found_style = style->find(Value("style")); found_style != style->end()) {
        const auto* name = std::get_if<std::string>(&found_style->second);
        if (!name || (*name != "readable" && *name != "karaoke" && *name != "cue" && *name != "punch")) throw std::runtime_error("Invalid caption style");
        layout.karaoke = *name == "karaoke";
        layout.cue = *name == "cue"; layout.punch = *name == "punch";
      }
      if (const auto field = style->find(Value("motion")); field != style->end()) {
        const auto* enabled = std::get_if<bool>(&field->second);
        if (!enabled) throw std::runtime_error("Invalid caption motion"); layout.motion = *enabled;
      }
      if (layout.karaoke) {
        const auto waiting = Integer(*style, "waitingColor"), underline = Integer(*style, "underlineColor");
        if (waiting < 0 || waiting > UINT32_MAX || underline < 0 || underline > UINT32_MAX) throw std::runtime_error("Invalid caption ink");
        layout.waiting_color = static_cast<uint32_t>(waiting); layout.underline_color = static_cast<uint32_t>(underline);
        layout.underline_size = Number(*style, "underlineSize"); layout.underline_gap = Number(*style, "underlineGap");
      }
      if (layout.cue || layout.punch || style->find(Value("popMass")) != style->end()) {
        const auto stress = Integer(*style, "stressColor"), energy = Integer(*style, "energyColor");
        if (stress < 0 || stress > UINT32_MAX || energy < 0 || energy > UINT32_MAX) throw std::runtime_error("Invalid caption ink");
        layout.stress_color = static_cast<uint32_t>(stress); layout.energy_color = static_cast<uint32_t>(energy);
        layout.rise = Number(*style, "rise"); layout.pop_start = Number(*style, "popStart"); layout.pop_max = Number(*style, "popMax");
        layout.pop_amplitude = Number(*style, "popAmplitude"); layout.punch_start = Number(*style, "punchStart");
        layout.stress_width = Number(*style, "stressWidth"); layout.punch_width = Number(*style, "punchWidth");
        layout.slower_width = Number(*style, "slowerWidth"); layout.faster_width = Number(*style, "fasterWidth");
        layout.smooth_mass = Number(*style, "smoothMass"); layout.smooth_stiffness = Number(*style, "smoothStiffness"); layout.smooth_damping = Number(*style, "smoothDamping");
        layout.pop_mass = Number(*style, "popMass"); layout.pop_stiffness = Number(*style, "popStiffness"); layout.pop_damping = Number(*style, "popDamping");
      }
    }
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

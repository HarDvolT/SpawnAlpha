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
  if (const auto found = args.find(Value("screenBlur")); found != args.end()) {
    const auto* layout = std::get_if<Map>(&found->second);
    if (!layout || layout->size() != 3) throw std::runtime_error("Invalid screen blur");
    request.screen_blur = {true, Number(*layout, "maximum"), Number(*layout, "minimum"), Integer(*layout, "shutterUs")};
  }
  if (const auto found = args.find(Value("cameraTargets")); found != args.end()) {
    const auto* targets = std::get_if<flutter::EncodableList>(&found->second);
    const auto* layout = std::get_if<Map>(&Field(args, "cameraClearLayout"));
    if (!targets || targets->size() > 20000 || !layout || layout->size() != 5)
      throw std::runtime_error("Invalid camera placement");
    request.camera_clear = {true, Number(*layout, "gap"), Integer(*layout, "intervalUs"),
      {Number(*layout, "mass"), Number(*layout, "stiffness"), Number(*layout, "damping")}};
    for (const auto& value : *targets) {
      const auto* target = std::get_if<Map>(&value);
      if (!target || target->size() != 6) throw std::runtime_error("Invalid camera target");
      const auto sw = Integer(*target, "width"), sh = Integer(*target, "height");
      if (sw < 1 || sw > 100000 || sh < 1 || sh > 100000) throw std::runtime_error("Invalid camera target");
      request.camera_targets.push_back({Integer(*target, "startUs"), Integer(*target, "endUs"),
        Number(*target, "x"), Number(*target, "y"), static_cast<UINT>(sw), static_cast<UINT>(sh)});
    }
  }
  if (const auto found = args.find(Value("punchSteps")); found != args.end()) {
    const auto* steps = std::get_if<flutter::EncodableList>(&found->second);
    const auto* main = std::get_if<bool>(&Field(args, "punchMain"));
    const auto* spring = std::get_if<Map>(&Field(args, "punchSpring"));
    if (!steps || steps->size() > 20000 || !main || !spring) throw std::runtime_error("Invalid camera emphasis");
    request.punch_main = *main; request.punch_factor = Number(args, "punchFactor");
    request.punch_spring = {Number(*spring, "mass"), Number(*spring, "stiffness"), Number(*spring, "damping")};
    for (const auto& value : *steps) {
      const auto* step = std::get_if<Map>(&value);
      if (!step || step->size() != 2) throw std::runtime_error("Invalid camera emphasis");
      const auto* zoomed = std::get_if<bool>(&Field(*step, "zoomed"));
      if (!zoomed) throw std::runtime_error("Invalid camera emphasis");
      request.punch_steps.push_back({Integer(*step, "timeUs"), *zoomed});
    }
  }
  if (const auto found = args.find(Value("screenFrame")); found != args.end()) {
    const auto* frame = std::get_if<Map>(&found->second);
    if (!frame) throw std::runtime_error("Invalid screen frame");
    auto& layout = request.screen_frame; layout.enabled = true;
    layout.inset = Number(*frame, "inset"); layout.radius = Number(*frame, "radius");
    const auto top = Integer(*frame, "topColor"), bottom = Integer(*frame, "bottomColor");
    if (top < 0 || top > UINT32_MAX || bottom < 0 || bottom > UINT32_MAX) throw std::runtime_error("Invalid screen frame");
    layout.top_color = static_cast<uint32_t>(top); layout.bottom_color = static_cast<uint32_t>(bottom);
    const auto* shadows = std::get_if<flutter::EncodableList>(&Field(*frame, "shadows"));
    if (!shadows || shadows->size() > 4) throw std::runtime_error("Invalid screen shadow");
    for (const auto& value : *shadows) {
      const auto* shadow = std::get_if<Map>(&value);
      if (!shadow) throw std::runtime_error("Invalid screen shadow");
      const auto color = Integer(*shadow, "color");
      if (color < 0 || color > UINT32_MAX) throw std::runtime_error("Invalid screen shadow");
      layout.shadows.push_back({static_cast<uint32_t>(color), Number(*shadow, "x"), Number(*shadow, "y"), Number(*shadow, "sigma")});
    }
  }
  if (const auto found = args.find(Value("zoomSteps")); found != args.end()) {
    const auto* steps = std::get_if<flutter::EncodableList>(&found->second);
    const auto* spring = std::get_if<Map>(&Field(args, "zoomSpring"));
    if (!steps || steps->size() > 20000 || !spring) throw std::runtime_error("Invalid screen zoom");
    request.zoom_spring = {Number(*spring, "mass"), Number(*spring, "stiffness"), Number(*spring, "damping")};
    for (const auto& value : *steps) {
      const auto* step = std::get_if<Map>(&value);
      if (!step) throw std::runtime_error("Invalid screen zoom");
      const auto sw = Integer(*step, "width"), sh = Integer(*step, "height");
      if (sw < 1 || sw > 100000 || sh < 1 || sh > 100000) throw std::runtime_error("Invalid screen zoom");
      request.zoom_steps.push_back({Integer(*step, "timeUs"), Number(*step, "x"), Number(*step, "y"),
        Number(*step, "factor"), static_cast<UINT>(sw), static_cast<UINT>(sh)});
    }
  }
  if (const auto found = args.find(Value("clickPulses")); found != args.end()) {
    const auto* pulses = std::get_if<flutter::EncodableList>(&found->second);
    const auto* layout = std::get_if<Map>(&Field(args, "clickLayout"));
    if (!pulses || pulses->size() > 20000 || !layout) throw std::runtime_error("Invalid click highlights");
    const auto color = Integer(*layout, "color");
    if (color < 0 || color > 0xffffffffLL) throw std::runtime_error("Invalid click highlights");
    request.click_layout = {Number(*layout, "radius"), Number(*layout, "grow"), Number(*layout, "stroke"),
      Number(*layout, "halo"), Number(*layout, "mass"), Number(*layout, "stiffness"), Number(*layout, "damping"), static_cast<uint32_t>(color)};
    for (const auto& value : *pulses) {
      const auto* pulse = std::get_if<Map>(&value);
      if (!pulse) throw std::runtime_error("Invalid click highlight");
      const auto sw = Integer(*pulse, "width"), sh = Integer(*pulse, "height");
      if (sw < 1 || sw > 100000 || sh < 1 || sh > 100000) throw std::runtime_error("Invalid click highlight");
      request.click_pulses.push_back({Integer(*pulse, "startUs"), Integer(*pulse, "endUs"),
        Number(*pulse, "x"), Number(*pulse, "y"), static_cast<UINT>(sw), static_cast<UINT>(sh)});
    }
  }
  if (const auto found = args.find(Value("shortcutBadges")); found != args.end()) {
    const auto* badges = std::get_if<flutter::EncodableList>(&found->second);
    const auto* style = std::get_if<Map>(&Field(args, "shortcutLayout"));
    if (!badges || badges->size() > 20000 || !style) throw std::runtime_error("Invalid shortcuts");
    for (const auto& value : *badges) {
      const auto* badge = std::get_if<Map>(&value);
      if (!badge || badge->size() != 3) throw std::runtime_error("Invalid shortcut");
      const auto label = Path(*badge, "label");
      if (!IsShortcutLabel(label)) throw std::runtime_error("Invalid shortcut");
      request.shortcut_badges.push_back({Integer(*badge, "startUs"), Integer(*badge, "endUs"), label});
    }
    auto& layout = request.shortcut_layout;
    layout.keycap = true;
    const auto text = Integer(*style, "textColor"), plate = Integer(*style, "plateColor"), weight = Integer(*style, "weight");
    if (text < 0 || text > UINT32_MAX || plate < 0 || plate > UINT32_MAX || weight < 100 || weight > 900)
      throw std::runtime_error("Invalid shortcut layout");
    layout.text_color = static_cast<uint32_t>(text); layout.plate_color = static_cast<uint32_t>(plate); layout.weight = static_cast<UINT>(weight);
    layout.edge = Number(*style, "edge"); layout.safe_top = Number(*style, "safeTop"); layout.safe_right = Number(*style, "safeRight");
    layout.bottom = layout.safe_bottom = layout.edge;
    layout.font_size = layout.min_size = Number(*style, "fontSize"); layout.line_height = Number(*style, "lineHeight");
    layout.padding = Number(*style, "padding"); layout.radius = Number(*style, "radius");
    layout.rise = Number(*style, "rise"); layout.fade_us = Integer(*style, "fadeUs");
    layout.smooth_mass = Number(*style, "mass"); layout.smooth_stiffness = Number(*style, "stiffness"); layout.smooth_damping = Number(*style, "damping");
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

#include "recording_hud.h"
#include "win32_window.h"
#include "screen_sources.h"
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <functional>
#include <vector>
#include <cmath>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Channel = flutter::MethodChannel<Value>;
const Value* Field(const Map& args, const char* key) {
  const auto found = args.find(Value(key)); return found == args.end() ? nullptr : &found->second;
}
int Number(const Map& args, const char* key) {
  const auto* value = Field(args, key); return value && std::holds_alternative<int32_t>(*value) ? std::get<int32_t>(*value) : 0;
}
int64_t Session(const Map& args) {
  const auto* value = Field(args, "sessionId");
  if (!value) return -1;
  if (const auto id = std::get_if<int64_t>(value)) return *id;
  if (const auto id = std::get_if<int32_t>(value)) return *id;
  return -1;
}
bool Excluded(HWND hwnd) {
  DWORD affinity = 0; return hwnd && GetWindowDisplayAffinity(hwnd, &affinity) && affinity == WDA_EXCLUDEFROMCAPTURE;
}
bool Exclude(HWND hwnd) {
  using VersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
  const auto version = reinterpret_cast<VersionFn>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  OSVERSIONINFOW info{}; info.dwOSVersionInfoSize = sizeof(info);
  if (!version || version(&info) != 0 || info.dwMajorVersion < 10 ||
      (info.dwMajorVersion == 10 && info.dwBuildNumber < 19041)) return false;
  return SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE) && Excluded(hwnd);
}

class HudWindow : public Win32Window {
 public:
  HudWindow(flutter::DartProject project, RECT source, RECT work, int width, int height,
            int countdown, int inset, int poll, int radius, std::function<void(const std::string&)> command)
      : project_(std::move(project)), source_(source), work_(work), width_(width), height_(height),
        countdown_(countdown), inset_(inset), poll_(poll), radius_(radius), command_(std::move(command)) {}
  ~HudWindow() override { Destroy(); }
  void Update(const Map& state) {
    state_ = state;
    const auto* phase = Field(state, "phase");
    const bool countdown = phase && std::holds_alternative<std::string>(*phase) &&
        (std::get<std::string>(*phase) == "countdown" || std::get<std::string>(*phase) == "preparing");
    if (countdown != in_countdown_) { in_countdown_ = countdown; Place(); }
    if (channel_) channel_->InvokeMethod("update", std::make_unique<Value>(state));
  }
  bool Ready() { return Excluded(GetHandle()) && IsWindowVisible(GetHandle()) && !hit_regions_.empty(); }
 protected:
  bool OnCreate() override {
    SetWindowLongPtr(GetHandle(), GWL_STYLE, WS_POPUP);
    SetWindowLongPtr(GetHandle(), GWL_EXSTYLE, WS_EX_TOOLWINDOW | WS_EX_LAYERED);
    if (!SetLayeredWindowAttributes(GetHandle(), 0, 255, LWA_ALPHA) || !Exclude(GetHandle())) return false;
    Place();
    project_.set_dart_entrypoint("recordingHudMain"); project_.set_dart_entrypoint_arguments({});
    const auto frame = GetClientArea();
    controller_ = std::make_unique<flutter::FlutterViewController>(frame.right - frame.left, frame.bottom - frame.top, project_);
    if (!controller_->engine() || !controller_->view()) return false;
    channel_ = std::make_unique<Channel>(controller_->engine()->messenger(), "spawnalpha/recording_hud_view", &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "ready") { result->Success(Value(state_)); }
      else if (call.method_name() == "command") {
        const auto* args = call.arguments();
        if (args && std::holds_alternative<std::string>(*args)) command_(std::get<std::string>(*args));
        result->Success();
      } else if (call.method_name() == "hitRegions") {
        const auto* args = call.arguments();
        hit_regions_.clear();
        if (args && std::holds_alternative<flutter::EncodableList>(*args)) {
          const auto& regions = std::get<flutter::EncodableList>(*args);
          if (regions.size() <= 8) for (const auto& value : regions) {
            const auto* rect = std::get_if<flutter::EncodableList>(&value);
            if (!rect || rect->size() != 4) continue;
            double points[4]{}; bool valid = true;
            for (size_t i = 0; i < 4; ++i) {
              const auto* number = std::get_if<double>(&(*rect)[i]);
              if (!number || !std::isfinite(*number) || *number < 0 || *number > 4096) { valid = false; break; }
              points[i] = *number;
            }
            const double scale = GetDpiForWindow(GetHandle()) / 96.0;
            if (valid && points[2] > points[0] && points[3] > points[1]) hit_regions_.push_back({
              static_cast<LONG>(points[0] * scale), static_cast<LONG>(points[1] * scale),
              static_cast<LONG>(points[2] * scale), static_cast<LONG>(points[3] * scale)});
          }
        }
        result->Success();
      } else if (call.method_name() == "drag") {
        result->Success();
        POINT cursor{}; GetCursorPos(&cursor); ReleaseCapture();
        PostMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, MAKELPARAM(cursor.x, cursor.y));
      } else { result->NotImplemented(); }
    });
    SetChildContent(controller_->view()->GetNativeWindow());
    controller_->engine()->SetNextFrameCallback([this] {
      if (Excluded(GetHandle())) SetWindowPos(GetHandle(), HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    });
    controller_->ForceRedraw();
    SetTimer(GetHandle(), 1, static_cast<UINT>(poll_), nullptr);
    return true;
  }
  void OnDestroy() override { KillTimer(GetHandle(), 1); if (channel_) channel_->SetMethodCallHandler(nullptr); channel_.reset(); controller_.reset(); }
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) noexcept override {
    if (message == WM_CLOSE) { command_("stop"); return 0; }
    if (message == WM_TIMER && wp == 1) {
      POINT cursor{}; GetCursorPos(&cursor); ScreenToClient(hwnd, &cursor);
      bool interactive = false;
      for (const auto& region : hit_regions_) if (PtInRect(&region, cursor)) { interactive = true; break; }
      const auto style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
      const auto next = interactive ? style & ~WS_EX_TRANSPARENT : style | WS_EX_TRANSPARENT;
      if (next != style) SetWindowLongPtr(hwnd, GWL_EXSTYLE, next);
      return 0;
    }
    if (controller_) { const auto result = controller_->HandleTopLevelWindowProc(hwnd, message, wp, lp); if (result) return *result; }
    return Win32Window::MessageHandler(hwnd, message, wp, lp);
  }
 private:
  void Place() {
    const HMONITOR monitor = MonitorFromRect(&source_, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{sizeof(info)}; GetMonitorInfo(monitor, &info); work_ = info.rcWork;
    const UINT dpi = GetDpiForWindow(GetHandle());
    const double scale = dpi / 96.0;
    const int width = static_cast<int>((in_countdown_ ? countdown_ : width_) * scale);
    const int height = static_cast<int>((in_countdown_ ? countdown_ : height_) * scale);
    const int inset = static_cast<int>(inset_ * scale);
    const int x = in_countdown_ ? source_.left + (source_.right - source_.left - width) / 2 : work_.left + (work_.right - work_.left - width) / 2;
    const int y = in_countdown_ ? source_.top + (source_.bottom - source_.top - height) / 2 : work_.bottom - height - inset;
    SetWindowPos(GetHandle(), HWND_TOPMOST, std::clamp<LONG>(x, work_.left, std::max(work_.left, work_.right - width)),
        std::clamp<LONG>(y, work_.top, std::max(work_.top, work_.bottom - height)), width, height,
        SWP_NOACTIVATE | SWP_FRAMECHANGED);
    const int radius = static_cast<int>(radius_ * scale) * 2;
    const HRGN rounded = CreateRoundRectRgn(0, 0, width + 1, height + 1, radius, radius);
    if (!SetWindowRgn(GetHandle(), rounded, TRUE)) DeleteObject(rounded);
  }
  flutter::DartProject project_;
  RECT source_, work_;
  int width_, height_, countdown_, inset_, poll_, radius_;
  std::vector<RECT> hit_regions_;
  bool in_countdown_ = true;
  Map state_{{Value("phase"), Value("preparing")}};
  std::function<void(const std::string&)> command_;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<Channel> channel_;
};
}  // namespace

struct RecordingHud::Impl {
  Impl(HWND owner, flutter::DartProject project, flutter::BinaryMessenger* messenger)
      : owner(owner), project(std::move(project)), channel(messenger, "spawnalpha/recording_hud", &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid", "Missing recording controls."); return; }
      if (call.method_name() == "open") {
        if (window) { result->Error("busy", "Recording controls are already open."); return; }
        const auto* source = Field(*args, "sourceId");
        const int width = Number(*args, "width"), height = Number(*args, "height"), countdown = Number(*args, "countdownSize"), inset = Number(*args, "inset");
        const int poll = Number(*args, "hitPollMs"), radius = Number(*args, "radius");
        HMONITOR monitor = nullptr; HWND source_window = nullptr;
        if (!source || !std::holds_alternative<std::string>(*source) || width <= 0 || height <= 0 || countdown <= 0 ||
            width > 4096 || height > 4096 || countdown > 4096 || inset < 0 || poll < 1 || poll > 1000 || radius < 0 || radius > 256 ||
            !ResolveScreenSource(std::get<std::string>(*source), &monitor, &source_window)) {
          result->Error("source", "Choose an available source first."); return;
        }
        RECT source_rect{}, work{};
        if (source_window) { GetWindowRect(source_window, &source_rect); monitor = MonitorFromWindow(source_window, MONITOR_DEFAULTTONEAREST); }
        MONITORINFO info{sizeof(info)}; GetMonitorInfo(monitor, &info); work = info.rcWork;
        if (!source_window) source_rect = info.rcMonitor;
        if (!GetWindowDisplayAffinity(this->owner, &previous_affinity)) {
          result->Error("excluded", "Could not hide recording controls from capture."); return;
        }
        protected_owner = true;
        if (!Exclude(this->owner)) {
          Restore(); result->Error("excluded", "Could not hide recording controls from capture."); return;
        }
        ++session;
        window = std::make_unique<HudWindow>(this->project, source_rect, work, width, height, countdown, inset, poll, radius,
            [this](const std::string& command) {
              if (command != "stop" && command != "pause" && command != "prompter" && command != "lock") return;
              channel.InvokeMethod("command", std::make_unique<Value>(Map{{Value("sessionId"), Value(session)}, {Value("command"), Value(command)}}));
            });
        if (!window->Create(L"SpawnAlpha Recording", Win32Window::Point(source_rect.left, source_rect.top), Win32Window::Size(countdown, countdown))) {
          window.reset(); Restore(); result->Error("excluded", "Could not show hidden recording controls."); return;
        }
        result->Success(Value(session));
      } else if (call.method_name() == "status") {
        const bool active = window && Session(*args) == session;
        result->Success(Value(Map{{Value("ready"), Value(active && window->Ready())},
          {Value("excluded"), Value(active && Excluded(this->owner) && Excluded(window->GetHandle()))},
          {Value("ownerExcluded"), Value(Excluded(this->owner))}}));
      } else if (call.method_name() == "update") {
        const auto* state = Field(*args, "state");
        if (window && Session(*args) == session && state && std::holds_alternative<Map>(*state)) window->Update(std::get<Map>(*state));
        result->Success();
      } else if (call.method_name() == "close") {
        if (Session(*args) == session) { window.reset(); Restore(); }
        result->Success();
      } else { result->NotImplemented(); }
    });
  }
  ~Impl() { channel.SetMethodCallHandler(nullptr); window.reset(); Restore(); }
  void Restore() { if (protected_owner) SetWindowDisplayAffinity(owner, previous_affinity); protected_owner = false; }
  HWND owner;
  flutter::DartProject project;
  Channel channel;
  DWORD previous_affinity = WDA_NONE;
  bool protected_owner = false;
  int64_t session = 0;
  std::unique_ptr<HudWindow> window;
};
RecordingHud::RecordingHud(HWND owner, const flutter::DartProject& project, flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(owner, project, messenger)) {}
RecordingHud::~RecordingHud() = default;

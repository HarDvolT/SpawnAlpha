#include "floating_prompter.h"
#include "win32_window.h"
#include "companion_motion.h"
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <functional>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Channel = flutter::MethodChannel<Value>;

const Value* Field(const Map& map, const char* key) {
  const auto found = map.find(Value(key));
  return found == map.end() ? nullptr : &found->second;
}
int Number(const Map& map, const char* key) {
  const auto* value = Field(map, key);
  return value && std::holds_alternative<int32_t>(*value) ? std::get<int32_t>(*value) : 0;
}
double Real(const Map& map, const char* key) {
  const auto* value = Field(map, key);
  return value && std::holds_alternative<double>(*value) ? std::get<double>(*value) : 0;
}
bool Flag(const Map& map, const char* key) {
  const auto* value = Field(map, key);
  return value && std::holds_alternative<bool>(*value) && std::get<bool>(*value);
}
int64_t Session(const Value* args) {
  if (!args || !std::holds_alternative<Map>(*args)) return -1;
  const auto* value = Field(std::get<Map>(*args), "sessionId");
  if (!value) return -1;
  if (std::holds_alternative<int64_t>(*value)) return std::get<int64_t>(*value);
  if (std::holds_alternative<int32_t>(*value)) return std::get<int32_t>(*value);
  return -1;
}
bool ExclusionSupported() {
  using VersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
  const auto ntdll = GetModuleHandleW(L"ntdll.dll");
  const auto version = reinterpret_cast<VersionFn>(GetProcAddress(ntdll, "RtlGetVersion"));
  OSVERSIONINFOW info{};
  info.dwOSVersionInfoSize = sizeof(info);
  return version && version(&info) == 0 &&
      (info.dwMajorVersion > 10 || (info.dwMajorVersion == 10 && info.dwBuildNumber >= 19041));
}

class PrompterWindow : public Win32Window {
 public:
  PrompterWindow(HWND owner, flutter::DartProject project, std::string presentation,
                 int width, int height, int min_width, int min_height, int snap, double min_opacity,
                 std::function<void()> companion_ask)
      : owner_(owner), project_(std::move(project)), presentation_(std::move(presentation)),
        width_(width), height_(height), min_width_(min_width), min_height_(min_height), snap_(snap), min_opacity_(min_opacity),
        companion_ask_(std::move(companion_ask)) {}
  ~PrompterWindow() override { Destroy(); }

  bool Excluded() {
    DWORD affinity = 0;
    return GetHandle() && GetWindowDisplayAffinity(GetHandle(), &affinity) && affinity == WDA_EXCLUDEFROMCAPTURE;
  }
  bool Visible() { return GetHandle() && IsWindowVisible(GetHandle()); }
  Map PlacementStatus() {
    return {{Value("companion"), Value(companion_)}, {Value("following"), Value(follow_)},
      {Value("sampling"), Value(motion_ != nullptr)},
      {Value("clickThrough"), Value(GetHandle() && (GetWindowLongPtr(GetHandle(), GWL_EXSTYLE) & WS_EX_TRANSPARENT) != 0)}};
  }
  bool Show(bool visible) {
    if (!visible) { Hide(); return true; }
    if (!Excluded()) return false;
    wanted_ = true;
    RegisterShortcuts();
    if (!SetLocked(locked_)) return false;
    SetWindowPos(GetHandle(), HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    StartCompanion();
    return Visible();
  }
  void Update(const Value& state) {
    if (channel_) channel_->InvokeMethod("recordingState", std::make_unique<Value>(state));
  }
  void Lock() {
    if (channel_) channel_->InvokeMethod("command", std::make_unique<Value>("lock"));
  }
  void Hide() {
    wanted_ = false;
    KillTimer(GetHandle(), 7);
    motion_.reset();
    SetLocked(false);
    UnregisterShortcuts();
    if (GetHandle()) ShowWindow(GetHandle(), SW_HIDE);
    if (channel_) channel_->InvokeMethod("hidden", nullptr);
  }
  bool Placement(const Map& args) {
    const CompanionConfig config{Real(args, "width"), Real(args, "height"),
      Real(args, "gap"), Real(args, "jitter"), Real(args, "restSeconds"),
      Real(args, "mass"), Real(args, "stiffness"), Real(args, "damping")};
    const int poll = Number(args, "pollMs");
    const double values[] = {config.width, config.height, config.gap, config.jitter,
      config.rest_seconds, config.mass, config.stiffness, config.damping};
    for (const double value : values) if (!std::isfinite(value) || value <= 0 || value > 4096) return false;
    if (poll < 10 || poll > 1000 || config.rest_seconds > 60) return false;
    const double opacity = Real(args, "opacity");
    const int radius = Number(args, "radius");
    if (!std::isfinite(opacity) || opacity < min_opacity_ || opacity > 1 || radius <= 0 || radius > 256) return false;
    KillTimer(GetHandle(), 7); motion_.reset();
    companion_ = Flag(args, "enabled");
    // Preserve WS_VISIBLE when removing the resize frame from a live reader.
    auto style = GetWindowLongPtr(GetHandle(), GWL_STYLE) & ~WS_THICKFRAME;
    if (!companion_) style |= WS_THICKFRAME;
    SetWindowLongPtr(GetHandle(), GWL_STYLE, style);
    BOOL animations = TRUE;
    SystemParametersInfo(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0);
    follow_ = companion_ && Flag(args, "follow") && !Flag(args, "reduceMotion") && animations;
    config_ = config; poll_ = poll;
    companion_opacity_ = static_cast<BYTE>(opacity * 255); companion_radius_ = radius;
    Dock();
    if (!SetLocked(locked_)) return false;
    if (channel_) channel_->InvokeMethod("placement", std::make_unique<Value>(Map{
      {Value("companion"), Value(companion_)}, {Value("following"), Value(follow_)},
      {Value("camera"), Value(Flag(args, "camera"))}}));
    StartCompanion();
    return true;
  }

 protected:
  bool OnCreate() override {
    if (!ExclusionSupported()) return false;
    auto hwnd = GetHandle();
    SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_THICKFRAME);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, WS_EX_TOOLWINDOW | WS_EX_LAYERED);
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
    if (!SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE) || !Excluded()) return false;
    Dock();
    project_.set_dart_entrypoint("floatingPrompterMain");
    project_.set_dart_entrypoint_arguments({});
    const auto frame = GetClientArea();
    controller_ = std::make_unique<flutter::FlutterViewController>(
        frame.right - frame.left, frame.bottom - frame.top, project_);
    if (!controller_->engine() || !controller_->view()) return false;
    channel_ = std::make_unique<Channel>(controller_->engine()->messenger(),
        "spawnalpha/floating_view", &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      const auto& method = call.method_name();
      if (method == "ready") {
        result->Success(Value(Map{{Value("presentation"), Value(presentation_)}}));
      } else if (method == "close") {
        Hide();
        result->Success();
      } else if (method == "companionAsk") {
        if (companion_ && Visible() && Excluded()) companion_ask_();
        result->Success();
      } else if (method == "dock") {
        Dock();
        result->Success();
      } else if (method == "drag" || method == "resize") {
        result->Success();
        if (!locked_) {
          ReleaseCapture();
          POINT cursor{};
          GetCursorPos(&cursor);
          PostMessage(GetHandle(), WM_NCLBUTTONDOWN, method == "drag" ? HTCAPTION : HTBOTTOMRIGHT,
                      MAKELPARAM(cursor.x, cursor.y));
        }
      } else if (method == "lock") {
        const auto* args = call.arguments();
        if (!args || !std::holds_alternative<bool>(*args)) { result->Error("invalid", "Invalid lock"); return; }
        const auto lock = std::get<bool>(*args);
        if (lock && !shortcuts_) { result->Error("shortcut", "Shortcut unavailable"); return; }
        if (!SetLocked(lock)) { result->Error("lock", "Lock unavailable"); return; }
        result->Success(Value(locked_));
      } else if (method == "opacity") {
        const auto* args = call.arguments();
        if (args && std::holds_alternative<double>(*args)) {
          opacity_ = static_cast<BYTE>(std::clamp(std::get<double>(*args), min_opacity_, 1.0) * 255);
          SetLayeredWindowAttributes(GetHandle(), 0, opacity_, LWA_ALPHA);
        }
        result->Success();
      } else { result->NotImplemented(); }
    });
    SetChildContent(controller_->view()->GetNativeWindow());
    controller_->engine()->SetNextFrameCallback([this]() {
      if (wanted_ && Excluded()) {
        RegisterShortcuts();
        SetWindowPos(GetHandle(), HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      }
    });
    controller_->ForceRedraw();
    return true;
  }
  void OnDestroy() override {
    KillTimer(GetHandle(), 7);
    motion_.reset();
    UnregisterShortcuts();
    if (channel_) channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
    controller_.reset();
  }
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept override {
    if (message == WM_CLOSE) { Hide(); return 0; }
    if (message == WM_TIMER && wparam == 7) { MoveCompanion(); return 0; }
    if (message == WM_HOTKEY && channel_) {
      static const char* commands[] = {"play", "faster", "slower", "previous", "next", "lock"};
      if (wparam >= 1 && wparam <= 6) channel_->InvokeMethod("command", std::make_unique<Value>(commands[wparam - 1]));
      return 0;
    }
    if (message == WM_GETMINMAXINFO) {
      auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      const double scale = GetDpiForWindow(hwnd) / 96.0;
      limits->ptMinTrackSize = {static_cast<LONG>((companion_ ? config_.width : min_width_) * scale),
        static_cast<LONG>((companion_ ? config_.height : min_height_) * scale)};
      return 0;
    }
    if (message == WM_EXITSIZEMOVE) Snap();
    if (controller_) {
      const auto result = controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
      if (result) return *result;
    }
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }
 private:
  void RegisterShortcuts() {
    UnregisterShortcuts();
    const UINT keys[] = {VK_SPACE, VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, 'L'};
    for (int i = 0; i < 6; ++i) {
      if (!RegisterHotKey(GetHandle(), i + 1, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, keys[i])) {
        UnregisterShortcuts();
        return;
      }
    }
    shortcuts_ = true;
  }
  void UnregisterShortcuts() {
    if (GetHandle()) for (int i = 1; i <= 6; ++i) UnregisterHotKey(GetHandle(), i);
    shortcuts_ = false;
  }
  bool SetLocked(bool locked) {
    if (!GetHandle()) return false;
    const auto previous = GetWindowLongPtr(GetHandle(), GWL_EXSTYLE);
    auto style = previous;
    if (locked || (follow_ && wanted_)) style |= WS_EX_TRANSPARENT;
    else style &= ~WS_EX_TRANSPARENT;
    SetLastError(0);
    if (!SetWindowLongPtr(GetHandle(), GWL_EXSTYLE, style) && GetLastError() != 0) return false;
    if (!SetLayeredWindowAttributes(GetHandle(), 0, companion_ ? companion_opacity_ : opacity_, LWA_ALPHA)) {
      SetWindowLongPtr(GetHandle(), GWL_EXSTYLE, previous);
      return false;
    }
    locked_ = locked;
    return true;
  }
  void Dock() {
    MONITORINFO monitor{sizeof(monitor)};
    GetMonitorInfo(MonitorFromWindow(owner_, MONITOR_DEFAULTTONEAREST), &monitor);
    const double scale = GetDpiForWindow(owner_) / 96.0;
    const int width = std::min(static_cast<int>((companion_ ? config_.width : width_) * scale),
      static_cast<int>(monitor.rcWork.right - monitor.rcWork.left));
    const int height = std::min(static_cast<int>((companion_ ? config_.height : height_) * scale),
      static_cast<int>(monitor.rcWork.bottom - monitor.rcWork.top));
    SetWindowPos(GetHandle(), HWND_TOPMOST,
        monitor.rcWork.left + (monitor.rcWork.right - monitor.rcWork.left - width) / 2,
        monitor.rcWork.top, width, height, SWP_NOACTIVATE | SWP_FRAMECHANGED);
    RoundCard(width, height, scale);
  }
  void RoundCard(int width, int height, double scale) {
    if (!companion_) { SetWindowRgn(GetHandle(), nullptr, TRUE); return; }
    const int diameter = static_cast<int>(companion_radius_ * scale * 2);
    const HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter, diameter);
    if (region && !SetWindowRgn(GetHandle(), region, TRUE)) DeleteObject(region);
  }
  void StartCompanion() {
    if (!follow_ || !wanted_ || !Visible() || !Excluded()) return;
    const double scale = GetDpiForWindow(GetHandle()) / 96.0;
    auto physical = config_;
    physical.width *= scale; physical.height *= scale;
    physical.gap *= scale; physical.jitter *= scale;
    motion_ = std::make_unique<CompanionMotion>(physical);
    RECT bounds{}; GetWindowRect(GetHandle(), &bounds);
    motion_->Reset(bounds.left, bounds.top);
    last_tick_ = std::chrono::steady_clock::now();
    motion_scale_ = scale;
    SetTimer(GetHandle(), 7, static_cast<UINT>(poll_), nullptr);
  }
  void MoveCompanion() {
    if (!Visible() || !Excluded()) { Hide(); return; }
    POINT pointer{};
    if (!GetCursorPos(&pointer)) return; // No input-desktop access: hold safely.
    MONITORINFO monitor{sizeof(monitor)};
    if (!GetMonitorInfo(MonitorFromPoint(pointer, MONITOR_DEFAULTTONEAREST), &monitor)) return;
    const double scale = GetDpiForWindow(GetHandle()) / 96.0;
    if (!motion_ || scale != motion_scale_) StartCompanion();
    if (!motion_) return;
    const auto now = std::chrono::steady_clock::now();
    const double time = std::chrono::duration<double>(now.time_since_epoch()).count();
    const double elapsed = std::chrono::duration<double>(now - last_tick_).count();
    last_tick_ = now;
    const auto work = monitor.rcWork;
    const auto rect = motion_->Step(pointer.x, pointer.y,
      {static_cast<double>(work.left), static_cast<double>(work.top),
       static_cast<double>(work.right - work.left), static_cast<double>(work.bottom - work.top)}, time, elapsed);
    RECT previous{}; GetWindowRect(GetHandle(), &previous);
    SetWindowPos(GetHandle(), HWND_TOPMOST, static_cast<int>(std::round(rect.x)),
      static_cast<int>(std::round(rect.y)), static_cast<int>(rect.width), static_cast<int>(rect.height), SWP_NOACTIVATE);
    if (previous.right - previous.left != static_cast<int>(rect.width) || previous.bottom - previous.top != static_cast<int>(rect.height)) {
      RoundCard(static_cast<int>(rect.width), static_cast<int>(rect.height), scale);
    }
  }
  void Snap() {
    RECT rect{};
    GetWindowRect(GetHandle(), &rect);
    MONITORINFO monitor{sizeof(monitor)};
    GetMonitorInfo(MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTONEAREST), &monitor);
    const auto area = monitor.rcWork;
    const int distance = static_cast<int>(snap_ * GetDpiForWindow(GetHandle()) / 96.0);
    const int width = rect.right - rect.left, height = rect.bottom - rect.top;
    int x = rect.left, y = rect.top;
    if (std::abs(x - area.left) <= distance) x = area.left;
    if (std::abs(rect.right - area.right) <= distance) x = area.right - width;
    if (std::abs(y - area.top) <= distance) {
      y = area.top;
      const int centre = area.left + (area.right - area.left - width) / 2;
      if (std::abs(x - centre) <= distance) x = centre;
    }
    if (std::abs(rect.bottom - area.bottom) <= distance) y = area.bottom - height;
    SetWindowPos(GetHandle(), nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }
  HWND owner_;
  flutter::DartProject project_;
  std::string presentation_;
  int width_, height_, min_width_, min_height_, snap_;
  double min_opacity_;
  bool wanted_ = true, locked_ = false, shortcuts_ = false;
  bool companion_ = false, follow_ = false;
  CompanionConfig config_{};
  int poll_ = 16;
  int companion_radius_ = 0;
  BYTE companion_opacity_ = 255;
  double motion_scale_ = 1;
  std::chrono::steady_clock::time_point last_tick_;
  std::unique_ptr<CompanionMotion> motion_;
  std::function<void()> companion_ask_;
  BYTE opacity_ = 255;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<Channel> channel_;
};
}  // namespace

struct FloatingPrompterHost::Impl {
  Impl(HWND owner, const flutter::DartProject& project, flutter::BinaryMessenger* messenger)
      : owner(owner), project(project), channel(messenger, "spawnalpha/floating_prompter", &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "open") {
        const auto* args = call.arguments();
        if (!args || !std::holds_alternative<Map>(*args)) { result->Error("invalid", "Missing presentation"); return; }
        const auto& map = std::get<Map>(*args);
        const auto* presentation = Field(map, "presentation");
        const int width = Number(map, "width"), height = Number(map, "height");
        const int min_width = Number(map, "minWidth"), min_height = Number(map, "minHeight"), snap = Number(map, "snap");
        const auto* opacity = Field(map, "minOpacity");
        const double min_opacity = opacity && std::holds_alternative<double>(*opacity) ? std::get<double>(*opacity) : 0;
        if (!presentation || !std::holds_alternative<std::string>(*presentation) || width < min_width ||
            height < min_height || min_width <= 0 || min_height <= 0 || width > 4096 || height > 4096 || snap <= 0 ||
            min_opacity <= 0 || min_opacity > 1) {
          result->Error("invalid", "Invalid presentation"); return;
        }
        window.reset();
        window = std::make_unique<PrompterWindow>(this->owner, this->project, std::get<std::string>(*presentation), width, height, min_width, min_height, snap, min_opacity,
          [this] { channel.InvokeMethod("command", std::make_unique<Value>(Map{
            {Value("sessionId"), Value(session)}, {Value("command"), Value("companionAsk")}})); });
        if (!window->Create(L"SpawnAlpha Prompter", Win32Window::Point(0, 0), Win32Window::Size(width, height))) {
          window.reset(); result->Error("excluded", "Hidden prompter unavailable"); return;
        }
        ++session;
        result->Success(Value(session));
      } else if (call.method_name() == "close") {
        if (Session(call.arguments()) == session) window.reset();
        result->Success();
      } else if (call.method_name() == "status") {
        const bool active = Session(call.arguments()) == session && window;
        Map state = active ? window->PlacementStatus() : Map{};
        state[Value("excluded")] = Value(active && window->Excluded());
        state[Value("visible")] = Value(active && window->Visible());
        result->Success(Value(state));
      } else if (call.method_name() == "update" || call.method_name() == "show" || call.method_name() == "lock" || call.method_name() == "placement") {
        if (Session(call.arguments()) != session || !window || !window->Excluded()) {
          result->Error("session", "Prompter unavailable"); return;
        }
        const auto& args = std::get<Map>(*call.arguments());
        if (call.method_name() == "placement") {
          if (!window->Placement(args)) { result->Error("invalid", "Companion placement unavailable"); return; }
        } else if (call.method_name() == "update") {
          const auto* state = Field(args, "state");
          if (!state || !std::holds_alternative<Map>(*state)) { result->Error("invalid", "Invalid reader state"); return; }
          window->Update(*state);
        } else if (call.method_name() == "show") {
          const auto* visible = Field(args, "visible");
          if (!visible || !std::holds_alternative<bool>(*visible) || !window->Show(std::get<bool>(*visible))) {
            result->Error("excluded", "Hidden reader unavailable"); return;
          }
        } else { window->Lock(); }
        result->Success();
      } else { result->NotImplemented(); }
    });
  }
  ~Impl() { channel.SetMethodCallHandler(nullptr); window.reset(); }
  HWND owner;
  flutter::DartProject project;
  Channel channel;
  int64_t session = 0;
  std::unique_ptr<PrompterWindow> window;
};
FloatingPrompterHost::FloatingPrompterHost(HWND owner, const flutter::DartProject& project, flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(owner, project, messenger)) {}
FloatingPrompterHost::~FloatingPrompterHost() = default;

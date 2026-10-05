#include "floating_prompter.h"
#include "win32_window.h"
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <algorithm>
#include <cmath>

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
                 int width, int height, int min_width, int min_height, int snap, double min_opacity)
      : owner_(owner), project_(std::move(project)), presentation_(std::move(presentation)),
        width_(width), height_(height), min_width_(min_width), min_height_(min_height), snap_(snap), min_opacity_(min_opacity) {}
  ~PrompterWindow() override { Destroy(); }

  bool Excluded() {
    DWORD affinity = 0;
    return GetHandle() && GetWindowDisplayAffinity(GetHandle(), &affinity) && affinity == WDA_EXCLUDEFROMCAPTURE;
  }
  bool Visible() { return GetHandle() && IsWindowVisible(GetHandle()); }
  void Hide() {
    wanted_ = false;
    SetLocked(false);
    UnregisterShortcuts();
    if (GetHandle()) ShowWindow(GetHandle(), SW_HIDE);
    if (channel_) channel_->InvokeMethod("hidden", nullptr);
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
        SetWindowPos(GetHandle(), HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
      }
    });
    controller_->ForceRedraw();
    return true;
  }
  void OnDestroy() override {
    UnregisterShortcuts();
    if (channel_) channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
    controller_.reset();
  }
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept override {
    if (message == WM_CLOSE) { Hide(); return 0; }
    if (message == WM_HOTKEY && channel_) {
      static const char* commands[] = {"play", "faster", "slower", "previous", "next", "lock"};
      if (wparam >= 1 && wparam <= 6) channel_->InvokeMethod("command", std::make_unique<Value>(commands[wparam - 1]));
      return 0;
    }
    if (message == WM_GETMINMAXINFO) {
      auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      const double scale = GetDpiForWindow(hwnd) / 96.0;
      limits->ptMinTrackSize = {static_cast<LONG>(min_width_ * scale), static_cast<LONG>(min_height_ * scale)};
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
    if (locked) style |= WS_EX_TRANSPARENT;
    else style &= ~WS_EX_TRANSPARENT;
    SetLastError(0);
    if (!SetWindowLongPtr(GetHandle(), GWL_EXSTYLE, style) && GetLastError() != 0) return false;
    if (!SetLayeredWindowAttributes(GetHandle(), 0, opacity_, LWA_ALPHA)) {
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
    const int width = static_cast<int>(width_ * scale);
    const int height = static_cast<int>(height_ * scale);
    SetWindowPos(GetHandle(), HWND_TOPMOST,
        monitor.rcWork.left + (monitor.rcWork.right - monitor.rcWork.left - width) / 2,
        monitor.rcWork.top, width, height, SWP_NOACTIVATE | SWP_FRAMECHANGED);
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
        window = std::make_unique<PrompterWindow>(this->owner, this->project, std::get<std::string>(*presentation), width, height, min_width, min_height, snap, min_opacity);
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
        result->Success(Value(Map{{Value("excluded"), Value(active && window->Excluded())},
          {Value("visible"), Value(active && window->Visible())}}));
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

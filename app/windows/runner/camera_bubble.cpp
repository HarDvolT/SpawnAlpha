#include "camera_bubble.h"
#include "camera_capture.h"
#include "screen_sources.h"
#include "win32_window.h"
#include <flutter/flutter_view_controller.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <mutex>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Channel = flutter::MethodChannel<Value>;
using Provider = std::function<std::shared_ptr<const CameraFrame>()>;
const Value* Field(const Map& map, const char* key) {
  const auto found = map.find(Value(key)); return found == map.end() ? nullptr : &found->second;
}
int Number(const Map& map, const char* key) {
  const auto* value = Field(map, key); return value && std::holds_alternative<int32_t>(*value) ? std::get<int32_t>(*value) : 0;
}
int64_t Session(const Map& map) {
  const auto* value = Field(map, "sessionId");
  if (value) {
    if (const auto* id = std::get_if<int64_t>(value)) return *id;
    if (const auto* id = std::get_if<int32_t>(value)) return *id;
  }
  return -1;
}
bool Excluded(HWND hwnd) {
  DWORD value = 0; return hwnd && GetWindowDisplayAffinity(hwnd, &value) && value == WDA_EXCLUDEFROMCAPTURE;
}
bool Exclude(HWND hwnd) {
  using VersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
  const auto version = reinterpret_cast<VersionFn>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  OSVERSIONINFOW info{}; info.dwOSVersionInfoSize = sizeof(info);
  return version && version(&info) == 0 && info.dwMajorVersion >= 10 &&
      (info.dwMajorVersion > 10 || info.dwBuildNumber >= 19041) &&
      SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE) && Excluded(hwnd);
}
struct Pixels { UINT width = 0, height = 0; std::vector<uint8_t> rgba; };
struct Lease { std::shared_ptr<const Pixels> pixels; FlutterDesktopPixelBuffer buffer{}; };
struct PixelState {
  std::mutex mutex;
  std::shared_ptr<const Pixels> latest;
  const FlutterDesktopPixelBuffer* Copy() {
    std::lock_guard<std::mutex> lock(mutex);
    if (!latest) return nullptr;
    auto* lease = new Lease{latest};
    lease->buffer.buffer = latest->rgba.data();
    lease->buffer.width = latest->width; lease->buffer.height = latest->height;
    lease->buffer.release_context = lease;
    lease->buffer.release_callback = [](void* context) { delete static_cast<Lease*>(context); };
    return &lease->buffer;
  }
};
class BubbleWindow : public Win32Window {
 public:
  BubbleWindow(flutter::DartProject project, RECT work, int diameter, int reader_width,
               int inset, int poll, std::string name, Provider frame)
      : project_(std::move(project)), work_(work), diameter_(diameter), reader_width_(reader_width),
        inset_(inset), poll_(poll), name_(std::move(name)), frame_(std::move(frame)) {}
  ~BubbleWindow() override { Destroy(); }
  bool Ready() { return child_ready_ && shown_ && Excluded(GetHandle()); }
 protected:
  bool OnCreate() override {
    // Win32Window::Create first invokes Destroy/OnDestroy, even on a new object.
    // Recreate the frame holder here rather than relying on the constructor.
    pixels_ = std::make_shared<PixelState>();
    SetWindowLongPtr(GetHandle(), GWL_STYLE, WS_POPUP);
    SetWindowLongPtr(GetHandle(), GWL_EXSTYLE, WS_EX_TOOLWINDOW | WS_EX_LAYERED);
    if (!SetLayeredWindowAttributes(GetHandle(), 0, 255, LWA_ALPHA) || !Exclude(GetHandle())) return false;
    const double scale = GetDpiForWindow(GetHandle()) / 96.0;
    const int size = static_cast<int>(diameter_ * scale), inset = static_cast<int>(inset_ * scale);
    const int x = (work_.left + work_.right) / 2 + static_cast<int>(reader_width_ * scale / 2) + inset;
    SetWindowPos(GetHandle(), HWND_TOPMOST,
      std::clamp<LONG>(x, work_.left, std::max(work_.left, work_.right - size)), work_.top + inset,
      size, size, SWP_FRAMECHANGED | SWP_NOACTIVATE);
    Round();
    project_.set_dart_entrypoint("cameraBubbleMain"); project_.set_dart_entrypoint_arguments({});
    const auto area = GetClientArea();
    controller_ = std::make_unique<flutter::FlutterViewController>(area.right, area.bottom, project_);
    if (!controller_->engine() || !controller_->view()) return false;
    auto* registrar = flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(
      controller_->engine()->GetRegistrarForPlugin("CameraBubble"));
    textures_ = registrar->texture_registrar();
    const std::weak_ptr<PixelState> weak = pixels_;
    texture_ = std::make_shared<flutter::TextureVariant>(flutter::PixelBufferTexture(
      [weak](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
        if (const auto state = weak.lock()) return state->Copy(); return nullptr;
      }));
    texture_id_ = textures_->RegisterTexture(texture_.get());
    if (texture_id_ < 0) return false;
    channel_ = std::make_unique<Channel>(controller_->engine()->messenger(), "spawnalpha/camera_bubble_view", &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "ready") { child_ready_ = true; result->Success(Value(State())); }
      else if (call.method_name() == "hide") { ShowWindow(GetHandle(), SW_HIDE); result->Success(); }
      else if (call.method_name() == "drag") {
        result->Success(); POINT cursor{}; GetCursorPos(&cursor); ReleaseCapture();
        PostMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, MAKELPARAM(cursor.x, cursor.y));
      } else { result->NotImplemented(); }
    });
    SetChildContent(controller_->view()->GetNativeWindow());
    controller_->engine()->SetNextFrameCallback([this] {
      if (Excluded(GetHandle())) {
        SetWindowPos(GetHandle(), HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        shown_ = IsWindowVisible(GetHandle()) != FALSE;
      }
    });
    controller_->ForceRedraw(); SetTimer(GetHandle(), 1, static_cast<UINT>(poll_), nullptr);
    return true;
  }
  void OnDestroy() override {
    KillTimer(GetHandle(), 1);
    if (channel_) channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
    if (textures_ && texture_id_ >= 0) {
      auto retain = std::move(texture_);
      textures_->UnregisterTexture(texture_id_, [retain]() {});
      texture_id_ = -1;
    }
    pixels_.reset(); controller_.reset(); textures_ = nullptr;
  }
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) noexcept override {
    if (message == WM_CLOSE) { ShowWindow(hwnd, SW_HIDE); return 0; }
    if (message == WM_SIZE) Round();
    if (message == WM_TIMER && wp == 1) {
      if (!Excluded(hwnd)) { ShowWindow(hwnd, SW_HIDE); return 0; }
      try { Tick(); } catch (...) { ShowWindow(hwnd, SW_HIDE); child_ready_ = false; }
      return 0;
    }
    if (controller_) { const auto result = controller_->HandleTopLevelWindowProc(hwnd, message, wp, lp); if (result) return *result; }
    return Win32Window::MessageHandler(hwnd, message, wp, lp);
  }
 private:
  void Round() {
    const auto area = GetClientArea(); if (area.right <= 0 || area.bottom <= 0) return;
    const auto region = CreateEllipticRgn(0, 0, area.right + 1, area.bottom + 1);
    if (!SetWindowRgn(GetHandle(), region, TRUE)) DeleteObject(region);
  }
  Map State() const {
    return {{Value("textureId"), Value(texture_id_)}, {Value("width"), Value(static_cast<int32_t>(width_))},
      {Value("height"), Value(static_cast<int32_t>(height_))}, {Value("name"), Value(name_)},
      {Value("live"), Value(width_ > 0 && height_ > 0)}};
  }
  void Tick() {
    const auto frame = frame_();
    if (!frame || frame->arrived_100ns == last_frame_) return;
    const size_t count = frame->bgra.size();
    if (count != static_cast<size_t>(frame->width) * frame->height * 4) return;
    auto pixels = std::make_shared<Pixels>(); pixels->width = frame->width; pixels->height = frame->height;
    pixels->rgba.resize(count);
    const auto* source = frame->bgra.data(); auto* destination = pixels->rgba.data();
    for (size_t i = 0; i < count; i += 4) {
      destination[i] = source[i + 2]; destination[i + 1] = source[i + 1];
      destination[i + 2] = source[i]; destination[i + 3] = 255;
    }
    { std::lock_guard<std::mutex> lock(pixels_->mutex); pixels_->latest = std::move(pixels); }
    last_frame_ = frame->arrived_100ns;
    if (width_ != frame->width || height_ != frame->height) {
      width_ = frame->width; height_ = frame->height;
      if (channel_) channel_->InvokeMethod("update", std::make_unique<Value>(State()));
    }
    textures_->MarkTextureFrameAvailable(texture_id_);
  }
  flutter::DartProject project_;
  RECT work_;
  int diameter_, reader_width_, inset_, poll_;
  std::string name_;
  Provider frame_;
  bool child_ready_ = false, shown_ = false;
  UINT width_ = 0, height_ = 0;
  int64_t texture_id_ = -1;
  LONGLONG last_frame_ = 0;
  std::shared_ptr<PixelState> pixels_ = std::make_shared<PixelState>();
  std::shared_ptr<flutter::TextureVariant> texture_;
  flutter::TextureRegistrar* textures_ = nullptr;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<Channel> channel_;
};
}  // namespace
struct CameraBubbleHost::Impl {
  Impl(flutter::DartProject project, flutter::BinaryMessenger* messenger, Provider frame)
      : project(std::move(project)), frame(std::move(frame)), channel(messenger, "spawnalpha/camera_bubble", &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid", "Choose the camera preview first."); return; }
      if (call.method_name() == "open") {
        if (window) { result->Error("busy", "Camera preview is already open."); return; }
        const auto* source = Field(*args, "sourceId"), *name = Field(*args, "name");
        const int diameter = Number(*args, "diameter"), reader = Number(*args, "readerWidth"), inset = Number(*args, "inset"), poll = Number(*args, "pollMs");
        HMONITOR monitor = nullptr; HWND source_window = nullptr;
        if (!source || !name || !std::holds_alternative<std::string>(*source) || !std::holds_alternative<std::string>(*name) ||
            diameter < 96 || diameter > 1024 || reader < 0 || reader > 4096 || inset < 0 || inset > 256 || poll < 1 || poll > 1000 ||
            !ResolveScreenSource(std::get<std::string>(*source), &monitor, &source_window)) {
          result->Error("invalid", "Choose an available screen and camera."); return;
        }
        if (source_window) monitor = MonitorFromWindow(source_window, MONITOR_DEFAULTTONEAREST);
        MONITORINFO info{sizeof(info)}; if (!GetMonitorInfo(monitor, &info)) { result->Error("source", "The source is unavailable."); return; }
        auto next = std::make_unique<BubbleWindow>(this->project, info.rcWork, diameter, reader, inset, poll, std::get<std::string>(*name), this->frame);
        if (!next->Create(L"SpawnAlpha camera preview", Win32Window::Point(info.rcWork.left, info.rcWork.top), Win32Window::Size(diameter, diameter))) {
          result->Error("excluded", "Could not hide camera preview from recording."); return;
        }
        window = std::move(next); result->Success(Value(++generation));
      } else if (call.method_name() == "status") {
        const bool matches = window && Session(*args) == generation;
        result->Success(Value(Map{{Value("excluded"), Value(matches && Excluded(window->GetHandle()))},
          {Value("ready"), Value(matches && window->Ready())}}));
      } else if (call.method_name() == "close") {
        if (window && Session(*args) == generation) window.reset(); result->Success();
      } else { result->NotImplemented(); }
    });
  }
  ~Impl() { channel.SetMethodCallHandler(nullptr); window.reset(); }
  flutter::DartProject project;
  Provider frame;
  Channel channel;
  int64_t generation = 0;
  std::unique_ptr<BubbleWindow> window;
};
CameraBubbleHost::CameraBubbleHost(const flutter::DartProject& project, flutter::BinaryMessenger* messenger, Provider frame)
    : impl_(std::make_unique<Impl>(project, messenger, std::move(frame))) {}
CameraBubbleHost::~CameraBubbleHost() = default;

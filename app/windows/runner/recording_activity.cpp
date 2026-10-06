#include "recording_activity.h"
#include <dwmapi.h>
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>

namespace {
int64_t Now() {
  LARGE_INTEGER now{}, hz{}; QueryPerformanceCounter(&now); QueryPerformanceFrequency(&hz);
  return now.QuadPart / hz.QuadPart * 10000000 + now.QuadPart % hz.QuadPart * 10000000 / hz.QuadPart;
}
bool Bounds(HWND window, RECT& rect) {
  return IsWindow(window) && !IsIconic(window) &&
      (SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS, &rect, sizeof(rect))) || GetWindowRect(window, &rect));
}
bool Own(HWND window) {
  DWORD process = 0; GetWindowThreadProcessId(window, &process);
  return !window || process == GetCurrentProcessId();
}
bool Down(int key) { return (GetAsyncKeyState(key) & 0x8000) != 0; }
bool Modifier(UINT key) {
  return key == VK_CONTROL || key == VK_LCONTROL || key == VK_RCONTROL || key == VK_SHIFT ||
      key == VK_LSHIFT || key == VK_RSHIFT || key == VK_MENU || key == VK_LMENU || key == VK_RMENU || key == VK_LWIN || key == VK_RWIN;
}
}  // namespace

struct RecordingActivity::Impl {
  HMONITOR monitor = nullptr;
  HWND source = nullptr;
  std::thread thread;
  std::atomic<bool> stop{false}, failed{false};
  std::mutex mutex;
  std::condition_variable ready;
  bool started = false;
  HRESULT result = E_FAIL;
  std::vector<ActivityEvent> events;
  RECT previous_focus{};
  bool had_focus = false;
  HWND sink = nullptr;
  bool registered = false;
  HANDLE timer = nullptr;
  void Cleanup() {
    if (registered) {
      RAWINPUTDEVICE devices[] = {{1, 2, RIDEV_REMOVE, nullptr}, {1, 6, RIDEV_REMOVE, nullptr}};
      if (!RegisterRawInputDevices(devices, 2, sizeof(RAWINPUTDEVICE))) failed = true;
      registered = false;
    }
    if (sink) { DestroyWindow(sink); sink = nullptr; }
    if (timer) { CloseHandle(timer); timer = nullptr; }
  }

  bool Scope(RECT& rect) const {
    if (source) return Bounds(source, rect);
    MONITORINFO info{}; info.cbSize = sizeof(info);
    if (!GetMonitorInfo(monitor, &info)) return false;
    rect = info.rcMonitor; return true;
  }
  bool Focus(const RECT& rect, RECT& clipped) const {
    const auto window = GetForegroundWindow();
    if (Own(window) || (source && GetAncestor(window, GA_ROOT) != GetAncestor(source, GA_ROOT))) return false;
    RECT foreground{};
    return Bounds(window, foreground) && IntersectRect(&clipped, &rect, &foreground);
  }
  bool Point(const RECT& rect, POINT point) const {
    const auto window = WindowFromPoint(point);
    return PtInRect(&rect, point) && !Own(window) &&
        (!source || GetAncestor(window, GA_ROOT) == GetAncestor(source, GA_ROOT));
  }
  ActivityEvent Event(ActivityKind kind, const RECT& rect) const {
    ActivityEvent event; event.kind = kind; event.qpc_100ns = Now();
    event.width = rect.right - rect.left; event.height = rect.bottom - rect.top;
    return event;
  }
  void Queue(const ActivityEvent& event) {
    std::lock_guard<std::mutex> lock(mutex);
    if (events.size() >= 8192) { failed = true; return; }
    events.push_back(event);
  }
  void Sample() {
    RECT rect{};
    if (!Scope(rect)) { failed = true; return; }
    CURSORINFO cursor{}; cursor.cbSize = sizeof(cursor);
    if (!GetCursorInfo(&cursor)) { failed = true; return; }
    auto event = Event(ActivityKind::cursor, rect);
    event.visible = (cursor.flags & CURSOR_SHOWING) && Point(rect, cursor.ptScreenPos);
    // Hidden/out-of-source positions are never retained.
    if (event.visible) { event.x = cursor.ptScreenPos.x - rect.left; event.y = cursor.ptScreenPos.y - rect.top; }
    event.detail = cursor.hCursor == LoadCursor(nullptr, IDC_ARROW) ? ActivityDetail::arrow :
        cursor.hCursor == LoadCursor(nullptr, IDC_IBEAM) ? ActivityDetail::text :
        cursor.hCursor == LoadCursor(nullptr, IDC_HAND) ? ActivityDetail::hand : ActivityDetail::other;
    if (!event.visible) event.detail = ActivityDetail::other;
    Queue(event);
    RECT focus{};
    const bool focused = Focus(rect, focus);
    if (focused != had_focus || (focused && !EqualRect(&focus, &previous_focus))) {
      auto change = Event(ActivityKind::focus, rect);
      if (focused) {
        change.rect_x = focus.left - rect.left; change.rect_y = focus.top - rect.top;
        change.rect_width = focus.right - focus.left; change.rect_height = focus.bottom - focus.top;
      }
      Queue(change); previous_focus = focus; had_focus = focused;
    }
  }
  void Input(HRAWINPUT handle) {
    RAWINPUT input{}; UINT bytes = sizeof(input);
    const auto size = GetRawInputData(handle, RID_INPUT, &input, &bytes, sizeof(RAWINPUTHEADER));
    if (size == static_cast<UINT>(-1)) { failed = true; return; }
    RECT rect{}; if (!Scope(rect)) return;
    if (input.header.dwType == RIM_TYPEKEYBOARD) {
      const auto& key = input.data.keyboard;
      RECT focus{};
      if ((key.Flags & RI_KEY_BREAK) || key.VKey == 255 || Modifier(key.VKey) || !Focus(rect, focus)) return;
      auto event = Event(ActivityKind::key, rect);
      event.detail = SanitizeShortcut(key.VKey, Down(VK_CONTROL), Down(VK_MENU), Down(VK_SHIFT), Down(VK_LWIN) || Down(VK_RWIN));
      if (event.detail != ActivityDetail::none) event.kind = ActivityKind::shortcut;
      Queue(event);
    } else if (input.header.dwType == RIM_TYPEMOUSE) {
      POINT point{};
      if (!GetCursorPos(&point) || !Point(rect, point)) return;
      const auto buttons = input.data.mouse.usButtonFlags;
      for (const auto& button : {std::pair<UINT, ActivityDetail>{RI_MOUSE_LEFT_BUTTON_DOWN, ActivityDetail::left},
          {RI_MOUSE_RIGHT_BUTTON_DOWN, ActivityDetail::right}, {RI_MOUSE_MIDDLE_BUTTON_DOWN, ActivityDetail::middle},
          {RI_MOUSE_BUTTON_4_DOWN, ActivityDetail::extra}, {RI_MOUSE_BUTTON_5_DOWN, ActivityDetail::extra}}) {
        if (!(buttons & button.first)) continue;
        auto event = Event(ActivityKind::click, rect);
        event.x = point.x - rect.left; event.y = point.y - rect.top; event.detail = button.second; Queue(event);
      }
    }
    // RAWINPUT, including its key/device fields, dies here. No WM_CHAR,
    // ToUnicode, clipboard access or text translation is used anywhere.
  }
  static LRESULT CALLBACK Proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    if (message == WM_NCCREATE) SetWindowLongPtr(window, GWLP_USERDATA,
        reinterpret_cast<LONG_PTR>(reinterpret_cast<CREATESTRUCT*>(lp)->lpCreateParams));
    const auto self = reinterpret_cast<Impl*>(GetWindowLongPtr(window, GWLP_USERDATA));
    if (self && message == WM_INPUT) {
      try { self->Input(reinterpret_cast<HRAWINPUT>(lp)); }
      catch (...) { self->failed = true; }
    }
    return DefWindowProc(window, message, wp, lp);
  }
  void Run() {
    const auto instance = GetModuleHandle(nullptr);
    WNDCLASS type{}; type.hInstance = instance; type.lpfnWndProc = Proc; type.lpszClassName = L"SpawnAlphaActivitySink";
    RegisterClass(&type);  // May already exist after an earlier take.
    const auto window = sink = CreateWindowEx(0, type.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, this);
    HRESULT start_result = window ? S_OK : HRESULT_FROM_WIN32(GetLastError());
    // Respect any keyboard/mouse receiver already owned by another app plugin.
    UINT count = 0;
    if (SUCCEEDED(start_result) && GetRegisteredRawInputDevices(nullptr, &count, sizeof(RAWINPUTDEVICE)) != static_cast<UINT>(-1)) {
      std::vector<RAWINPUTDEVICE> existing(count);
      if (count && GetRegisteredRawInputDevices(existing.data(), &count, sizeof(RAWINPUTDEVICE)) == static_cast<UINT>(-1)) start_result = E_FAIL;
      for (const auto& device : existing) {
        if (device.usUsagePage == 1 && (device.usUsage == 2 || device.usUsage == 6)) start_result = HRESULT_FROM_WIN32(ERROR_BUSY);
      }
    } else if (SUCCEEDED(start_result)) start_result = E_FAIL;
    RAWINPUTDEVICE devices[] = {{1, 2, RIDEV_INPUTSINK, window}, {1, 6, RIDEV_INPUTSINK, window}};
    if (SUCCEEDED(start_result)) {
      registered = RegisterRawInputDevices(devices, 2, sizeof(RAWINPUTDEVICE)) != FALSE;
      if (!registered) start_result = HRESULT_FROM_WIN32(GetLastError());
    }
    if (SUCCEEDED(start_result)) {
      timer = CreateWaitableTimerEx(nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
      if (!timer) start_result = HRESULT_FROM_WIN32(GetLastError());
    }
    { std::lock_guard<std::mutex> lock(mutex); result = start_result; started = true; }
    ready.notify_one();
    auto next = Now();
    while (SUCCEEDED(start_result) && !stop && !failed) {
      // Bound each batch so heavy mouse input cannot starve cursor sampling.
      MSG message{};
      for (int batch = 0; batch < 256 && PeekMessage(&message, nullptr, 0, 0, PM_REMOVE); ++batch) {
        TranslateMessage(&message); DispatchMessage(&message);
      }
      const auto now = Now();
      if (now >= next) { Sample(); next = now + 10000000 / 60; }
      LARGE_INTEGER due{}; due.QuadPart = -std::max<int64_t>(1, next - Now());
      if (!SetWaitableTimer(timer, &due, 0, nullptr, nullptr, FALSE)) { failed = true; break; }
      if (MsgWaitForMultipleObjectsEx(1, &timer, INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE) == WAIT_FAILED) { failed = true; break; }
    }
    Cleanup();
  }
};
RecordingActivity::RecordingActivity() : impl_(std::make_unique<Impl>()) {}
RecordingActivity::~RecordingActivity() { Stop(); }
HRESULT RecordingActivity::Start(HMONITOR monitor, HWND window) {
  if (impl_->thread.joinable() || ((!monitor) == (!window))) return E_INVALIDARG;
  impl_->monitor = monitor; impl_->source = window;
  try { impl_->thread = std::thread([this] {
    try { impl_->Run(); }
    catch (...) {
      impl_->failed = true; impl_->Cleanup();
      { std::lock_guard<std::mutex> lock(impl_->mutex); impl_->result = E_FAIL; impl_->started = true; }
      impl_->ready.notify_one();
    }
  }); }
  catch (...) { return E_FAIL; }
  std::unique_lock<std::mutex> lock(impl_->mutex);
  impl_->ready.wait(lock, [this] { return impl_->started; });
  return impl_->result;
}
void RecordingActivity::Stop() { impl_->stop = true; if (impl_->thread.joinable()) impl_->thread.join(); }
std::vector<ActivityEvent> RecordingActivity::Drain() {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  std::vector<ActivityEvent> events; events.swap(impl_->events); return events;
}
bool RecordingActivity::Failed() const { return impl_->failed; }

#include "screen_sources.h"

#include <windows.h>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <charconv>
#include <string>
#include <vector>

namespace {
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::string Utf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int length = static_cast<int>(text.size());
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), length,
                                      nullptr, 0, nullptr, nullptr);
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), length, output.data(), size,
                      nullptr, nullptr);
  return output;
}

struct Display {
  MONITORINFOEXW info{};
};

BOOL CALLBACK CollectDisplay(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto* displays = reinterpret_cast<std::vector<Display>*>(data);
  Display display;
  display.info.cbSize = sizeof(display.info);
  if (GetMonitorInfoW(monitor, &display.info) &&
      display.info.rcMonitor.right > display.info.rcMonitor.left &&
      display.info.rcMonitor.bottom > display.info.rcMonitor.top) {
    displays->push_back(display);
  }
  return TRUE;
}

BOOL CALLBACK CollectWindow(HWND window, LPARAM data) {
  // Do not offer the app's own Studio, prompter, HUD or helper windows.
  DWORD process = 0;
  GetWindowThreadProcessId(window, &process);
  if (process == GetCurrentProcessId() || !IsWindowVisible(window) ||
      IsIconic(window) || window == GetShellWindow()) return TRUE;
  const LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  if ((style & WS_EX_TOOLWINDOW) ||
      (GetWindow(window, GW_OWNER) && !(style & WS_EX_APPWINDOW))) return TRUE;
  DWORD cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked,
                                      sizeof(cloaked))) && cloaked) return TRUE;
  DWORD affinity = WDA_NONE;
  if (GetWindowDisplayAffinity(window, &affinity) && affinity != WDA_NONE)
    return TRUE;
  RECT bounds{};
  if (!GetWindowRect(window, &bounds) || bounds.right <= bounds.left ||
      bounds.bottom <= bounds.top) return TRUE;
  const int length = GetWindowTextLengthW(window);
  if (length <= 0) return TRUE;
  std::vector<wchar_t> title(static_cast<size_t>(length) + 1);
  const int copied = GetWindowTextW(window, title.data(), length + 1);
  if (copied <= 0 || !IsWindow(window)) return TRUE;
  const std::string id = "window:" + std::to_string(process) + ":" +
      std::to_string(reinterpret_cast<uintptr_t>(window));
  auto* windows = reinterpret_cast<EncodableList*>(data);
  windows->emplace_back(EncodableMap{
      {EncodableValue("id"), EncodableValue(id)},
      {EncodableValue("kind"), EncodableValue("window")},
      {EncodableValue("name"), EncodableValue(Utf8(std::wstring(title.data(), copied)))},
      {EncodableValue("width"), EncodableValue(static_cast<int32_t>(bounds.right - bounds.left))},
      {EncodableValue("height"), EncodableValue(static_cast<int32_t>(bounds.bottom - bounds.top))},
  });
  return TRUE;
}

EncodableList ListSources() {
  std::vector<Display> displays;
  EnumDisplayMonitors(nullptr, nullptr, CollectDisplay,
                      reinterpret_cast<LPARAM>(&displays));
  std::sort(displays.begin(), displays.end(), [](const Display& a, const Display& b) {
    const bool a_primary = (a.info.dwFlags & MONITORINFOF_PRIMARY) != 0;
    const bool b_primary = (b.info.dwFlags & MONITORINFOF_PRIMARY) != 0;
    if (a_primary != b_primary) return a_primary;
    return std::wstring(a.info.szDevice) < std::wstring(b.info.szDevice);
  });
  EncodableList sources;
  int number = 0;
  for (const auto& display : displays) {
    const auto& info = display.info;
    sources.emplace_back(EncodableMap{
        {EncodableValue("id"), EncodableValue("display:" + Utf8(info.szDevice))},
        {EncodableValue("kind"), EncodableValue("display")},
        {EncodableValue("name"), EncodableValue("Display " + std::to_string(++number))},
        {EncodableValue("width"), EncodableValue(static_cast<int32_t>(info.rcMonitor.right - info.rcMonitor.left))},
        {EncodableValue("height"), EncodableValue(static_cast<int32_t>(info.rcMonitor.bottom - info.rcMonitor.top))},
        {EncodableValue("primary"), EncodableValue((info.dwFlags & MONITORINFOF_PRIMARY) != 0)},
    });
  }
  EnumWindows(CollectWindow, reinterpret_cast<LPARAM>(&sources));
  return sources;
}
}  // namespace

bool ResolveScreenSource(const std::string& id, HMONITOR* monitor, HWND* window) {
  *monitor = nullptr;
  *window = nullptr;
  const auto sources = ListSources();
  bool found = false;
  for (const auto& source : sources) {
    const auto& row = std::get<EncodableMap>(source);
    if (std::get<std::string>(row.at(EncodableValue("id"))) == id) {
      found = true;
      break;
    }
  }
  if (!found) return false;
  if (id.rfind("window:", 0) == 0) {
    const auto start = id.find_last_of(':') + 1;
    uintptr_t handle = 0;
    const auto parsed = std::from_chars(id.data() + start, id.data() + id.size(), handle);
    if (parsed.ec != std::errc() || parsed.ptr != id.data() + id.size()) return false;
    *window = reinterpret_cast<HWND>(handle);
    return IsWindow(*window) && !IsIconic(*window);
  }
  struct Match { const std::string& id; HMONITOR value = nullptr; } match{id};
  EnumDisplayMonitors(nullptr, nullptr,
    [](HMONITOR candidate, HDC, LPRECT, LPARAM data) -> BOOL {
      auto* match = reinterpret_cast<Match*>(data);
      MONITORINFOEXW info{};
      info.cbSize = sizeof(info);
      if (GetMonitorInfoW(candidate, &info) && "display:" + Utf8(info.szDevice) == match->id)
        match->value = candidate;
      return TRUE;
    }, reinterpret_cast<LPARAM>(&match));
  *monitor = match.value;
  return *monitor != nullptr;
}

std::unique_ptr<flutter::MethodChannel<EncodableValue>>
RegisterScreenSources(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "spawnalpha/screen_sources",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const flutter::MethodCall<EncodableValue>& call,
                                 std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (call.method_name() == "list") {
      // Read metadata only. No capture, input hook, disk write or logging.
      result->Success(EncodableValue(ListSources()));
    } else {
      result->NotImplemented();
    }
  });
  return channel;
}

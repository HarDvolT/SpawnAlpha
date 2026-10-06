#include "../recording_activity.h"
#include <iostream>
#include <stdexcept>
// An own-process source must exclude ALL owner input. Cursor visibility and
// shape are also redacted here. Discard records in memory; never write a file.
int main() {
  HWND window = CreateWindowEx(0, L"STATIC", L"Generated activity scope", WS_POPUP, 0, 0, 640, 360,
      nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
  try {
    if (!window) throw std::runtime_error("Window unavailable");
    for (int run = 0; run < 3; ++run) {
      RecordingActivity activity;
      if (FAILED(activity.Start(nullptr, window))) throw std::runtime_error("Receiver unavailable");
      Sleep(220); activity.Stop();
      const auto events = activity.Drain();
      if (activity.Failed() || events.size() < 10 || events.size() > 20) throw std::runtime_error("Sampling failed");
      for (const auto& event : events) {
        if (event.kind != ActivityKind::cursor || event.visible || event.x || event.y ||
            event.detail != ActivityDetail::other) throw std::runtime_error("Own input retained");
      }
    }
    DestroyWindow(window);
    std::cout << "Activity receiver lifecycle and own-window input exclusion passed. No activity file written.\n";
    return 0;
  } catch (...) {
    if (window) DestroyWindow(window);
    std::cerr << "Activity receiver check failed.\n"; return 1;
  }
}

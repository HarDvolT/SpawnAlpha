#include "../recording_activity.h"
#include "../recording_clock.h"
#include <iostream>
#include <stdexcept>
void Require(bool value) { if (!value) throw std::runtime_error("Activity invariant failed"); }
int main() {
  try {
    for (UINT key = 0; key < 65536; ++key) {
      Require(SanitizeShortcut(key, false, false, false, false) == ActivityDetail::none);
      Require(SanitizeShortcut(key, true, true, false, false) == ActivityDetail::none);
      Require(SanitizeShortcut(key, true, false, false, true) == ActivityDetail::none);
      const bool allowed = key < 128 && std::string("ACSVXYZ").find(static_cast<char>(key)) != std::string::npos;
      Require((SanitizeShortcut(key, true, false, false, false) != ActivityDetail::none) == allowed);
    }
    Require(SanitizeShortcut('S', true, false, false, false) == ActivityDetail::ctrlS);
    Require(SanitizeShortcut('Z', true, false, true, false) == ActivityDetail::ctrlShiftZ);
    const UINT protected_keys[] = {VK_SPACE, VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, 'L'};
    for (const UINT key : protected_keys) {
      Require(IsPrompterShortcut(key, true, false, true, false));
      Require(!IsPrompterShortcut(key, true, true, true, false));
      Require(!IsPrompterShortcut(key, true, false, false, false));
    }
    Require(!IsPrompterShortcut('S', true, false, true, false));
    const RECT monitor{-1920, -1080, 0, 0};
    Require(ActivityKeyboardWithin(monitor, monitor));
    Require(ActivityKeyboardWithin(monitor, {-1000, -500, -100, -100}));
    Require(!ActivityKeyboardWithin(monitor, {-10, -500, 100, -100}));
    Require(!ActivityKeyboardWithin(monitor, {0, 0, 640, 360}));
    Require(!ActivityKeyboardWithin(monitor, {-100, -100, -100, -100}));
    ActivityEvent key; key.width = 640; key.height = 360;
    Require(ActivityJson(key, 12340) == "{\"type\":\"key\",\"timeUs\":1234,\"width\":640,\"height\":360,\"count\":1}");
    key.kind = ActivityKind::shortcut; key.detail = ActivityDetail::ctrlS;
    Require(ActivityJson(key, 0).find("Ctrl+S") != std::string::npos);
    RecordingClock clock(100); int64_t time = -1;
    Require(!clock.Event(99, time)); Require(clock.Event(100, time) && time == 0);
    clock.Pause(true, 200); Require(!clock.Event(200, time)); Require(!clock.Event(250, time));
    clock.Pause(false, 300); Require(!clock.Event(299, time)); Require(clock.Event(300, time) && time == 100);
    clock.Pause(true, 400); clock.Pause(false, 500);
    Require(clock.Event(550, time) && time == 250);
    std::cout << "Activity privacy and common pause clock checks passed.\n"; return 0;
  } catch (...) { std::cerr << "Activity check failed.\n"; return 1; }
}

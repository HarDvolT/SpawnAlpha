#include "../recording_probe.h"
#include <iostream>
int wmain(int count, wchar_t** args) {
  if (count != 2 && count != 3) return 2;
  const std::atomic<bool> cancelled{false};
  const auto info = ProbeRecording(args[1], cancelled);
  if (!info.readable || info.width != 640 || info.height != 360 ||
      info.duration_100ns < 20000000 || info.duration_100ns > 41000000 ||
      info.has_audio != (count == 3)) {
    std::cerr << "Recording probe check failed.\n"; return 1;
  }
  const std::atomic<bool> stop{true};
  if (ProbeRecording(args[1], stop).readable || ProbeRecording(L"missing-fixture.mp4", cancelled).readable) return 1;
  std::cout << "Recording probe check passed: decoded frame, dimensions, duration, audio, cancelled/missing file.\n";
  return 0;
}

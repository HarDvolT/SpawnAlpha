#ifndef RUNNER_RECORDING_PROBE_H_
#define RUNNER_RECORDING_PROBE_H_
#include <windows.h>
#include <atomic>
#include <string>

struct RecordingInfo {
  bool readable = false, has_audio = false;
  UINT width = 0, height = 0;
  LONGLONG duration_100ns = 0;
};
// Header/duration probe plus one decoded video frame. Run off the UI thread.
// Incomplete fragmented MP4 duration falls back to compressed-sample timestamps.
RecordingInfo ProbeRecording(const std::wstring& path, const std::atomic<bool>& cancelled);
#endif

#ifndef RUNNER_SCREEN_RECORDING_CORE_H_
#define RUNNER_SCREEN_RECORDING_CORE_H_
#include <windows.h>
#include <cstdint>
#include <memory>
#include <string>

enum class ScreenRecordingState { starting, recording, paused, saving, finished, failed };
enum class ScreenRecordingReason { none, cancelled, source, microphone, encoder, camera };
struct ScreenRecordingStatus {
  ScreenRecordingState state = ScreenRecordingState::starting;
  ScreenRecordingReason reason = ScreenRecordingReason::none;
  UINT width = 0, height = 0;
  UINT64 frames = 0, audio_frames = 0;
  UINT64 camera_frames = 0;
  LONGLONG duration_100ns = 0;
  double peak_db = -100, rms_db = -100, loudest_rms_db = -100;
};

// Selected-source GPU capture + chosen microphone + fragmented MP4 on one MTA
// worker. No preview CPU readback. Start is nonblocking; poll Status until ready.
class ScreenRecordingCore {
 public:
  ScreenRecordingCore();
  ~ScreenRecordingCore();
  HRESULT Start(HMONITOR monitor, HWND window, const std::wstring& path,
                const std::wstring& microphone_id, bool record_audio,
                const std::wstring& camera_id = {}, const std::wstring& camera_path = {});
  void RequestStop();
  void SetPaused(bool paused);
  ScreenRecordingStatus Status() const;
 private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};
#endif

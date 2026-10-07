#ifndef RUNNER_SCREEN_RECORDING_CORE_H_
#define RUNNER_SCREEN_RECORDING_CORE_H_
#include <windows.h>
#include <cstdint>
#include <memory>
#include <string>
struct CameraFrame;

enum class ScreenRecordingState { starting, recording, paused, saving, finished, failed };
enum class ScreenRecordingReason { none, cancelled, source, microphone, encoder, camera, systemAudio, activity };
struct ScreenRecordingStatus {
  ScreenRecordingState state = ScreenRecordingState::starting;
  ScreenRecordingReason reason = ScreenRecordingReason::none;
  UINT width = 0, height = 0;
  UINT64 frames = 0, audio_frames = 0;
  UINT64 camera_frames = 0;
  UINT64 system_audio_frames = 0;
  UINT64 activity_events = 0;
  UINT64 cursor_free_frames = 0;
  bool cursor_free_complete = false;
  LONGLONG duration_100ns = 0;
  double peak_db = -100, rms_db = -100, loudest_rms_db = -100;
  double loudest_system_rms_db = -100;
};

// Selected-source GPU capture + chosen microphone + fragmented MP4 on one MTA
// worker. No preview CPU readback. Start is nonblocking; poll Status until ready.
class ScreenRecordingCore {
 public:
  ScreenRecordingCore();
  ~ScreenRecordingCore();
  HRESULT Start(HMONITOR monitor, HWND window, const std::wstring& path,
                const std::wstring& microphone_id, bool record_audio,
                const std::wstring& camera_id = {}, const std::wstring& camera_path = {},
                bool record_system_audio = false, const std::wstring& activity_path = {},
                const std::wstring& cursor_free_path = {});
  void RequestStop();
  void SetPaused(bool paused);
  ScreenRecordingStatus Status() const;
  std::shared_ptr<const CameraFrame> LatestCamera() const;
 private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};
#endif

#ifndef RUNNER_RECORDING_ACTIVITY_H_
#define RUNNER_RECORDING_ACTIVITY_H_
#include <windows.h>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// Only this enum crosses the raw-input boundary. Never retain a key code,
// character, scan code, window handle, title or input-device identity.
enum class ActivityDetail { none, arrow, text, hand, other, left, right, middle,
  extra, ctrlA, ctrlC, ctrlS, ctrlV, ctrlX, ctrlY, ctrlZ,
  ctrlShiftA, ctrlShiftC, ctrlShiftS, ctrlShiftV, ctrlShiftX, ctrlShiftY, ctrlShiftZ };
enum class ActivityKind { cursor, click, key, shortcut, focus };
struct ActivityEvent {
  ActivityKind kind = ActivityKind::key;
  ActivityDetail detail = ActivityDetail::none;
  int64_t qpc_100ns = 0;
  int x = 0, y = 0, width = 0, height = 0;
  int rect_x = 0, rect_y = 0, rect_width = 0, rect_height = 0;
  bool visible = true;
};
ActivityDetail SanitizeShortcut(UINT key, bool ctrl, bool alt, bool shift, bool win);
std::string ActivityJson(const ActivityEvent& event, int64_t time_100ns);

// Active only during an opted-in Screen/Both take. A dedicated message thread
// queues sanitized, bounded records; the encoding worker owns disk writes.
class RecordingActivity {
 public:
  RecordingActivity();
  ~RecordingActivity();
  HRESULT Start(HMONITOR monitor, HWND window);
  void Stop();
  std::vector<ActivityEvent> Drain();
  bool Failed() const;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

class ActivityWriter {
 public:
  ~ActivityWriter();
  HRESULT Start(const std::wstring& path);
  HRESULT Write(const ActivityEvent& event, int64_t time_100ns);
  HRESULT Flush();
  HRESULT Finish(int64_t duration_100ns, bool complete);
  uint64_t Count() const { return count_; }
 private:
  HRESULT Line(const std::string& line);
  HANDLE file_ = INVALID_HANDLE_VALUE;
  uint64_t count_ = 0;
};
#endif

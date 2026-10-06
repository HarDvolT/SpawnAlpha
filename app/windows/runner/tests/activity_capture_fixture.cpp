#include "../recording_activity.h"
#include <atomic>
#include <mutex>
#include <thread>
// Generated coordinates/key timings only. No cursor, keyboard, window or device
// API may be called in this fixture; the normal binary cannot enable it.
struct RecordingActivity::Impl {
  std::atomic<bool> stop{false};
  std::thread thread;
  std::mutex mutex;
  std::vector<ActivityEvent> events;
};
RecordingActivity::RecordingActivity() : impl_(std::make_unique<Impl>()) {}
RecordingActivity::~RecordingActivity() { Stop(); }
HRESULT RecordingActivity::Start(HMONITOR, HWND) {
  impl_->thread = std::thread([this] {
    LARGE_INTEGER hz{}; QueryPerformanceFrequency(&hz);
    int index = 0;
    while (!impl_->stop) {
      LARGE_INTEGER now{}; QueryPerformanceCounter(&now);
      ActivityEvent event;
      event.qpc_100ns = now.QuadPart / hz.QuadPart * 10000000 + now.QuadPart % hz.QuadPart * 10000000 / hz.QuadPart;
      event.width = 672; event.height = 399; event.x = 120; event.y = 100;
      event.kind = index % 30 == 0 ? ActivityKind::click : index % 30 == 10 ? ActivityKind::key : index % 30 == 20 ? ActivityKind::shortcut : ActivityKind::cursor;
      event.detail = event.kind == ActivityKind::cursor ? ActivityDetail::arrow : event.kind == ActivityKind::click ? ActivityDetail::left : event.kind == ActivityKind::shortcut ? ActivityDetail::ctrlS : ActivityDetail::none;
      { std::lock_guard<std::mutex> lock(impl_->mutex); impl_->events.push_back(event); }
      ++index; Sleep(16);
    }
  });
  return S_OK;
}
void RecordingActivity::Stop() { impl_->stop = true; if (impl_->thread.joinable()) impl_->thread.join(); }
std::vector<ActivityEvent> RecordingActivity::Drain() {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  std::vector<ActivityEvent> events; events.swap(impl_->events); return events;
}
bool RecordingActivity::Failed() const { return false; }

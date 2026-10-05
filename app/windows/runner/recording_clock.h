#ifndef RUNNER_RECORDING_CLOCK_H_
#define RUNNER_RECORDING_CLOCK_H_
#include <algorithm>
#include <cstdint>
#include <vector>

struct AudioSlice {
  size_t offset = 0, count = 0;
  int64_t time_100ns = 0;
};

// One QPC timeline with paused intervals removed. Worker-thread only; independent
// of Windows capture/encoding. Audio slices keep packets crossing a pause exact.
class RecordingClock {
 public:
  explicit RecordingClock(int64_t origin) : origin_(origin) {}
  void Pause(bool paused, int64_t now) {
    if (paused == paused_) return;
    now = std::max(origin_, now);
    if (paused) pauses_.push_back({now, -1});
    else pauses_.back().end = now;
    paused_ = paused;
  }
  int64_t Time(int64_t qpc) const {
    int64_t time = std::max<int64_t>(0, qpc - origin_);
    for (const auto& pause : pauses_) {
      if (qpc <= pause.start) break;
      time -= std::max<int64_t>(0, std::min(qpc, pause.end < 0 ? qpc : pause.end) - pause.start);
    }
    return std::max<int64_t>(0, time);
  }
  std::vector<AudioSlice> Audio(int64_t qpc, size_t frames, uint32_t rate) const {
    std::vector<AudioSlice> slices;
    if (!rate || !frames) return slices;
    const int64_t end = qpc + static_cast<int64_t>(frames) * 10000000 / rate;
    int64_t cursor = std::max(qpc, origin_);
    auto offset = [qpc, rate, frames](int64_t time) {
      const int64_t delta = std::max<int64_t>(0, time - qpc);
      const int64_t count = (delta * rate + 9999999) / 10000000;
      return std::min(frames, static_cast<size_t>(count));
    };
    auto emit = [&](int64_t until) {
      const size_t begin = offset(cursor), finish = offset(until);
      if (finish > begin) {
        slices.push_back({begin, finish - begin, Time(qpc + static_cast<int64_t>(begin) * 10000000 / rate)});
      }
    };
    for (const auto& pause : pauses_) {
      if (pause.start >= end) break;
      if (pause.end >= 0 && pause.end <= cursor) continue;
      if (cursor < pause.start) emit(std::min(end, pause.start));
      cursor = std::max(cursor, pause.end < 0 ? end : pause.end);
      if (cursor >= end) return slices;
    }
    emit(end);
    return slices;
  }
 private:
  struct PauseSpan { int64_t start, end; };
  int64_t origin_;
  bool paused_ = false;
  std::vector<PauseSpan> pauses_;
};
#endif

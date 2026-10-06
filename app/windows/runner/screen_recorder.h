#ifndef RUNNER_SCREEN_RECORDER_H_
#define RUNNER_SCREEN_RECORDER_H_
#include <flutter/binary_messenger.h>
#include <memory>
struct CameraFrame;

class ScreenRecorder {
 public:
  explicit ScreenRecorder(flutter::BinaryMessenger* messenger);
  ~ScreenRecorder();
  // Main UI thread only. The returned snapshot owns pixels independently of capture.
  std::shared_ptr<const CameraFrame> LatestCamera() const;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

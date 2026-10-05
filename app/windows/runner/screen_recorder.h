#ifndef RUNNER_SCREEN_RECORDER_H_
#define RUNNER_SCREEN_RECORDER_H_
#include <flutter/binary_messenger.h>
#include <memory>

class ScreenRecorder {
 public:
  explicit ScreenRecorder(flutter::BinaryMessenger* messenger);
  ~ScreenRecorder();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

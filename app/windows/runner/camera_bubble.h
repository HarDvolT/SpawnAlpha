#ifndef RUNNER_CAMERA_BUBBLE_H_
#define RUNNER_CAMERA_BUBBLE_H_
#include <flutter/binary_messenger.h>
#include <flutter/dart_project.h>
#include <functional>
#include <memory>
struct CameraFrame;
class CameraBubbleHost {
 public:
  CameraBubbleHost(const flutter::DartProject& project, flutter::BinaryMessenger* messenger,
                   std::function<std::shared_ptr<const CameraFrame>()> frame);
  ~CameraBubbleHost();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

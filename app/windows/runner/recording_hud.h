#ifndef RUNNER_RECORDING_HUD_H_
#define RUNNER_RECORDING_HUD_H_
#include <flutter/binary_messenger.h>
#include <flutter/dart_project.h>
#include <windows.h>
#include <memory>
class RecordingHud {
 public:
  RecordingHud(HWND owner, const flutter::DartProject& project, flutter::BinaryMessenger* messenger);
  ~RecordingHud();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

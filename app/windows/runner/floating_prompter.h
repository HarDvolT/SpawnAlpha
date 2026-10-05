#ifndef RUNNER_FLOATING_PROMPTER_H_
#define RUNNER_FLOATING_PROMPTER_H_
#include <flutter/dart_project.h>
#include <flutter/binary_messenger.h>
#include <windows.h>
#include <memory>

class FloatingPrompterHost {
 public:
  FloatingPrompterHost(HWND owner, const flutter::DartProject& project,
                       flutter::BinaryMessenger* messenger);
  ~FloatingPrompterHost();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

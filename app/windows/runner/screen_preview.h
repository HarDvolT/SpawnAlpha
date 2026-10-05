#ifndef RUNNER_SCREEN_PREVIEW_H_
#define RUNNER_SCREEN_PREVIEW_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/texture_registrar.h>
#include <memory>

class ScreenPreview {
 public:
  ScreenPreview(flutter::BinaryMessenger* messenger,
                flutter::TextureRegistrar* textures);
  ~ScreenPreview();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
#endif  // RUNNER_SCREEN_PREVIEW_H_

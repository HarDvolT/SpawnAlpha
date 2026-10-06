#ifndef RUNNER_LOCAL_PLAYER_H_
#define RUNNER_LOCAL_PLAYER_H_
#include <flutter/binary_messenger.h>
#include <flutter/texture_registrar.h>
#include <memory>
class LocalPlayer {
 public:
  LocalPlayer(flutter::BinaryMessenger*, flutter::TextureRegistrar*);
  ~LocalPlayer();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

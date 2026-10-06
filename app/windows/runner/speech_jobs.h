#pragma once
#include <flutter/binary_messenger.h>
#include <memory>

class SpeechJobs {
 public:
  explicit SpeechJobs(flutter::BinaryMessenger* messenger);
  ~SpeechJobs();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

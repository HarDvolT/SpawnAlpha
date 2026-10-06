#ifndef RUNNER_RENDER_JOBS_H_
#define RUNNER_RENDER_JOBS_H_
#include <flutter/binary_messenger.h>
#include <memory>
class RenderJobs {
 public:
  explicit RenderJobs(flutter::BinaryMessenger*);
  ~RenderJobs();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

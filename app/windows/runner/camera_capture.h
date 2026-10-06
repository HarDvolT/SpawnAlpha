#ifndef RUNNER_CAMERA_CAPTURE_H_
#define RUNNER_CAMERA_CAPTURE_H_
#include <windows.h>
#include <memory>
#include <string>
#include <vector>
#include <cstdint>

// Immutable, top-down BGRA snapshot. No borrowed camera buffer crosses the
// callback. The recorder can upload this smaller camera image to its own GPU.
struct CameraFrame {
  UINT width = 0, height = 0;
  LONGLONG arrived_100ns = 0;
  std::vector<uint8_t> bgra;
};
class CameraCapture {
 public:
  CameraCapture();
  ~CameraCapture();
  HRESULT Open(const std::wstring& symbolic_link);
#ifdef SPAWNALPHA_CAMERA_FIXTURE
  // Only compiled into explicit, non-shipping generated-video checks.
  HRESULT OpenFixture(const std::wstring& local_path);
  HRESULT FixtureError() const;
#endif
  std::shared_ptr<const CameraFrame> Latest() const;
  bool Failed() const;
  void Stop();
 private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};
#endif

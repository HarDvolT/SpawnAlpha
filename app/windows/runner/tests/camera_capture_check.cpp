#include "../camera_capture.h"
#include <winrt/base.h>
#include <iostream>

int wmain(int count, wchar_t** args) {
  if (count != 2) return 2;
  if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) return 3;
  int result = 1;
  const char* stage = "chosen-device rejection";
  try {
    CameraCapture camera;
    if (SUCCEEDED(camera.Open(L"missing-spawnalpha-camera-device")) || camera.Latest()) throw winrt::hresult_error(E_FAIL);
    for (int cycle = 0; cycle < 2; ++cycle) {
      stage = "open generated fixture";
      winrt::check_hresult(camera.OpenFixture(args[1]));
      stage = "wait for generated frame";
      const auto deadline = GetTickCount64() + 5000;
      std::shared_ptr<const CameraFrame> frame;
      while (GetTickCount64() < deadline && !(frame = camera.Latest())) { if (camera.Failed()) winrt::check_hresult(camera.FixtureError()); Sleep(5); }
      if (!frame || frame->width < 2 || frame->height < 2 || frame->bgra.size() != static_cast<size_t>(frame->width) * frame->height * 4) throw winrt::hresult_error(E_FAIL);
      const size_t centre = (static_cast<size_t>(frame->height / 2) * frame->width + frame->width / 2) * 4;
      // This check is invoked with the generated blue-window recording.
      if (frame->bgra[centre] <= frame->bgra[centre + 2] + 40) throw winrt::hresult_error(E_FAIL);
      camera.Stop(); camera.Stop();
      if (camera.Latest()) throw winrt::hresult_error(E_FAIL);
      // The owned snapshot survives source shutdown and still has its pixels.
      if (frame->bgra.empty() || frame->arrived_100ns <= 0) throw winrt::hresult_error(E_FAIL);
    }
    std::cout << "Camera capture check passed: generated frames, owned buffers, chosen-device failure, repeated start/stop.\n";
    result = 0;
  } catch (...) { std::cerr << "Camera capture check failed at " << stage << ": " << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n"; }
  CoUninitialize(); return result;
}

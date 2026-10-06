// Both files use synthetic images. No private desktop, camera or microphone.
#include "../screen_recording_core.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <winrt/base.h>
#include <iostream>
#include <cmath>

void Require(bool value) { if (!value) throw winrt::hresult_error(E_FAIL); }
LRESULT CALLBACK Fixture(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{}; const auto dc = BeginPaint(window, &paint);
    RECT rect{}; GetClientRect(window, &rect); const auto brush = CreateSolidBrush(RGB(32, 96, 224));
    FillRect(dc, &rect, brush); DeleteObject(brush); EndPaint(window, &paint); return 0;
  }
  return DefWindowProc(window, message, wp, lp);
}
std::pair<UINT64, LONGLONG> Decode(const std::wstring& path) {
  using winrt::check_hresult; using winrt::com_ptr;
  com_ptr<IMFAttributes> options; check_hresult(MFCreateAttributes(options.put(), 1));
  check_hresult(options->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
  com_ptr<IMFSourceReader> reader; check_hresult(MFCreateSourceReaderFromURL(path.c_str(), options.get(), reader.put()));
  const DWORD video = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
  com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
  check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
  check_hresult(reader->SetCurrentMediaType(video, nullptr, type.get()));
  UINT64 frames = 0; LONGLONG last = -1;
  while (true) {
    DWORD flags = 0; LONGLONG time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(video, 0, nullptr, &flags, &time, sample.put()));
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (!sample) continue;
    Require(time > last); if (!frames) Require(time == 0);
    last = time; ++frames;
  }
  com_ptr<IMFMediaType> audio;
  Require(FAILED(reader->GetNativeMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), 0, audio.put())));
  return {frames, last};
}
int wmain(int count, wchar_t** args) {
  if (count != 4 && count != 5) return 2;
  const bool stop_paused = count == 5 && std::wcscmp(args[4], L"--stop-paused") == 0;
  const bool camera_loss = count == 5 && std::wcscmp(args[4], L"--camera-loss") == 0;
  if (count == 5 && !stop_paused && !camera_loss) return 2;
  if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) return 3;
  HWND window = nullptr; int result = 1;
  const char* stage = "capture";
  try {
    WNDCLASSW type{}; type.hInstance = GetModuleHandle(nullptr); type.lpfnWndProc = Fixture; type.lpszClassName = L"SpawnAlphaPairedFixture";
    Require(RegisterClassW(&type) != 0);
    window = CreateWindowW(type.lpszClassName, L"SpawnAlpha paired generated test", WS_POPUP | WS_VISIBLE,
      100, 100, 640, 360, nullptr, nullptr, type.hInstance, nullptr);
    Require(window != nullptr); ShowWindow(window, SW_SHOWNOACTIVATE); UpdateWindow(window);
    ScreenRecordingCore capture;
    winrt::check_hresult(capture.Start(nullptr, window, args[1], L"", false, args[3], args[2]));
    const auto deadline = GetTickCount64() + 15000;
    ULONGLONG origin = 0;
    bool paused = false, resumed = false, stopped = false;
    UINT64 held_frames = 0; LONGLONG held_duration = -1;
    while (GetTickCount64() < deadline) {
      MSG msg{}; while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
      const auto state = capture.Status();
      Require(state.state != ScreenRecordingState::failed);
      if (state.state == ScreenRecordingState::finished) break;
      if (state.state == ScreenRecordingState::recording || state.state == ScreenRecordingState::paused) {
        if (!origin) origin = GetTickCount64();
        const auto elapsed = GetTickCount64() - origin;
        if (!paused && elapsed > 700) { capture.SetPaused(true); paused = true; }
        if (state.state == ScreenRecordingState::paused) {
          if (held_duration < 0) { held_frames = state.frames; held_duration = state.duration_100ns; }
          Require(state.frames == held_frames && state.duration_100ns == held_duration);
        }
        if (!stop_paused && !resumed && elapsed > 1700) { capture.SetPaused(false); resumed = true; }
        if (!camera_loss && !stopped && elapsed > (stop_paused ? 1700U : 2800U)) { capture.RequestStop(); stopped = true; }
      }
      Sleep(5);
    }
    const auto state = capture.Status();
    Require(paused && held_duration >= 0 && (resumed || stop_paused) && (stopped || camera_loss));
    Require(state.reason == (camera_loss ? ScreenRecordingReason::camera : ScreenRecordingReason::none));
    Require(state.state == ScreenRecordingState::finished && state.frames >= (stop_paused || camera_loss ? 15U : 45U) && state.frames == state.camera_frames);
    stage = "decode paired files"; winrt::check_hresult(MFStartup(MF_VERSION));
    const auto screen = Decode(args[1]), camera = Decode(args[2]);
    Require(screen.first == state.frames && camera.first == state.frames && screen.second == camera.second);
    Require(std::abs(screen.second + 10000000LL / 30 - state.duration_100ns) <= 2);
    winrt::check_hresult(MFShutdown());
    std::cout << "Paired recording check passed: separate fragmented files, identical frame times, paused clock, ordered decoded endpoints, clean stop.\n";
    result = 0;
  } catch (...) { std::cerr << "Paired recording check failed at " << stage << ": " << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n"; }
  if (window) DestroyWindow(window); CoUninitialize(); return result;
}

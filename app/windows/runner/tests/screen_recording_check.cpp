#include "../screen_recording_core.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <winrt/base.h>
#include <iostream>
#include <cmath>
#include <vector>

#ifdef SPAWNALPHA_AUDIO_FIXTURE
void ConfigureAudioFixture(bool idle, bool fail, bool loss);
double Tone(const std::vector<int16_t>& pcm, size_t channel, double hz) {
  double real = 0, imaginary = 0;
  const size_t frames = pcm.size() / 2;
  for (size_t frame = 0; frame < frames; ++frame) {
    const double phase = frame * hz * 6.283185307179586 / 48000;
    real += pcm[frame * 2 + channel] * std::cos(phase);
    imaginary += pcm[frame * 2 + channel] * std::sin(phase);
  }
  return 2 * std::sqrt(real * real + imaginary * imaginary) / frames;
}
#endif

void Require(bool condition) { if (!condition) throw winrt::hresult_error(E_FAIL); }
LRESULT CALLBACK TestWindow(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{}; const HDC dc = BeginPaint(window, &paint);
    RECT area{}; GetClientRect(window, &area);
    const HBRUSH blue = CreateSolidBrush(RGB(32, 64, 224));
    FillRect(dc, &area, blue); DeleteObject(blue);
    const LONG x = static_cast<LONG>((GetTickCount64() / 30) % static_cast<ULONGLONG>(area.right));
    const RECT bar{x, 0, x + 20, area.bottom};
    const HBRUSH orange = CreateSolidBrush(RGB(224, 128, 32));
    FillRect(dc, &bar, orange); DeleteObject(orange);
    EndPaint(window, &paint); return 0;
  }
  return DefWindowProc(window, message, wp, lp);
}

void Decode(const std::wstring& path, const ScreenRecordingStatus& status, bool audio,
            bool stereo = false, bool voice = false, bool idle = false) {
  using winrt::check_hresult; using winrt::com_ptr;
  check_hresult(MFStartup(MF_VERSION));
  com_ptr<IMFAttributes> options;
  check_hresult(MFCreateAttributes(options.put(), 1));
  check_hresult(options->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
  com_ptr<IMFSourceReader> reader;
  check_hresult(MFCreateSourceReaderFromURL(path.c_str(), options.get(), reader.put()));
  com_ptr<IMFMediaType> rgb;
  check_hresult(MFCreateMediaType(rgb.put()));
  check_hresult(rgb->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
  check_hresult(rgb->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
  const DWORD video_stream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
  check_hresult(reader->SetCurrentMediaType(video_stream, nullptr, rgb.get()));
  UINT64 decoded = 0; LONGLONG previous = -1;
  while (true) {
    DWORD flags = 0; LONGLONG time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(video_stream, 0, nullptr, &flags, &time, sample.put()));
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (!sample) continue;
    Require(time > previous); previous = time;
    if (decoded == 0 || time >= status.duration_100ns - 1000000) {
      com_ptr<IMFMediaBuffer> buffer;
      check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
      BYTE* pixels = nullptr; DWORD length = 0;
      check_hresult(buffer->Lock(&pixels, nullptr, &length));
      bool sized = length >= 640 * 360 * 4;
      UINT blue = 0;
      for (UINT x : {160U, 240U, 320U, 400U, 480U}) {
        const size_t point = (180 * 640 + x) * 4;
        if (sized && pixels[point] > pixels[point + 2] + 60) ++blue;
      }
      const size_t margin = (180 * 640 + 10) * 4;
      const bool letterbox = decoded == 0 || (sized && pixels[margin] < 12 &&
          pixels[margin + 1] < 12 && pixels[margin + 2] < 12);
      check_hresult(buffer->Unlock());
      Require(sized && blue >= 3 && letterbox);
    }
    ++decoded;
  }
  Require(decoded == status.frames && decoded >= 30);
  Require(std::abs(previous + 10000000LL / 30 - status.duration_100ns) <= 2);
  com_ptr<IMFMediaType> audio_type;
  const DWORD audio_stream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
  const HRESULT has_audio = reader->GetNativeMediaType(audio_stream, 0, audio_type.put());
  Require(audio ? SUCCEEDED(has_audio) : FAILED(has_audio));
  if (audio) {
    check_hresult(reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE));
    check_hresult(reader->SetStreamSelection(audio_stream, TRUE));
    com_ptr<IMFMediaType> pcm;
    check_hresult(MFCreateMediaType(pcm.put()));
    check_hresult(pcm->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
    check_hresult(pcm->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM));
    check_hresult(pcm->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16));
    check_hresult(reader->SetCurrentMediaType(audio_stream, nullptr, pcm.get()));
    com_ptr<IMFMediaType> actual;
    check_hresult(reader->GetCurrentMediaType(audio_stream, actual.put()));
    UINT32 channels = 0;
    check_hresult(actual->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels));
    Require(channels == (stereo ? 2U : 1U));
    LONGLONG first = -1, last = -1;
    UINT64 samples = 0;
    std::vector<int16_t> decoded_audio;
    while (true) {
      DWORD flags = 0; LONGLONG time = 0; com_ptr<IMFSample> sample;
      check_hresult(reader->ReadSample(audio_stream, 0, nullptr, &flags, &time, sample.put()));
      if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
      if (!sample) continue;
      Require(time > last); if (first < 0) first = time; last = time;
      DWORD length = 0; check_hresult(sample->GetTotalLength(&length)); samples += length / (2 * channels);
#ifdef SPAWNALPHA_AUDIO_FIXTURE
      if (stereo) {
        com_ptr<IMFMediaBuffer> buffer;
        check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
        BYTE* bytes = nullptr;
        check_hresult(buffer->Lock(&bytes, nullptr, &length));
        const auto* values = reinterpret_cast<const int16_t*>(bytes);
        decoded_audio.insert(decoded_audio.end(), values, values + length / 2);
        check_hresult(buffer->Unlock());
      }
#endif
    }
    Require(std::abs(first) < 1000000 && samples >= 48000);
    Require(std::abs(last - previous) < 1500000);
#ifdef SPAWNALPHA_AUDIO_FIXTURE
    if (stereo) {
      Require(!decoded_audio.empty());
      if (idle) {
        double squares = 0;
        for (const auto value : decoded_audio) squares += static_cast<double>(value) * value;
        Require(std::sqrt(squares / decoded_audio.size()) < 30);
      } else {
        Require(Tone(decoded_audio, 0, 1000) > 500 && Tone(decoded_audio, 1, 1500) > 500);
        Require(Tone(decoded_audio, 0, 1500) < 300 && Tone(decoded_audio, 1, 1000) < 300);
        Require(voice ? Tone(decoded_audio, 0, 600) > 300 && Tone(decoded_audio, 1, 600) > 300
                      : Tone(decoded_audio, 0, 600) < 300 && Tone(decoded_audio, 1, 600) < 300);
      }
      Require(status.audio_frames == static_cast<UINT64>(status.duration_100ns * 48000 / 10000000));
      Require(voice ? status.loudest_rms_db > -40 : status.loudest_rms_db == -100);
      Require(idle ? status.loudest_system_rms_db == -100 : status.loudest_system_rms_db > -40);
    }
#endif
  }
  reader = nullptr; rgb = nullptr; audio_type = nullptr; options = nullptr;
  check_hresult(MFShutdown());
}

int wmain(int count, wchar_t** args) {
  if (count != 2 && count != 3) return 2;
  bool pause = count == 3 && (std::wcscmp(args[2], L"--pause") == 0 || std::wcscmp(args[2], L"--microphone-pause") == 0);
  bool audio = count == 3 && (std::wcscmp(args[2], L"--microphone") == 0 || std::wcscmp(args[2], L"--microphone-pause") == 0);
  bool system = false, idle = false, bad_system = false, lost_system = false;
#ifdef SPAWNALPHA_AUDIO_FIXTURE
  if (count != 3) return 2;
  system = true;
  audio = std::wcscmp(args[2], L"--mixed") == 0 || std::wcscmp(args[2], L"--mixed-pause") == 0;
  pause = std::wcscmp(args[2], L"--system-pause") == 0 || std::wcscmp(args[2], L"--mixed-pause") == 0;
  idle = std::wcscmp(args[2], L"--idle-system") == 0;
  bad_system = std::wcscmp(args[2], L"--missing-system") == 0;
  lost_system = std::wcscmp(args[2], L"--lost-system") == 0;
  if (!audio && !pause && !idle && !bad_system && !lost_system && std::wcscmp(args[2], L"--system") != 0) return 2;
  ConfigureAudioFixture(idle, bad_system, lost_system);
#endif
  const bool minimize = count == 3 && std::wcscmp(args[2], L"--minimize") == 0;
  const bool close = count == 3 && std::wcscmp(args[2], L"--close") == 0;
  const bool cancel = count == 3 && std::wcscmp(args[2], L"--cancel") == 0;
  const bool bad_mic = count == 3 && std::wcscmp(args[2], L"--missing-microphone") == 0;
  if (count == 3 && !system && !audio && !minimize && !close && !cancel && !bad_mic && !pause) return 2;
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return 3;
  HWND window = nullptr;
  const char* stage = "create test window";
  try {
    WNDCLASSW type{}; type.lpfnWndProc = TestWindow;
    type.hInstance = GetModuleHandle(nullptr); type.lpszClassName = L"SpawnAlphaRecordingFixture";
    Require(RegisterClassW(&type) != 0);
    window = CreateWindowW(type.lpszClassName, L"SpawnAlpha generated recording test",
        WS_POPUP | WS_VISIBLE, 80, 80, 640, 360, nullptr, nullptr, type.hInstance, nullptr);
    Require(window != nullptr);
    ShowWindow(window, SW_SHOW); UpdateWindow(window);
    ScreenRecordingCore recorder;
    stage = "start recording";
    winrt::check_hresult(recorder.Start(nullptr, window, args[1],
        bad_mic ? L"missing-spawnalpha-check-device" : L"", audio || bad_mic, {}, {}, system));
    if (cancel) recorder.RequestStop();
    ULONGLONG recording_start = 0, start = GetTickCount64();
    bool resized = false, stopped = false;
    bool requested_pause = false, requested_resume = false, saw_pause = false;
    UINT64 paused_frames = 0; LONGLONG paused_duration = -1;
    while (GetTickCount64() - start < 15000) {
      MSG message{};
      while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessage(&message); }
      const auto status = recorder.Status();
      if (status.state == ScreenRecordingState::failed) {
        if (cancel || bad_mic || bad_system) break;
        stage = "recording failed"; throw winrt::hresult_error(E_FAIL);
      }
      if (status.state == ScreenRecordingState::finished) break;
      if (status.state == ScreenRecordingState::recording || status.state == ScreenRecordingState::paused) {
        if (!recording_start) recording_start = GetTickCount64();
        const auto elapsed = GetTickCount64() - recording_start;
        if (!resized && elapsed > 1000) {
          SetWindowPos(window, nullptr, 120, 120, 320, 240, SWP_NOZORDER | SWP_NOACTIVATE); resized = true;
        }
        if (pause && !requested_pause && elapsed > 800) { recorder.SetPaused(true); requested_pause = true; }
        if (status.state == ScreenRecordingState::paused) {
          saw_pause = true;
          if (paused_duration < 0) { paused_duration = status.duration_100ns; paused_frames = status.frames; }
          Require(status.duration_100ns == paused_duration && status.frames == paused_frames);
        }
        if (pause && !requested_resume && elapsed > 1800) { recorder.SetPaused(false); requested_resume = true; }
        if (!stopped && elapsed > (pause ? 3400U : 2400U)) {
          if (minimize) ShowWindow(window, SW_MINIMIZE);
          else if (close) { DestroyWindow(window); window = nullptr; }
          else recorder.RequestStop();
          stopped = true;
        }
      }
      if (window && !minimize) InvalidateRect(window, nullptr, FALSE);
      Sleep(10);
    }
    stage = "validate safe stop";
    const auto status = recorder.Status();
    if (cancel || bad_mic || bad_system) {
      Require(status.state == ScreenRecordingState::failed && status.frames == 0);
      Require(status.reason == (cancel ? ScreenRecordingReason::cancelled : bad_system ? ScreenRecordingReason::systemAudio : ScreenRecordingReason::microphone));
      Require(GetFileAttributesW(args[1]) == INVALID_FILE_ATTRIBUTES);
      if (window) DestroyWindow(window);
      std::cout << "Screen recording startup-failure check passed: no saved file or device fallback.\n";
      CoUninitialize(); return 0;
    }
    Require(status.state == ScreenRecordingState::finished);
    Require(status.reason == ((minimize || close) ? ScreenRecordingReason::source : lost_system ? ScreenRecordingReason::systemAudio : ScreenRecordingReason::none));
    Require(status.width == 640 && status.height == 360 && status.duration_100ns >= 20000000);
    if (pause) Require(saw_pause && requested_resume && status.duration_100ns < 28000000);
    Require(audio || system ? status.audio_frames >= 48000 : status.audio_frames == 0);
    stage = "decode saved recording";
    Decode(args[1], status, audio || system, system, audio, idle);
    if (window) DestroyWindow(window);
    std::cout << "Screen recording check passed: generated window, resize, safe stop, decoded frames";
    if (audio) std::cout << ", microphone track and aligned endpoints";
    if (minimize || close) std::cout << ", source-loss recovery";
    if (pause) std::cout << ", pause gap removed";
    std::cout << ".\n";
    CoUninitialize(); return 0;
  } catch (...) {
    if (window) DestroyWindow(window);
    std::cerr << "Screen recording check failed at " << stage << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    CoUninitialize(); return 1;
  }
}

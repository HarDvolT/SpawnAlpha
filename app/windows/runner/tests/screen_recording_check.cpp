#include "../screen_recording_core.h"
#include "../recording_probe.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <winrt/base.h>
#include <iostream>
#include <cmath>
#include <vector>
#include <cstring>
#include <psapi.h>
void ConfigureRecordingStall(DWORD);

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

void RequireAt(bool condition, int line) {
  if (!condition) { std::cerr << "Generated recording guard at line " << line << "\n"; throw winrt::hresult_error(E_FAIL); }
}
#define Require(value) RequireAt(value, __LINE__)
LRESULT CALLBACK TestWindow(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_SETCURSOR) { SetCursor(LoadCursorW(nullptr, IDC_ARROW)); return TRUE; }
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
            bool stereo = false, bool voice = false, bool idle = false, bool short_take = false) {
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
    if (decoded == 0) Require(time == 0);
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
      Require(sized && blue >= 3 && (short_take || letterbox));
    }
    ++decoded;
  }
  Require(decoded == status.frames && decoded >= (short_take ? 1U : 30U));
  Require(std::abs(previous + 10000000LL / 30 - status.duration_100ns) <= 334);
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
    Require(std::abs(first) < 1000000 && samples >= (short_take ? 1U : 48000U));
    Require(std::abs(last - previous) < 1500000);
    if (short_take) {
      const auto expected = status.duration_100ns * 48000 / 10000000;
      Require(std::abs(static_cast<LONGLONG>(samples) - expected) <= 2048);
    }
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

void CheckCursorPair(const std::wstring& original, const std::wstring& clean, UINT64 frames) {
  using winrt::check_hresult; using winrt::com_ptr;
  check_hresult(MFStartup(MF_VERSION));
  {
    com_ptr<IMFAttributes> options; check_hresult(MFCreateAttributes(options.put(), 1));
    check_hresult(options->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
    com_ptr<IMFSourceReader> first, second;
    check_hresult(MFCreateSourceReaderFromURL(original.c_str(), options.get(), first.put()));
    check_hresult(MFCreateSourceReaderFromURL(clean.c_str(), options.get(), second.put()));
    com_ptr<IMFMediaType> rgb; check_hresult(MFCreateMediaType(rgb.put()));
    check_hresult(rgb->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
    check_hresult(rgb->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
    const auto stream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
    for (auto* reader : {first.get(), second.get()}) {
      check_hresult(reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE));
      check_hresult(reader->SetStreamSelection(stream, TRUE));
      check_hresult(reader->SetCurrentMediaType(stream, nullptr, rgb.get()));
    }
    struct Picture { bool end = false; LONGLONG time = 0, duration = 0; UINT white = 0; };
    auto read = [&](IMFSourceReader* reader) {
      Picture picture;
      while (true) {
        DWORD flags = 0; com_ptr<IMFSample> sample;
        check_hresult(reader->ReadSample(stream, 0, nullptr, &flags, &picture.time, sample.put()));
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { picture.end = true; return picture; }
        if (!sample) continue;
        check_hresult(sample->GetSampleDuration(&picture.duration));
        com_ptr<IMFMediaBuffer> buffer; check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
        BYTE* pixels = nullptr; DWORD length = 0;
        check_hresult(buffer->Lock(&pixels, nullptr, &length));
        Require(length >= 640U * 360U * 4U);
        for (size_t offset = 0; offset + 3 < length; offset += 4) {
          if (pixels[offset] > 180 && pixels[offset + 1] > 180 && pixels[offset + 2] > 180) ++picture.white;
        }
        check_hresult(buffer->Unlock()); return picture;
      }
    };
    UINT64 decoded = 0, pointer_frames = 0;
    while (true) {
      const auto original_frame = read(first.get()), clean_frame = read(second.get());
      Require(original_frame.end == clean_frame.end);
      if (original_frame.end) break;
      Require(original_frame.time == clean_frame.time && original_frame.duration == clean_frame.duration);
      Require(clean_frame.white < 4);
      if (original_frame.white > 20) ++pointer_frames;
      ++decoded;
    }
    if (!(decoded == frames && pointer_frames > decoded / 2))
      std::cerr << "Generated cursor counts: decoded=" << decoded
                << " visible=" << pointer_frames << " expected=" << frames << "\n";
    Require(decoded == frames && pointer_frames > decoded / 2);
  }
  check_hresult(MFShutdown());
  std::cout << "Cursor pair decoded: identical clocks/counts, original pointer retained, clean picture verified.\n";
}

int wmain(int count, wchar_t** args) {
  if (count != 2 && count != 3) return 2;
  const bool cursor_slow = count == 3 && std::wcscmp(args[2], L"--cursor-slow") == 0;
  const bool required_slow = count == 3 && (std::wcscmp(args[2], L"--slow") == 0 ||
      std::wcscmp(args[2], L"--mixed-slow") == 0 || std::wcscmp(args[2], L"--voice-slow") == 0);
  ConfigureRecordingStall(cursor_slow ? 700 : required_slow ? 1200 : 0);
  const bool cursor = cursor_slow || (count == 3 && (std::wcscmp(args[2], L"--cursor") == 0 || std::wcscmp(args[2], L"--cursor-pause") == 0 || std::wcscmp(args[2], L"--cursor-long") == 0 || std::wcscmp(args[2], L"--cursor-blocked") == 0 || std::wcscmp(args[2], L"--mixed-cursor-pause") == 0));
  const bool cursor_blocked = count == 3 && std::wcscmp(args[2], L"--cursor-blocked") == 0;
  bool pause = count == 3 && (std::wcscmp(args[2], L"--pause") == 0 || std::wcscmp(args[2], L"--microphone-pause") == 0 || std::wcscmp(args[2], L"--cursor-pause") == 0);
  const bool long_take = count == 3 && (std::wcscmp(args[2], L"--long") == 0 || std::wcscmp(args[2], L"--cursor-long") == 0);
  if (long_take) pause = true;
  bool audio = count == 3 && (std::wcscmp(args[2], L"--microphone") == 0 || std::wcscmp(args[2], L"--microphone-pause") == 0);
  bool system = false, idle = false, bad_system = false, lost_system = false;
#ifdef SPAWNALPHA_AUDIO_FIXTURE
  if (count != 3) return 2;
  const bool voice_slow = std::wcscmp(args[2], L"--voice-slow") == 0;
  system = !voice_slow;
  audio = std::wcscmp(args[2], L"--mixed") == 0 || std::wcscmp(args[2], L"--mixed-pause") == 0 || std::wcscmp(args[2], L"--mixed-cursor-pause") == 0 || required_slow;
  pause = std::wcscmp(args[2], L"--system-pause") == 0 || std::wcscmp(args[2], L"--mixed-pause") == 0 || std::wcscmp(args[2], L"--mixed-cursor-pause") == 0;
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
  if (count == 3 && !system && !audio && !minimize && !close && !cancel && !bad_mic && !pause && !long_take && !cursor && !required_slow) return 2;
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return 3;
  HWND window = nullptr;
  POINT previous_cursor{}; const bool restore_cursor = cursor && GetCursorPos(&previous_cursor);
  const std::wstring cursor_path = std::wstring(args[1]) + L".clean.mp4";
  const char* stage = "create test window";
  try {
    WNDCLASSW type{}; type.lpfnWndProc = TestWindow;
    type.hInstance = GetModuleHandle(nullptr); type.lpszClassName = L"SpawnAlphaRecordingFixture";
    type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    Require(RegisterClassW(&type) != 0);
    window = CreateWindowW(type.lpszClassName, L"SpawnAlpha generated recording test",
        WS_POPUP | WS_VISIBLE, 80, 80, 640, 360, nullptr, nullptr, type.hInstance, nullptr);
    Require(window != nullptr);
    ShowWindow(window, SW_SHOW); UpdateWindow(window);
    if (cursor) SetCursorPos(280, 180);
    if (cursor_blocked) {
      const auto file = CreateFileW(cursor_path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
      Require(file != INVALID_HANDLE_VALUE); DWORD written = 0;
      Require(WriteFile(file, "keep", 4, &written, nullptr) && written == 4); CloseHandle(file);
    }
    ScreenRecordingCore recorder;
    stage = "start recording";
    winrt::check_hresult(recorder.Start(nullptr, window, args[1],
        bad_mic ? L"missing-spawnalpha-check-device" : L"", audio || bad_mic, {}, {}, system, {}, cursor ? cursor_path : L""));
    if (cancel) recorder.RequestStop();
    ULONGLONG recording_start = 0, start = GetTickCount64();
    bool resized = false, stopped = false;
    bool requested_pause = false, requested_resume = false, saw_pause = false;
    UINT64 paused_frames = 0; LONGLONG paused_duration = -1;
    size_t baseline_memory = 0, peak_memory = 0;
    int extra_pause = 0;
    while (GetTickCount64() - start < (long_take ? 45000U : 15000U)) {
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
        // Keep the owned pointer active during long checks. Windows may hide
        // an idle cursor, or it may otherwise move out of the generated source.
        if (cursor && window)
          SetCursorPos(260 + static_cast<int>((elapsed / 400) % 4) * 4, resized ? 220 : 180);
        if (long_take && elapsed > 5000) {
          PROCESS_MEMORY_COUNTERS_EX memory{}; memory.cb = sizeof(memory);
          Require(K32GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory), sizeof(memory)));
          if (!baseline_memory) baseline_memory = memory.PrivateUsage;
          peak_memory = std::max(peak_memory, memory.PrivateUsage);
          const ULONGLONG times[] = {8000, 9000, 16000, 17000};
          if (extra_pause < 4 && elapsed > times[extra_pause]) {
            recorder.SetPaused(extra_pause % 2 == 0); ++extra_pause;
          }
        }
        if (!resized && elapsed > 1000) {
          SetWindowPos(window, nullptr, 120, 120, 320, 240, SWP_NOZORDER | SWP_NOACTIVATE); resized = true;
          if (cursor) SetCursorPos(280, 220);
        }
        if (pause && !requested_pause && elapsed > 800) { recorder.SetPaused(true); requested_pause = true; }
        if (status.state == ScreenRecordingState::paused && extra_pause == 0) {
          saw_pause = true;
          if (paused_duration < 0) { paused_duration = status.duration_100ns; paused_frames = status.frames; }
          Require(status.duration_100ns == paused_duration && status.frames == paused_frames);
        }
        if (pause && !requested_resume && elapsed > 1800) { recorder.SetPaused(false); requested_resume = true; }
        if (!stopped && elapsed > (long_take ? 30000U : pause ? 3400U : 2400U)) {
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
    if (required_slow) {
      const std::atomic<bool> cancelled{false};
      const auto info = ProbeRecording(args[1], cancelled);
      Require(status.reason == ScreenRecordingReason::encoder && status.frames == 10 &&
          info.readable && std::abs(info.duration_100ns - status.duration_100ns) <= 334);
      Decode(args[1], status, audio || system, system, audio, false, true);
      if (window) DestroyWindow(window);
      std::cout << "Slow encoder check passed: readable original, continuous clock and bounded stop.\n";
      CoUninitialize(); return 0;
    }
    Require(status.reason == ((minimize || close) ? ScreenRecordingReason::source : lost_system ? ScreenRecordingReason::systemAudio : ScreenRecordingReason::none));
    Require(status.width == 640 && status.height == 360 && status.duration_100ns >= 20000000);
    if (pause) Require(saw_pause && requested_resume && (long_take || status.duration_100ns < 28000000));
    if (long_take) {
      Require(extra_pause == 4 && status.frames > 650 && status.duration_100ns > 260000000 && status.duration_100ns < 290000000);
      Require(baseline_memory > 0 && peak_memory - baseline_memory < 128ULL * 1024 * 1024);
      std::cout << "Long take check passed: 30 seconds, three pauses, bounded private-memory growth ("
          << (peak_memory - baseline_memory) / 1024 / 1024 << " MiB).\n";
    }
    Require(audio || system ? status.audio_frames >= 48000 : status.audio_frames == 0);
    stage = "decode saved recording";
    Decode(args[1], status, audio || system, system, audio, idle);
    const std::atomic<bool> probe_cancel{false};
    const auto original_probe = ProbeRecording(args[1], probe_cancel);
    Require(original_probe.readable && std::abs(original_probe.duration_100ns - status.duration_100ns) <= 334);
    if (cursor) {
      Require(status.cursor_free_complete == (!cursor_blocked && !cursor_slow));
      if (cursor_slow) {
        Require(status.cursor_free_frames == 10 && status.frames > status.cursor_free_frames);
        Require(GetFileAttributesW(cursor_path.c_str()) != INVALID_FILE_ATTRIBUTES);
        std::cout << "Optional picture pressure check passed: original kept continuous, partial companion ineligible.\n";
      } else if (!cursor_blocked) {
        Require(status.cursor_free_frames == status.frames);
        Decode(cursor_path, status, false);
        Require(std::abs(ProbeRecording(cursor_path, probe_cancel).duration_100ns - status.duration_100ns) <= 334);
        CheckCursorPair(args[1], cursor_path, status.frames);
      } else {
        Require(status.cursor_free_frames == 0);
        const auto file = CreateFileW(cursor_path.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        Require(file != INVALID_HANDLE_VALUE); char bytes[4]{}; DWORD read = 0;
        Require(ReadFile(file, bytes, 4, &read, nullptr) && read == 4); CloseHandle(file);
        Require(std::memcmp(bytes, "keep", 4) == 0);
      }
    }
    if (window) DestroyWindow(window);
    if (restore_cursor) SetCursorPos(previous_cursor.x, previous_cursor.y);
    std::cout << "Screen recording check passed: generated window, resize, safe stop, decoded frames";
    if (audio) std::cout << ", microphone track and aligned endpoints";
    if (minimize || close) std::cout << ", source-loss recovery";
    if (pause) std::cout << ", pause gap removed";
    std::cout << ".\n";
    CoUninitialize(); return 0;
  } catch (...) {
    if (window) DestroyWindow(window);
    if (restore_cursor) SetCursorPos(previous_cursor.x, previous_cursor.y);
    std::cerr << "Screen recording check failed at " << stage << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    CoUninitialize(); return 1;
  }
}

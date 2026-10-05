#include "../microphone_capture.h"
#include <winrt/base.h>
#include <iostream>

int wmain(int count, wchar_t** args) {
  if (count > 2) return 2;
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return 3;
  try {
    MicrophoneCapture microphone;
    if (SUCCEEDED(microphone.Open(L"missing-spawnalpha-check-device"))) throw winrt::hresult_error(E_FAIL);
    winrt::check_hresult(microphone.Open(count == 2 ? args[1] : L""));
    MicrophonePacket packet;
    if (SUCCEEDED(microphone.Read(packet))) throw winrt::hresult_error(E_FAIL);
    winrt::check_hresult(microphone.Start());
    UINT64 frames = 0, previous = 0;
    const ULONGLONG start = GetTickCount64();
    while (GetTickCount64() - start < 1100) {
      const HRESULT read = microphone.Read(packet);
      winrt::check_hresult(read);
      if (read == S_FALSE) { Sleep(5); continue; }
      if (packet.pcm.empty() || packet.pcm.size() > 48000) throw winrt::hresult_error(E_FAIL);
      if (!packet.timestamp_error) {
        if (packet.qpc_100ns <= previous) throw winrt::hresult_error(E_FAIL);
        previous = packet.qpc_100ns;
      }
      frames += packet.pcm.size();
      // Captured samples are discarded immediately: no file or private log.
    }
    microphone.Stop(); microphone.Stop();
    if (frames < 24000 || frames > 72000 || !previous) throw winrt::hresult_error(E_FAIL);
    if (SUCCEEDED(microphone.Read(packet))) throw winrt::hresult_error(E_FAIL);
    std::cout << "Microphone check passed: PCM packets, timestamps, no device fallback, clean stop; nothing saved.\n";
    CoUninitialize();
    return 0;
  } catch (...) {
    std::cerr << "Microphone check failed: 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    CoUninitialize();
    return 1;
  }
}

#include "../microphone_capture.h"
#include <winrt/base.h>
#include <iostream>

int main() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    for (int trial = 0; trial < 3; ++trial) {
      SystemAudioCapture capture;
      SystemAudioPacket packet;
      if (capture.Read(packet) != E_UNEXPECTED) throw winrt::hresult_error(E_FAIL);
      winrt::check_hresult(capture.Open()); winrt::check_hresult(capture.Start());
      const auto started = GetTickCount64();
      while (GetTickCount64() - started < 120) {
        const auto result = capture.Read(packet);
        if (result != S_FALSE) {
          winrt::check_hresult(result);
          if (packet.pcm.empty() || packet.pcm.size() % 2 || !packet.qpc_100ns)
            throw winrt::hresult_error(E_FAIL);
        }
        packet = {};  // Never write or log playback samples, even if present.
        Sleep(2);
      }
      capture.Stop(); capture.Stop();
    }
    winrt::uninit_apartment();
    std::cout << "System loopback format/lifetime check passed; all samples discarded.\n";
    return 0;
  } catch (...) {
    std::cerr << "System loopback check failed: 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    return 1;
  }
}

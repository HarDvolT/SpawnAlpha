#ifndef RUNNER_MICROPHONE_CAPTURE_H_
#define RUNNER_MICROPHONE_CAPTURE_H_
#include <windows.h>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

struct MicrophonePacket {
  std::vector<int16_t> pcm;
  UINT64 qpc_100ns = 0;
  UINT64 device_frames = 0;
  bool discontinuity = false;
  bool timestamp_error = false;
};

// Same timestamp/flags as the microphone, but interleaved stereo PCM16 at 48 kHz.
using SystemAudioPacket = MicrophonePacket;

// Shared-mode mono PCM16, 48 kHz. Open/read/stop on one COM-initialized thread.
// A null/default choice is pinned when opened; never fall back from a chosen ID.
class MicrophoneCapture {
 public:
  MicrophoneCapture();
  ~MicrophoneCapture();
  HRESULT Open(const std::wstring& id);
  HRESULT Start();
  // S_FALSE means no packet yet. A device/access error is returned to the caller.
  HRESULT Read(MicrophonePacket& packet);
  void Stop();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

// Pins Windows' default render endpoint on Open. Shared-mode loopback captures
// the entire playback mix, not just a chosen window. No fallback after unplug.
class SystemAudioCapture {
 public:
  SystemAudioCapture();
  ~SystemAudioCapture();
  HRESULT Open();
  HRESULT Start();
  HRESULT Read(SystemAudioPacket& packet);
  void Stop();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

// Copyright 2026 SpawnAlpha. Added to the vendored camera_windows plugin,
// under the same BSD-style licence (see LICENSE).

#ifndef PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_AUDIO_INPUT_H_
#define PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_AUDIO_INPUT_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <atomic>
#include <map>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace camera_windows {

// A microphone (an active audio capture endpoint).
struct AudioInputInfo {
  std::wstring id;
  std::wstring name;
  bool is_default = false;
};

// The active microphones, the Windows default first.
std::vector<AudioInputInfo> ListAudioInputs();

// The endpoint ID of the Windows default microphone, or empty.
std::wstring DefaultAudioInputId();

// The microphone the capture engine records from. Empty means the Windows
// default microphone. Upstream always used the first microphone listed,
// which is often a virtual or unused device on PCs with several.
void SetPreferredAudioInput(const std::wstring& id);
std::wstring PreferredAudioInput();

// Measures a microphone's level on a background thread, through its own
// shared-mode WASAPI stream (the capture engine keeps recording as usual).
// Values are in dBFS over the last ~50 ms; -100 means silence or no data.
class AudioLevelMonitor {
 public:
  AudioLevelMonitor() = default;
  ~AudioLevelMonitor();

  AudioLevelMonitor(const AudioLevelMonitor&) = delete;
  AudioLevelMonitor& operator=(const AudioLevelMonitor&) = delete;

  // Starts measuring [id], or the default microphone when empty.
  void Start(const std::wstring& id);
  void Stop();

  float peak_db() const { return peak_db_.load(); }
  float rms_db() const { return rms_db_.load(); }
  bool running() const { return running_.load(); }

  // True when the stream could not be opened (no device, access denied).
  bool failed() const { return failed_.load(); }

  // True when Windows refused access: the microphone privacy switches are
  // off for desktop apps. Implies failed().
  bool denied() const { return denied_.load(); }

 private:
  void Run(std::wstring id);

  std::thread thread_;
  std::atomic<bool> running_{false};
  std::atomic<bool> failed_{false};
  std::atomic<bool> denied_{false};
  std::atomic<float> peak_db_{-100.0f};
  std::atomic<float> rms_db_{-100.0f};
};

// The "spawnalpha/audio_input" method channel: list, select, startLevels,
// stopLevels and level for the chosen microphone; watchAll, levels and
// unwatchAll to meter every microphone at once (the record set-up). Owned
// by the registrar, like a plugin.
class AudioInputChannel : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit AudioInputChannel(flutter::BinaryMessenger* messenger);
  ~AudioInputChannel() override;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  AudioLevelMonitor monitor_;

  // One monitor per microphone while the record set-up shows every meter.
  std::map<std::wstring, std::unique_ptr<AudioLevelMonitor>> watched_;
};

}  // namespace camera_windows

#endif  // PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_AUDIO_INPUT_H_

// Non-shipping implementation of both endpoints, linked only by the explicit
// audio_recording_check target. Never opens a real playback/microphone device.
#include "../microphone_capture.h"
#include <audioclient.h>
#include <cmath>

namespace {
bool idle_system = false, fail_system = false, lose_system = false;
UINT64 Qpc() {
  LARGE_INTEGER now{}, frequency{};
  QueryPerformanceCounter(&now); QueryPerformanceFrequency(&frequency);
  return static_cast<UINT64>(now.QuadPart / frequency.QuadPart * 10000000 +
      now.QuadPart % frequency.QuadPart * 10000000 / frequency.QuadPart);
}
struct Endpoint {
  bool running = false, system = false;
  UINT64 origin = 0, frames = 0;
  HRESULT Start() { running = true; origin = Qpc(); frames = 0; return S_OK; }
  HRESULT Read(MicrophonePacket& packet) {
    packet = {};
    if (!running) return E_UNEXPECTED;
    const auto now = Qpc();
    if (system && lose_system && now - origin > 21000000) return AUDCLNT_E_DEVICE_INVALIDATED;
    if (system && idle_system) return S_FALSE;
    if (now - origin < (frames + 480) * 10000000 / 48000) return S_FALSE;
    const auto channels = system ? 2U : 1U;
    packet.pcm.resize(480 * channels);
    for (size_t frame = 0; frame < 480; ++frame) {
      const auto time = static_cast<double>(frames + frame) / 48000;
      for (size_t channel = 0; channel < channels; ++channel) {
        const auto hz = system ? (channel == 0 ? 1000.0 : 1500.0) : 600.0;
        packet.pcm[frame * channels + channel] = static_cast<int16_t>((system ? 3000 : 2000) * std::sin(time * hz * 6.283185307179586));
      }
    }
    packet.qpc_100ns = origin + frames * 10000000 / 48000;
    packet.device_frames = frames; frames += 480;
    return S_OK;
  }
};
}
void ConfigureAudioFixture(bool idle, bool fail, bool loss) {
  idle_system = idle; fail_system = fail; lose_system = loss;
}
struct MicrophoneCapture::Impl : Endpoint {};
MicrophoneCapture::MicrophoneCapture() : impl_(std::make_unique<Impl>()) {}
MicrophoneCapture::~MicrophoneCapture() = default;
HRESULT MicrophoneCapture::Open(const std::wstring&) { return S_OK; }
HRESULT MicrophoneCapture::Start() { return impl_->Start(); }
HRESULT MicrophoneCapture::Read(MicrophonePacket& packet) { return impl_->Read(packet); }
void MicrophoneCapture::Stop() { impl_->running = false; }
struct SystemAudioCapture::Impl : Endpoint { Impl() { system = true; } };
SystemAudioCapture::SystemAudioCapture() : impl_(std::make_unique<Impl>()) {}
SystemAudioCapture::~SystemAudioCapture() = default;
HRESULT SystemAudioCapture::Open() { return fail_system ? E_ACCESSDENIED : S_OK; }
HRESULT SystemAudioCapture::Start() { return impl_->Start(); }
HRESULT SystemAudioCapture::Read(SystemAudioPacket& packet) { return impl_->Read(packet); }
void SystemAudioCapture::Stop() { impl_->running = false; }

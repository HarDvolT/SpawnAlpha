#include "microphone_capture.h"
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <winrt/base.h>
#include <cstring>

using winrt::check_hresult;
using winrt::com_ptr;

namespace {
struct AudioCapture {
  ~AudioCapture() { Stop(); }
  HRESULT Open(const std::wstring& id, bool loopback) {
    Stop();
    try {
      com_ptr<IMMDeviceEnumerator> devices;
      check_hresult(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                     __uuidof(IMMDeviceEnumerator), devices.put_void()));
      com_ptr<IMMDevice> device;
      const auto direction = loopback ? eRender : eCapture;
      channels = loopback ? 2U : 1U;
      if (id.empty()) check_hresult(devices->GetDefaultAudioEndpoint(direction, eConsole, device.put()));
      else check_hresult(devices->GetDevice(id.c_str(), device.put()));
      EDataFlow flow{};
      check_hresult(device.as<IMMEndpoint>()->GetDataFlow(&flow));
      if (flow != direction) return E_INVALIDARG;
      check_hresult(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, client.put_void()));
      WAVEFORMATEX format{};
      format.wFormatTag = WAVE_FORMAT_PCM;
      format.nChannels = static_cast<WORD>(channels); format.nSamplesPerSec = 48000; format.wBitsPerSample = 16;
      format.nBlockAlign = static_cast<WORD>(channels * 2); format.nAvgBytesPerSec = 48000 * channels * 2;
      // Windows converts the chosen endpoint's mix format. No custom resampler
      // or first-device fallback; access/unplug errors fail the recording start.
      check_hresult(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
          AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY |
              (loopback ? AUDCLNT_STREAMFLAGS_LOOPBACK : 0),
          1000000, 0, &format, nullptr));
      check_hresult(client->GetService(__uuidof(IAudioCaptureClient), capture.put_void()));
      return S_OK;
    } catch (...) { const auto error = winrt::to_hresult(); Stop(); return error; }
  }
  HRESULT Start() {
    if (!client || running) return E_UNEXPECTED;
    const HRESULT result = client->Start();
    running = SUCCEEDED(result);
    return result;
  }
  HRESULT Read(MicrophonePacket& packet) {
    packet = {};
    if (!running || !capture) return E_UNEXPECTED;
    BYTE* bytes = nullptr; UINT32 frames = 0; DWORD flags = 0;
    UINT64 position = 0, qpc = 0;
    const HRESULT result = capture->GetBuffer(&bytes, &frames, &flags, &position, &qpc);
    if (FAILED(result)) return result;
    if (!frames) return S_FALSE;
    HRESULT copied = S_OK;
    try {
      packet.pcm.resize(static_cast<size_t>(frames) * channels);
      if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT)) {
        if (!bytes) throw winrt::hresult_error(E_POINTER);
        std::memcpy(packet.pcm.data(), bytes, packet.pcm.size() * sizeof(int16_t));
      }
      packet.qpc_100ns = qpc; packet.device_frames = position;
      packet.discontinuity = (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) != 0;
      packet.timestamp_error = (flags & AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR) != 0;
    } catch (...) { copied = winrt::to_hresult(); }
    const HRESULT released = capture->ReleaseBuffer(frames);
    return FAILED(copied) ? copied : released;
  }
  void Stop() {
    if (client && running) client->Stop();
    running = false; capture = nullptr; client = nullptr;
  }
  bool running = false;
  UINT channels = 1;
  com_ptr<IAudioClient> client;
  com_ptr<IAudioCaptureClient> capture;
};
}  // namespace
struct MicrophoneCapture::Impl : AudioCapture {};
MicrophoneCapture::MicrophoneCapture() : impl_(std::make_unique<Impl>()) {}
MicrophoneCapture::~MicrophoneCapture() = default;
HRESULT MicrophoneCapture::Open(const std::wstring& id) { return impl_->Open(id, false); }
HRESULT MicrophoneCapture::Start() { return impl_->Start(); }
HRESULT MicrophoneCapture::Read(MicrophonePacket& packet) { return impl_->Read(packet); }
void MicrophoneCapture::Stop() { impl_->Stop(); }
struct SystemAudioCapture::Impl : AudioCapture {};
SystemAudioCapture::SystemAudioCapture() : impl_(std::make_unique<Impl>()) {}
SystemAudioCapture::~SystemAudioCapture() = default;
HRESULT SystemAudioCapture::Open() { return impl_->Open({}, true); }
HRESULT SystemAudioCapture::Start() { return impl_->Start(); }
HRESULT SystemAudioCapture::Read(SystemAudioPacket& packet) { return impl_->Read(packet); }
void SystemAudioCapture::Stop() { impl_->Stop(); }

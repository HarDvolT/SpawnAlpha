// Copyright 2026 SpawnAlpha. Added to the vendored camera_windows plugin,
// under the same BSD-style licence (see LICENSE).

#include "audio_input.h"

#include <audioclient.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <propidl.h>
#include <wrl/client.h>

#include <chrono>
#include <cmath>
#include <mutex>

#include "string_utils.h"

namespace camera_windows {

using Microsoft::WRL::ComPtr;

namespace {

// PKEY_Device_FriendlyName, defined here so no extra GUID library is needed.
const PROPERTYKEY kDeviceFriendlyName = {
    {0xa45c254e, 0xdf1c, 0x4efd, {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}},
    14};

std::mutex g_preferred_mutex;
std::wstring g_preferred_input;

float ToDb(double amplitude) {
  if (amplitude <= 0.00001) return -100.0f;
  return static_cast<float>(20.0 * std::log10(amplitude));
}

ComPtr<IMMDeviceEnumerator> CreateEnumerator() {
  ComPtr<IMMDeviceEnumerator> enumerator;
  CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                   IID_PPV_ARGS(&enumerator));
  return enumerator;
}

std::wstring DeviceId(IMMDevice* device) {
  LPWSTR id = nullptr;
  std::wstring result;
  if (SUCCEEDED(device->GetId(&id)) && id) {
    result = id;
    CoTaskMemFree(id);
  }
  return result;
}

std::wstring DeviceName(IMMDevice* device) {
  ComPtr<IPropertyStore> store;
  std::wstring result;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store))) return result;
  PROPVARIANT value;
  PropVariantInit(&value);
  if (SUCCEEDED(store->GetValue(kDeviceFriendlyName, &value)) &&
      value.vt == VT_LPWSTR && value.pwszVal) {
    result = value.pwszVal;
  }
  PropVariantClear(&value);
  return result;
}

}  // namespace

std::wstring DefaultAudioInputId() {
  ComPtr<IMMDeviceEnumerator> enumerator = CreateEnumerator();
  if (!enumerator) return L"";
  ComPtr<IMMDevice> device;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device))) {
    return L"";
  }
  return DeviceId(device.Get());
}

std::vector<AudioInputInfo> ListAudioInputs() {
  std::vector<AudioInputInfo> inputs;
  ComPtr<IMMDeviceEnumerator> enumerator = CreateEnumerator();
  if (!enumerator) return inputs;
  ComPtr<IMMDeviceCollection> collection;
  if (FAILED(enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE,
                                            &collection))) {
    return inputs;
  }
  const std::wstring default_id = DefaultAudioInputId();
  UINT count = 0;
  collection->GetCount(&count);
  for (UINT i = 0; i < count; ++i) {
    ComPtr<IMMDevice> device;
    if (FAILED(collection->Item(i, &device))) continue;
    AudioInputInfo info;
    info.id = DeviceId(device.Get());
    info.name = DeviceName(device.Get());
    info.is_default = !default_id.empty() && info.id == default_id;
    if (info.is_default) {
      inputs.insert(inputs.begin(), info);
    } else {
      inputs.push_back(info);
    }
  }
  return inputs;
}

void SetPreferredAudioInput(const std::wstring& id) {
  std::lock_guard<std::mutex> lock(g_preferred_mutex);
  g_preferred_input = id;
}

std::wstring PreferredAudioInput() {
  std::lock_guard<std::mutex> lock(g_preferred_mutex);
  return g_preferred_input;
}

// ---- AudioLevelMonitor ------------------------------------------------------

AudioLevelMonitor::~AudioLevelMonitor() { Stop(); }

void AudioLevelMonitor::Start(const std::wstring& id) {
  Stop();
  failed_ = false;
  peak_db_ = -100.0f;
  rms_db_ = -100.0f;
  running_ = true;
  thread_ = std::thread(&AudioLevelMonitor::Run, this, id);
}

void AudioLevelMonitor::Stop() {
  running_ = false;
  if (thread_.joinable()) thread_.join();
}

void AudioLevelMonitor::Run(std::wstring id) {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    HRESULT hr = S_OK;
    ComPtr<IMMDeviceEnumerator> enumerator = CreateEnumerator();
    ComPtr<IMMDevice> device;
    if (!enumerator) {
      hr = E_FAIL;
    } else if (id.empty()) {
      hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
    } else {
      hr = enumerator->GetDevice(id.c_str(), &device);
    }

    ComPtr<IAudioClient> client;
    if (SUCCEEDED(hr)) {
      hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                            reinterpret_cast<void**>(client.GetAddressOf()));
    }
    WAVEFORMATEX* format = nullptr;
    if (SUCCEEDED(hr)) hr = client->GetMixFormat(&format);
    // A 100 ms buffer, polled every 10 ms.
    if (SUCCEEDED(hr)) {
      hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 1000000, 0, format,
                              nullptr);
    }
    ComPtr<IAudioCaptureClient> capture;
    if (SUCCEEDED(hr)) hr = client->GetService(IID_PPV_ARGS(&capture));
    if (SUCCEEDED(hr)) hr = client->Start();

    if (FAILED(hr)) {
      failed_ = true;
    } else {
      // The shared-mode mix format is almost always 32-bit float; 16- and
      // 32-bit integer PCM are handled too. Extensible formats carry the
      // format tag in the first field of their sub-format GUID.
      WORD tag = format->wFormatTag;
      if (tag == WAVE_FORMAT_EXTENSIBLE) {
        tag = static_cast<WORD>(
            reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format)->SubFormat.Data1);
      }
      const bool is_float = tag == WAVE_FORMAT_IEEE_FLOAT;
      const WORD bits = format->wBitsPerSample;
      const UINT32 channels = format->nChannels;

      double sum = 0;
      float peak = 0;
      size_t samples = 0;
      auto window_start = std::chrono::steady_clock::now();
      while (running_ && SUCCEEDED(hr)) {
        Sleep(10);
        UINT32 packet = 0;
        hr = capture->GetNextPacketSize(&packet);
        while (SUCCEEDED(hr) && packet > 0) {
          BYTE* data = nullptr;
          UINT32 frames = 0;
          DWORD flags = 0;
          hr = capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
          if (FAILED(hr)) break;
          const UINT32 n = frames * channels;
          if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && data) {
            for (UINT32 i = 0; i < n; ++i) {
              float v = 0;
              if (is_float && bits == 32) {
                v = reinterpret_cast<float*>(data)[i];
              } else if (bits == 16) {
                v = reinterpret_cast<int16_t*>(data)[i] / 32768.0f;
              } else if (bits == 32) {
                v = static_cast<float>(reinterpret_cast<int32_t*>(data)[i] /
                                       2147483648.0);
              }
              const float a = std::fabs(v);
              if (a > peak) peak = a;
              sum += static_cast<double>(v) * v;
            }
          }
          samples += n;
          capture->ReleaseBuffer(frames);
          hr = capture->GetNextPacketSize(&packet);
        }
        const auto now = std::chrono::steady_clock::now();
        if (now - window_start >= std::chrono::milliseconds(50)) {
          rms_db_ = samples ? ToDb(std::sqrt(sum / samples)) : -100.0f;
          peak_db_ = ToDb(peak);
          sum = 0;
          peak = 0;
          samples = 0;
          window_start = now;
        }
      }
      client->Stop();
      if (FAILED(hr)) failed_ = true;
    }
    if (format) CoTaskMemFree(format);
  }
  if (SUCCEEDED(com)) CoUninitialize();
  running_ = false;
}

// ---- The method channel -----------------------------------------------------

// static
void AudioInputChannel::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(
      std::make_unique<AudioInputChannel>(registrar->messenger()));
}

AudioInputChannel::AudioInputChannel(flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "spawnalpha/audio_input",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        const auto* id_arg = std::get_if<std::string>(call.arguments());
        const std::wstring id = id_arg ? Utf16FromUtf8(*id_arg) : L"";
        if (method == "list") {
          flutter::EncodableList list;
          for (const AudioInputInfo& input : ListAudioInputs()) {
            list.push_back(flutter::EncodableValue(flutter::EncodableMap{
                {flutter::EncodableValue("id"),
                 flutter::EncodableValue(Utf8FromUtf16(input.id))},
                {flutter::EncodableValue("name"),
                 flutter::EncodableValue(Utf8FromUtf16(input.name))},
                {flutter::EncodableValue("default"),
                 flutter::EncodableValue(input.is_default)},
            }));
          }
          result->Success(flutter::EncodableValue(list));
        } else if (method == "select") {
          // Applies to cameras created from now on.
          SetPreferredAudioInput(id);
          result->Success();
        } else if (method == "startLevels") {
          monitor_.Start(id);
          result->Success();
        } else if (method == "stopLevels") {
          monitor_.Stop();
          result->Success();
        } else if (method == "level") {
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("peak"),
               flutter::EncodableValue(static_cast<double>(monitor_.peak_db()))},
              {flutter::EncodableValue("rms"),
               flutter::EncodableValue(static_cast<double>(monitor_.rms_db()))},
              {flutter::EncodableValue("failed"),
               flutter::EncodableValue(monitor_.failed())},
          }));
        } else {
          result->NotImplemented();
        }
      });
}

AudioInputChannel::~AudioInputChannel() { monitor_.Stop(); }

}  // namespace camera_windows

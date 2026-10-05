#include "recording_probe.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <winrt/base.h>
#include <algorithm>

RecordingInfo ProbeRecording(const std::wstring& path, const std::atomic<bool>& cancelled) {
  RecordingInfo info{};
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return info;
  const HRESULT media = MFStartup(MF_VERSION);
  if (SUCCEEDED(media)) {
    try {
      using winrt::check_hresult; using winrt::com_ptr;
      const DWORD video = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
      const DWORD audio = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
      const DWORD all = static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS);
      com_ptr<IMFAttributes> options;
      check_hresult(MFCreateAttributes(options.put(), 1));
      check_hresult(options->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
      com_ptr<IMFSourceReader> reader;
      check_hresult(MFCreateSourceReaderFromURL(path.c_str(), options.get(), reader.put()));
      com_ptr<IMFMediaType> native;
      info.has_audio = SUCCEEDED(reader->GetNativeMediaType(audio, 0, native.put()));
      native = nullptr;
      check_hresult(reader->SetStreamSelection(all, FALSE));
      check_hresult(reader->SetStreamSelection(video, TRUE));
      com_ptr<IMFMediaType> rgb;
      check_hresult(MFCreateMediaType(rgb.put()));
      check_hresult(rgb->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
      check_hresult(rgb->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
      check_hresult(reader->SetCurrentMediaType(video, nullptr, rgb.get()));
      bool decoded = false;
      while (!cancelled && !decoded) {
        DWORD flags = 0; com_ptr<IMFSample> sample;
        check_hresult(reader->ReadSample(video, 0, nullptr, &flags, nullptr, sample.put()));
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
        if (sample) {
          DWORD length = 0; check_hresult(sample->GetTotalLength(&length));
          decoded = length > 0;
        }
      }
      if (!decoded || cancelled) throw winrt::hresult_error(E_FAIL);
      com_ptr<IMFMediaType> current;
      check_hresult(reader->GetCurrentMediaType(video, current.put()));
      check_hresult(MFGetAttributeSize(current.get(), MF_MT_FRAME_SIZE, &info.width, &info.height));
      // H.264 decoder surfaces can be padded to macroblock dimensions. Report
      // the visible aperture, not the extra bottom/right padding in the surface.
      MFVideoArea aperture{};
      UINT32 aperture_size = 0;
      HRESULT area = current->GetBlob(MF_MT_MINIMUM_DISPLAY_APERTURE,
          reinterpret_cast<UINT8*>(&aperture), sizeof(aperture), &aperture_size);
      if (FAILED(area)) area = current->GetBlob(MF_MT_GEOMETRIC_APERTURE,
          reinterpret_cast<UINT8*>(&aperture), sizeof(aperture), &aperture_size);
      if (SUCCEEDED(area) && aperture_size == sizeof(aperture) && aperture.Area.cx > 0 && aperture.Area.cy > 0 &&
          static_cast<UINT>(aperture.Area.cx) <= info.width && static_cast<UINT>(aperture.Area.cy) <= info.height) {
        info.width = static_cast<UINT>(aperture.Area.cx); info.height = static_cast<UINT>(aperture.Area.cy);
      }
      PROPVARIANT duration{};
      if (SUCCEEDED(reader->GetPresentationAttribute(static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE),
          MF_PD_DURATION, &duration)) && duration.vt == VT_UI8 && duration.uhVal.QuadPart <= LLONG_MAX) {
        info.duration_100ns = static_cast<LONGLONG>(duration.uhVal.QuadPart);
      }
      PropVariantClear(&duration);
      if (info.duration_100ns <= 0) {
        // No movie duration after a crash. Read encoded samples without decoding
        // the whole video to find the last completed fragment's timestamp.
        reader = nullptr;
        check_hresult(MFCreateSourceReaderFromURL(path.c_str(), nullptr, reader.put()));
        check_hresult(reader->SetStreamSelection(all, FALSE));
        check_hresult(reader->SetStreamSelection(video, TRUE));
        while (!cancelled) {
          DWORD flags = 0; LONGLONG time = 0; com_ptr<IMFSample> sample;
          check_hresult(reader->ReadSample(video, 0, nullptr, &flags, &time, sample.put()));
          if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
          if (!sample) continue;
          LONGLONG length = 0;
          check_hresult(sample->GetSampleDuration(&length));
          if (time >= 0 && length > 0) info.duration_100ns = std::max(info.duration_100ns, time + length);
        }
      }
      info.readable = !cancelled && info.width > 0 && info.height > 0 && info.duration_100ns > 0;
    } catch (...) { info = {}; }  // Never log private paths or decoder details.
    MFShutdown();
  }
  CoUninitialize();
  return info;
}

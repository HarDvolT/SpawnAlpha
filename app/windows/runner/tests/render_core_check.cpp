// Explicit, non-shipping render-risk spike. Generates its own four-second
// H.264/AAC source, GPU-decodes two tracks, cuts/zooms/composites, re-encodes and
// decodes the result for verification. Never opens an owner recording/device.
#include "../gpu_video_writer.h"
#include <d3d11_4.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <winrt/base.h>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>

using winrt::com_ptr;
using winrt::check_hresult;
constexpr LONGLONG kSecond = 10000000;
constexpr DWORD kAllStreams = static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS);
constexpr DWORD kVideoStream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
constexpr DWORD kAudioStream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
constexpr UINT kWidth = 640, kHeight = 360, kRate = 48000;
void Require(bool value) { if (!value) throw winrt::hresult_error(E_FAIL); }

void Generate(ID3D11Device* device, const std::wstring& path) {
  GpuVideoWriter writer;
  check_hresult(writer.Start(device, path, kWidth, kHeight, 30, {kRate, 1}));
  const uint32_t colors[] = {0xffe03030, 0xff2040e0, 0xff30c050, 0xffe08020};
  for (UINT frame = 0; frame < 120; ++frame) {
    std::vector<uint32_t> pixels(kWidth * kHeight, colors[frame / 30]);
    for (UINT y = 0; y < kHeight; ++y) for (UINT x = 0; x < 80; ++x) pixels[y * kWidth + x] = 0xffffffff;
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = kWidth; desc.Height = kHeight; desc.MipLevels = 1; desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA data{pixels.data(), kWidth * 4, 0};
    com_ptr<ID3D11Texture2D> texture;
    check_hresult(device->CreateTexture2D(&desc, &data, texture.put()));
    check_hresult(writer.WriteFrame(texture.get(), kWidth, kHeight, frame * kSecond / 30));
    std::vector<int16_t> tone(kRate / 30);
    const double hz = (frame / 30 + 1) * 220.0;
    for (UINT index = 0; index < tone.size(); ++index) {
      const double phase = (frame * tone.size() + index) * hz * 6.283185307179586 / kRate;
      tone[index] = static_cast<int16_t>(std::sin(phase) * 12000);
    }
    check_hresult(writer.WriteAudio(tone.data(), static_cast<UINT>(tone.size()), frame * kSecond / 30));
  }
  check_hresult(writer.Finish());
}

struct GpuFrame { com_ptr<ID3D11Texture2D> texture; UINT slice = 0; };
class GpuReader {
 public:
  void Open(const std::wstring& path, IMFDXGIDeviceManager* manager) {
    com_ptr<IMFAttributes> options; check_hresult(MFCreateAttributes(options.put(), 3));
    check_hresult(options->SetUnknown(MF_SOURCE_READER_D3D_MANAGER, manager));
    check_hresult(options->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE));
    check_hresult(MFCreateSourceReaderFromURL(path.c_str(), options.get(), reader_.put()));
    check_hresult(reader_->SetStreamSelection(kAllStreams, FALSE));
    check_hresult(reader_->SetStreamSelection(kVideoStream, TRUE));
    com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
    check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
    check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12));
    check_hresult(reader_->SetCurrentMediaType(kVideoStream, nullptr, type.get()));
  }
  void Seek(LONGLONG time) {
    PROPVARIANT position{}; position.vt = VT_I8; position.hVal.QuadPart = time;
    check_hresult(reader_->SetCurrentPosition(GUID_NULL, position));
    sample_ = nullptr; time_ = -1;
  }
  GpuFrame At(LONGLONG wanted) {
    // Seek may start at an earlier keyframe. Decode through preroll; retain
    // the sample while its decoder texture is used by the compositor.
    // MP4 time-scale conversion may round a 30 Hz boundary by a fraction of a
    // microsecond. Treat that as the next frame, without reading past the last.
    while (!sample_ || time_ + duration_ <= wanted + 10) {
      DWORD flags = 0; sample_ = nullptr;
      check_hresult(reader_->ReadSample(kVideoStream, 0, nullptr, &flags, &time_, sample_.put()));
      Require(!(flags & MF_SOURCE_READERF_ENDOFSTREAM));
      if (sample_) {
        check_hresult(sample_->GetSampleDuration(&duration_));
        Require(duration_ > 0 && time_ <= wanted + duration_);
      }
    }
    com_ptr<IMFMediaBuffer> buffer; check_hresult(sample_->GetBufferByIndex(0, buffer.put()));
    const auto surface = buffer.as<IMFDXGIBuffer>();
    GpuFrame frame; check_hresult(surface->GetResource(__uuidof(ID3D11Texture2D), frame.texture.put_void()));
    check_hresult(surface->GetSubresourceIndex(&frame.slice));
    return frame;
  }
 private:
  com_ptr<IMFSourceReader> reader_;
  com_ptr<IMFSample> sample_;
  LONGLONG time_ = -1;
  LONGLONG duration_ = 0;
};

std::vector<int16_t> Audio(const std::wstring& path) {
  com_ptr<IMFSourceReader> reader;
  check_hresult(MFCreateSourceReaderFromURL(path.c_str(), nullptr, reader.put()));
  check_hresult(reader->SetStreamSelection(kAllStreams, FALSE));
  check_hresult(reader->SetStreamSelection(kAudioStream, TRUE));
  com_ptr<IMFMediaType> type; check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
  check_hresult(type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kRate));
  check_hresult(reader->SetCurrentMediaType(kAudioStream, nullptr, type.get()));
  // This check's source is bounded to four seconds. A shipping renderer must
  // stream bounded PCM packets instead of allocating for the full recording.
  std::vector<int16_t> pcm(kRate * 5);
  size_t last = 0;
  while (true) {
    DWORD flags = 0; LONGLONG time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kAudioStream, 0, nullptr, &flags, &time, sample.put()));
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (!sample) continue;
    com_ptr<IMFMediaBuffer> buffer; check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
    BYTE* bytes = nullptr; DWORD length = 0; check_hresult(buffer->Lock(&bytes, nullptr, &length));
    const auto values = reinterpret_cast<const int16_t*>(bytes);
    const auto first = static_cast<LONGLONG>(std::llround(static_cast<double>(time) * kRate / kSecond));
    for (DWORD index = 0; index < length / 2; ++index) {
      const auto position = first + index;
      if (position >= 0 && static_cast<size_t>(position) < pcm.size()) {
        pcm[static_cast<size_t>(position)] = values[index]; last = std::max(last, static_cast<size_t>(position + 1));
      }
    }
    check_hresult(buffer->Unlock());
  }
  pcm.resize(last); return pcm;
}

class Compositor {
 public:
  void Open(ID3D11Device* device) {
    device_.copy_from(device); device->GetImmediateContext(context_.put());
    video_ = device_.as<ID3D11VideoDevice>(); control_ = context_.as<ID3D11VideoContext1>();
    D3D11_VIDEO_PROCESSOR_CONTENT_DESC content{};
    content.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    content.InputWidth = content.OutputWidth = kWidth; content.InputHeight = content.OutputHeight = kHeight;
    content.InputFrameRate = content.OutputFrameRate = {30, 1};
    content.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
    check_hresult(video_->CreateVideoProcessorEnumerator(&content, enumerator_.put()));
    D3D11_VIDEO_PROCESSOR_CAPS caps{}; check_hresult(enumerator_->GetVideoProcessorCaps(&caps));
    Require(caps.MaxInputStreams >= 2);
    check_hresult(video_->CreateVideoProcessor(enumerator_.get(), 0, processor_.put()));
    control_->VideoProcessorSetOutputColorSpace1(processor_.get(), DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709);
    for (UINT stream = 0; stream < 2; ++stream) {
      control_->VideoProcessorSetStreamFrameFormat(processor_.get(), stream, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
      control_->VideoProcessorSetStreamColorSpace1(processor_.get(), stream, DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709);
      control_->VideoProcessorSetStreamAutoProcessingMode(processor_.get(), stream, FALSE);
    }
  }
  com_ptr<ID3D11Texture2D> Frame(const GpuFrame& screen, const GpuFrame& camera, UINT index) {
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = kWidth; desc.Height = kHeight; desc.MipLevels = 1; desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    com_ptr<ID3D11Texture2D> output; check_hresult(device_->CreateTexture2D(&desc, nullptr, output.put()));
    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC view{}; view.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
    com_ptr<ID3D11VideoProcessorOutputView> target;
    check_hresult(video_->CreateVideoProcessorOutputView(output.get(), enumerator_.get(), &view, target.put()));
    const GpuFrame frames[] = {screen, camera};
    com_ptr<ID3D11VideoProcessorInputView> inputs[2];
    D3D11_VIDEO_PROCESSOR_STREAM streams[2]{};
    const RECT sources[] = {{160, 90, 480, 270}, {0, 0, 640, 360}};
    const RECT destinations[] = {{0, 0, 640, 360}, {480, 240, 640, 360}};
    for (UINT stream = 0; stream < 2; ++stream) {
      D3D11_TEXTURE2D_DESC input_desc{}; frames[stream].texture->GetDesc(&input_desc);
      D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC input{}; input.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
      input.Texture2D.MipSlice = frames[stream].slice % input_desc.MipLevels;
      input.Texture2D.ArraySlice = frames[stream].slice / input_desc.MipLevels;
      check_hresult(video_->CreateVideoProcessorInputView(frames[stream].texture.get(), enumerator_.get(), &input, inputs[stream].put()));
      control_->VideoProcessorSetStreamSourceRect(processor_.get(), stream, TRUE, &sources[stream]);
      control_->VideoProcessorSetStreamDestRect(processor_.get(), stream, TRUE, &destinations[stream]);
      streams[stream].Enable = TRUE; streams[stream].pInputSurface = inputs[stream].get();
    }
    check_hresult(control_->VideoProcessorBlt(processor_.get(), target.get(), index, 2, streams));
    context_->Flush(); return output;
  }
 private:
  com_ptr<ID3D11Device> device_;
  com_ptr<ID3D11DeviceContext> context_;
  com_ptr<ID3D11VideoDevice> video_;
  com_ptr<ID3D11VideoContext1> control_;
  com_ptr<ID3D11VideoProcessorEnumerator> enumerator_;
  com_ptr<ID3D11VideoProcessor> processor_;
};

double ToneAt(const std::vector<int16_t>& pcm, size_t first, double hz) {
  Require(pcm.size() > first + 12000);
  double real = 0, imaginary = 0;
  for (size_t index = 0; index < 12000; ++index) {
    const double phase = index * hz * 6.283185307179586 / kRate;
    real += pcm[first + index] * std::cos(phase); imaginary += pcm[first + index] * std::sin(phase);
  }
  return 2 * std::sqrt(real * real + imaginary * imaginary) / 12000;
}
void Verify(const std::wstring& path, const char*& stage) {
  com_ptr<IMFAttributes> options; check_hresult(MFCreateAttributes(options.put(), 1));
  check_hresult(options->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
  com_ptr<IMFSourceReader> reader; check_hresult(MFCreateSourceReaderFromURL(path.c_str(), options.get(), reader.put()));
  com_ptr<IMFMediaType> rgb; check_hresult(MFCreateMediaType(rgb.put()));
  check_hresult(rgb->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)); check_hresult(rgb->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
  check_hresult(reader->SetCurrentMediaType(kVideoStream, nullptr, rgb.get()));
  UINT frames = 0;
  LONGLONG previous = -1;
  while (true) {
    DWORD flags = 0; LONGLONG time = 0; com_ptr<IMFSample> sample;
    check_hresult(reader->ReadSample(kVideoStream, 0, nullptr, &flags, &time, sample.put()));
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (!sample) continue;
    stage = "verify cut timestamps";
    // Container time-scale rounding is allowed within 1 ms; order and cadence
    // must remain exact at the frame level, including the splice at frame 30.
    Require(time > previous && std::abs(time - frames * kSecond / 30) <= kSecond / 1000);
    previous = time;
    com_ptr<IMFMediaBuffer> buffer; check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
    BYTE* pixels = nullptr; DWORD length = 0; check_hresult(buffer->Lock(&pixels, nullptr, &length));
    const size_t main = (20 * kWidth + 10) * 4, inset = (280 * kWidth + 488) * 4;
    bool colors = length >= kWidth * kHeight * 4;
    if (colors) {
      colors = frames < 30 ? pixels[main] > pixels[main + 2] + 80 : pixels[main + 2] > pixels[main] + 80;
      colors = colors && pixels[inset] > 220 && pixels[inset + 1] > 220 && pixels[inset + 2] > 220;
    }
    check_hresult(buffer->Unlock()); stage = "verify cut zoom and inset pixels"; Require(colors); ++frames;
  }
  stage = "verify cut frame count"; Require(frames == 60);
  const auto audio = Audio(path);
  stage = "verify cut audio length"; Require(audio.size() >= 94000 && audio.size() <= 100000);
  stage = "verify cut selected audio tones";
  Require(ToneAt(audio, 12000, 440) > 9000 && ToneAt(audio, 60000, 880) > 9000);
  Require(ToneAt(audio, 12000, 220) < 1500 && ToneAt(audio, 60000, 660) < 1500);
}

int wmain(int count, wchar_t** args) {
  if (count != 2) return 2;
  const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED); if (FAILED(com)) return 3;
  const char* stage = "create GPU";
  try {
    check_hresult(MFStartup(MF_VERSION));
    double elapsed = 0;
    {
      com_ptr<ID3D11Device> device; com_ptr<ID3D11DeviceContext> context;
      check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
          nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
      context.as<ID3D11Multithread>()->SetMultithreadProtected(TRUE);
      const std::wstring input = std::wstring(args[1]) + L"-source.mp4", output = std::wstring(args[1]) + L"-cut.mp4";
      stage = "generate source"; Generate(device.get(), input);
      LARGE_INTEGER start{}, finish{}, hz{}; QueryPerformanceCounter(&start); QueryPerformanceFrequency(&hz);
      UINT token = 0; com_ptr<IMFDXGIDeviceManager> manager;
      check_hresult(MFCreateDXGIDeviceManager(&token, manager.put())); check_hresult(manager->ResetDevice(device.get(), token));
      GpuReader screen, camera;
      stage = "GPU decode"; screen.Open(input, manager.get()); camera.Open(input, manager.get());
      const auto audio = Audio(input); Require(audio.size() >= kRate * 4);
      Compositor compositor; stage = "two-track GPU compositor"; compositor.Open(device.get());
      GpuVideoWriter writer; check_hresult(writer.Start(device.get(), output, kWidth, kHeight, 30, {kRate, 1}));
      // Renderer-independent range semantics: keep [1s,2s), then [3s,4s).
      // Presentation and sound restart at zero and have no gap at the join.
      for (UINT frame = 0; frame < 60; ++frame) {
        const UINT source_frame = frame < 30 ? frame + 30 : frame + 60;
        const auto time = source_frame * kSecond / 30;
        if (frame == 0 || frame == 30) { screen.Seek(time); camera.Seek(time); }
        stage = "decode selected screen frame"; const auto screen_frame = screen.At(time);
        stage = "decode selected camera frame"; const auto camera_frame = camera.At(time);
        stage = "compose GPU views"; const auto image = compositor.Frame(screen_frame, camera_frame, frame);
        stage = "encode composed video";
        check_hresult(writer.WriteFrame(image.get(), kWidth, kHeight, frame * kSecond / 30));
        stage = "encode selected audio";
        check_hresult(writer.WriteAudio(audio.data() + source_frame * (kRate / 30), kRate / 30, frame * kSecond / 30));
      }
      check_hresult(writer.Finish()); QueryPerformanceCounter(&finish);
      stage = "decode and verify cut"; Verify(output, stage);
      elapsed = double(finish.QuadPart - start.QuadPart) / hz.QuadPart;
    }
    std::cout << "Render core check passed: GPU NV12 decode, two-track zoom/inset, two source ranges, 60 ordered H.264 frames, matching cut AAC tones.\n";
    std::cout << "Rendered 2 seconds in " << elapsed << " seconds on this PC.\n";
    MFShutdown(); CoUninitialize(); return 0;
  } catch (...) {
    std::cerr << "Render core check failed at " << stage << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    MFShutdown(); CoUninitialize(); return 1;
  }
}

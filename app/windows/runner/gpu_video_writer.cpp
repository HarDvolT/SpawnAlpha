#include "gpu_video_writer.h"
#include <d3d11_4.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <codecapi.h>
#include <icodecapi.h>
#include <winrt/base.h>
#include <algorithm>
#include <cstring>

namespace {
using winrt::com_ptr;
using winrt::check_hresult;

com_ptr<IMFMediaType> VideoType(GUID subtype, UINT width, UINT height, UINT fps) {
  com_ptr<IMFMediaType> type;
  check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
  check_hresult(type->SetGUID(MF_MT_SUBTYPE, subtype));
  check_hresult(type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive));
  check_hresult(MFSetAttributeSize(type.get(), MF_MT_FRAME_SIZE, width, height));
  check_hresult(MFSetAttributeRatio(type.get(), MF_MT_FRAME_RATE, fps, 1));
  check_hresult(MFSetAttributeRatio(type.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1));
  check_hresult(type->SetUINT32(MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709));
  check_hresult(type->SetUINT32(MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709));
  check_hresult(type->SetUINT32(MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709));
  check_hresult(type->SetUINT32(MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235));
  return type;
}

com_ptr<IMFMediaType> AudioType(GUID subtype, const GpuAudioFormat& audio) {
  com_ptr<IMFMediaType> type;
  check_hresult(MFCreateMediaType(type.put()));
  check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
  check_hresult(type->SetGUID(MF_MT_SUBTYPE, subtype));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, audio.sample_rate));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, audio.channels));
  check_hresult(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16));
  if (subtype == MFAudioFormat_AAC) {
    check_hresult(type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 20000));
    check_hresult(type->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 0));
    check_hresult(type->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x29));
  } else {
    check_hresult(type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, audio.channels * 2));
    check_hresult(type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, audio.sample_rate * audio.channels * 2));
    check_hresult(type->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE));
  }
  return type;
}
}  // namespace

struct GpuVideoWriter::Impl {
  ~Impl() { Finish(); }
  HRESULT Start(ID3D11Device* given_device, const std::wstring& path, UINT given_width, UINT given_height, UINT given_fps,
                const GpuAudioFormat& given_audio, bool* created_file, bool fragmented) {
    if (created_file) *created_file = false;
    if (writer || started) return MF_E_INVALIDREQUEST;
    if (!given_device || path.empty() || given_width < 2 || given_height < 2 ||
        given_width > 4096 || given_height > 4096 || given_width % 2 || given_height % 2 ||
        given_fps == 0 || given_fps > 60) return E_INVALIDARG;
    if ((given_audio.sample_rate != 0 || given_audio.channels != 0) &&
        ((given_audio.sample_rate != 44100 && given_audio.sample_rate != 48000) ||
         (given_audio.channels != 1 && given_audio.channels != 2))) return E_INVALIDARG;
    try {
      check_hresult(MFStartup(MF_VERSION));
      started = true;
      device.copy_from(given_device);
      width = given_width; height = given_height; fps = given_fps;
      audio = given_audio;
      device->GetImmediateContext(context.put());
      const auto multithread = context.as<ID3D11Multithread>();
      multithread->SetMultithreadProtected(TRUE);
      video_device = device.as<ID3D11VideoDevice>();
      video_context = context.as<ID3D11VideoContext1>();
      UINT reset = 0;
      check_hresult(MFCreateDXGIDeviceManager(&reset, manager.put()));
      check_hresult(manager->ResetDevice(device.get(), reset));
      check_hresult(MFCreateFile(MF_ACCESSMODE_READWRITE, MF_OPENMODE_FAIL_IF_EXIST,
          MF_FILEFLAGS_NONE, path.c_str(), bytes.put()));
      if (created_file) *created_file = true;
      const auto output = VideoType(MFVideoFormat_H264, width, height, fps);
      const UINT64 bits = static_cast<UINT64>(width) * height * fps / 6;
      check_hresult(output->SetUINT32(MF_MT_AVG_BITRATE, static_cast<UINT32>(std::clamp<UINT64>(bits, 2000000, 16000000))));
      // Baseline forbids B-frames, keeping decode/presentation timestamps ordered.
      check_hresult(output->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Base));
      const auto audio_output = audio.sample_rate ? AudioType(MFAudioFormat_AAC, audio) : com_ptr<IMFMediaType>{};
      check_hresult(fragmented
        ? MFCreateFMPEG4MediaSink(bytes.get(), output.get(), audio_output.get(), sink.put())
        : MFCreateMPEG4MediaSink(bytes.get(), output.get(), audio_output.get(), sink.put()));
      com_ptr<IMFAttributes> attributes;
      check_hresult(MFCreateAttributes(attributes.put(), 4));
      check_hresult(attributes->SetUnknown(MF_SINK_WRITER_D3D_MANAGER, manager.get()));
      check_hresult(attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE));
      check_hresult(attributes->SetUINT32(MF_LOW_LATENCY, TRUE));
      check_hresult(MFCreateSinkWriterFromMediaSink(sink.get(), attributes.get(), writer.put()));
      check_hresult(writer->SetInputMediaType(0, VideoType(MFVideoFormat_NV12, width, height, fps).get(), nullptr));
      if (audio.sample_rate) {
        check_hresult(writer->SetInputMediaType(1, AudioType(MFAudioFormat_PCM, audio).get(), nullptr));
      }
      com_ptr<ICodecAPI> codec;
      if (SUCCEEDED(writer->GetServiceForStream(0, GUID_NULL, IID_PPV_ARGS(codec.put())))) {
        VARIANT gop{}; gop.vt = VT_UI4; gop.ulVal = fps;
        // Optional driver setting: shorter GOPs allow completed fragments sooner.
        codec->SetValue(&CODECAPI_AVEncMPVGOPSize, &gop);
      }
      check_hresult(writer->BeginWriting());
      writing = true;
      last_time = -1;
      audio_end = -1;
      return S_OK;
    } catch (...) { const HRESULT error = winrt::to_hresult(); Finish(); return error; }
  }

  void PrepareInput(ID3D11Texture2D* source, UINT content_width, UINT content_height) {
    D3D11_TEXTURE2D_DESC desc{};
    source->GetDesc(&desc);
    if (desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM || desc.ArraySize != 1 || desc.SampleDesc.Count != 1 ||
        content_width == 0 || content_height == 0 || content_width > desc.Width || content_height > desc.Height) {
      throw winrt::hresult_error(E_INVALIDARG);
    }
    com_ptr<ID3D11Device> source_device;
    source->GetDevice(source_device.put());
    if (source_device.get() != device.get()) throw winrt::hresult_error(E_INVALIDARG);
    if (!input || input_width != desc.Width || input_height != desc.Height) {
      input = nullptr; enumerator = nullptr; processor = nullptr;
      D3D11_VIDEO_PROCESSOR_CONTENT_DESC content{};
      content.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
      content.InputFrameRate = {fps, 1}; content.OutputFrameRate = {fps, 1};
      content.InputWidth = desc.Width; content.InputHeight = desc.Height;
      content.OutputWidth = width; content.OutputHeight = height;
      content.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
      check_hresult(video_device->CreateVideoProcessorEnumerator(&content, enumerator.put()));
      check_hresult(video_device->CreateVideoProcessor(enumerator.get(), 0, processor.put()));
      desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
      desc.Usage = D3D11_USAGE_DEFAULT; desc.CPUAccessFlags = 0; desc.MiscFlags = 0; desc.MipLevels = 1;
      check_hresult(device->CreateTexture2D(&desc, nullptr, input.put()));
      input_width = desc.Width; input_height = desc.Height;
    }
    context->CopyResource(input.get(), source);
    const RECT source_rect{0, 0, static_cast<LONG>(content_width), static_cast<LONG>(content_height)};
    const double scale = std::min(static_cast<double>(width) / content_width, static_cast<double>(height) / content_height);
    // Chroma is subsampled; fit to even pixel bounds inside the fixed video frame.
    const LONG fitted_width = std::max<LONG>(2, static_cast<LONG>(content_width * scale) / 2 * 2);
    const LONG fitted_height = std::max<LONG>(2, static_cast<LONG>(content_height * scale) / 2 * 2);
    const LONG x = static_cast<LONG>(width - fitted_width) / 4 * 2;
    const LONG y = static_cast<LONG>(height - fitted_height) / 4 * 2;
    const RECT destination{x, y, x + fitted_width, y + fitted_height};
    const RECT target{0, 0, static_cast<LONG>(width), static_cast<LONG>(height)};
    video_context->VideoProcessorSetStreamFrameFormat(processor.get(), 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
    video_context->VideoProcessorSetStreamSourceRect(processor.get(), 0, TRUE, &source_rect);
    video_context->VideoProcessorSetStreamDestRect(processor.get(), 0, TRUE, &destination);
    video_context->VideoProcessorSetOutputTargetRect(processor.get(), TRUE, &target);
    video_context->VideoProcessorSetStreamColorSpace1(processor.get(), 0, DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709);
    video_context->VideoProcessorSetOutputColorSpace1(processor.get(), DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709);
    const D3D11_VIDEO_COLOR black{};
    video_context->VideoProcessorSetOutputBackgroundColor(processor.get(), FALSE, &black);
  }

  HRESULT WriteFrame(ID3D11Texture2D* source, UINT content_width, UINT content_height, LONGLONG time, LONGLONG duration) {
    if (!writing || !source || time < 0 || time <= last_time || duration < 0 || duration > 10000000LL) return E_INVALIDARG;
    try {
      PrepareInput(source, content_width, content_height);
      D3D11_TEXTURE2D_DESC desc{};
      desc.Width = width; desc.Height = height; desc.MipLevels = 1; desc.ArraySize = 1;
      desc.Format = DXGI_FORMAT_NV12; desc.SampleDesc.Count = 1;
      desc.Usage = D3D11_USAGE_DEFAULT; desc.BindFlags = D3D11_BIND_RENDER_TARGET;
      com_ptr<ID3D11Texture2D> output;
      check_hresult(device->CreateTexture2D(&desc, nullptr, output.put()));
      D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC input_desc{};
      input_desc.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
      com_ptr<ID3D11VideoProcessorInputView> input_view;
      check_hresult(video_device->CreateVideoProcessorInputView(input.get(), enumerator.get(), &input_desc, input_view.put()));
      D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC output_desc{};
      output_desc.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
      com_ptr<ID3D11VideoProcessorOutputView> output_view;
      check_hresult(video_device->CreateVideoProcessorOutputView(output.get(), enumerator.get(), &output_desc, output_view.put()));
      D3D11_VIDEO_PROCESSOR_STREAM stream{};
      stream.Enable = TRUE; stream.pInputSurface = input_view.get();
      check_hresult(video_context->VideoProcessorBlt(processor.get(), output_view.get(), static_cast<UINT>(frames), 1, &stream));
      context->Flush();
      com_ptr<IMFMediaBuffer> buffer;
      check_hresult(MFCreateDXGISurfaceBuffer(__uuidof(ID3D11Texture2D), output.get(), 0, FALSE, buffer.put()));
      DWORD length = 0;
      check_hresult(buffer.as<IMF2DBuffer>()->GetContiguousLength(&length));
      check_hresult(buffer->SetCurrentLength(length));
      com_ptr<IMFSample> sample;
      check_hresult(MFCreateSample(sample.put()));
      check_hresult(sample->AddBuffer(buffer.get()));
      check_hresult(sample->SetSampleTime(time));
      check_hresult(sample->SetSampleDuration(duration ? duration : 10000000LL / fps));
      check_hresult(writer->WriteSample(0, sample.get()));
      last_time = time; ++frames;
      return S_OK;
    } catch (...) { return winrt::to_hresult(); }
  }

  HRESULT WriteAudio(const int16_t* pcm, UINT count, LONGLONG time) {
    if (!writing || !audio.sample_rate || !pcm || count == 0 || count > audio.sample_rate ||
        time < 0 || time < audio_end) return E_INVALIDARG;
    try {
      const DWORD length = count * audio.channels * sizeof(int16_t);
      com_ptr<IMFMediaBuffer> buffer;
      check_hresult(MFCreateMemoryBuffer(length, buffer.put()));
      BYTE* destination = nullptr;
      check_hresult(buffer->Lock(&destination, nullptr, nullptr));
      std::memcpy(destination, pcm, length);
      check_hresult(buffer->Unlock());
      check_hresult(buffer->SetCurrentLength(length));
      com_ptr<IMFSample> sample;
      check_hresult(MFCreateSample(sample.put()));
      check_hresult(sample->AddBuffer(buffer.get()));
      const LONGLONG duration = static_cast<LONGLONG>(count) * 10000000LL / audio.sample_rate;
      check_hresult(sample->SetSampleTime(time));
      check_hresult(sample->SetSampleDuration(duration));
      check_hresult(writer->WriteSample(1, sample.get()));
      audio_end = time + duration;
      return S_OK;
    } catch (...) { return winrt::to_hresult(); }
  }

  HRESULT Finish() {
    HRESULT result = S_OK;
    if (writer && writing) result = writer->Finalize();
    writing = false;
    writer = nullptr;
    if (sink) {
      const HRESULT closed = sink->Shutdown();
      if (SUCCEEDED(result) && FAILED(closed)) result = closed;
    }
    sink = nullptr;
    // The sink normally already closed its stream during Shutdown. Close again
    // only for failed startup; an already-closed stream can return E_INVALIDARG.
    if (bytes) bytes->Close();
    bytes = nullptr;
    processor = nullptr; enumerator = nullptr; input = nullptr;
    video_context = nullptr; video_device = nullptr; context = nullptr; manager = nullptr; device = nullptr;
    input_width = input_height = 0; frames = 0;
    audio = {}; audio_end = -1;
    if (started) { MFShutdown(); started = false; }
    return result;
  }
  bool started = false, writing = false;
  UINT width = 0, height = 0, fps = 30, input_width = 0, input_height = 0;
  UINT64 frames = 0;
  LONGLONG last_time = -1;
  LONGLONG audio_end = -1;
  GpuAudioFormat audio{};
  com_ptr<ID3D11Device> device;
  com_ptr<ID3D11DeviceContext> context;
  com_ptr<ID3D11VideoDevice> video_device;
  com_ptr<ID3D11VideoContext1> video_context;
  com_ptr<ID3D11VideoProcessorEnumerator> enumerator;
  com_ptr<ID3D11VideoProcessor> processor;
  com_ptr<ID3D11Texture2D> input;
  com_ptr<IMFDXGIDeviceManager> manager;
  com_ptr<IMFByteStream> bytes;
  com_ptr<IMFMediaSink> sink;
  com_ptr<IMFSinkWriter> writer;
};
GpuVideoWriter::GpuVideoWriter() : impl_(std::make_unique<Impl>()) {}
GpuVideoWriter::~GpuVideoWriter() = default;
HRESULT GpuVideoWriter::Start(ID3D11Device* device, const std::wstring& path, UINT width, UINT height, UINT fps,
                              const GpuAudioFormat& audio, bool* created_file, bool fragmented) {
  return impl_->Start(device, path, width, height, fps, audio, created_file, fragmented);
}
HRESULT GpuVideoWriter::WriteAudio(const int16_t* pcm, UINT frames, LONGLONG time) {
  return impl_->WriteAudio(pcm, frames, time);
}
HRESULT GpuVideoWriter::WriteFrame(ID3D11Texture2D* source, UINT width, UINT height, LONGLONG time, LONGLONG duration) {
  return impl_->WriteFrame(source, width, height, time, duration);
}
HRESULT GpuVideoWriter::Finish() { return impl_->Finish(); }

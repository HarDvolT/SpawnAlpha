#ifndef RUNNER_GPU_VIDEO_WRITER_H_
#define RUNNER_GPU_VIDEO_WRITER_H_
#include <d3d11.h>
#include <memory>
#include <string>
#include <cstdint>

struct GpuAudioFormat {
  // Zero means an explicitly silent video. AAC accepts 44.1/48 kHz, mono/stereo.
  UINT sample_rate = 0;
  UINT channels = 0;
};

// Platform H.264 in fragmented recording MP4 or finalized export MP4.
// Call from a COM-initialized thread and
// serialize calls. Each encoded sample owns its own GPU surface until released.
class GpuVideoWriter {
 public:
  GpuVideoWriter();
  ~GpuVideoWriter();
  HRESULT Start(ID3D11Device* device, const std::wstring& path,
                UINT width, UINT height, UINT fps = 30,
                const GpuAudioFormat& audio = {}, bool* created_file = nullptr,
                bool fragmented = true);
  HRESULT WriteFrame(ID3D11Texture2D* source, UINT content_width,
                     UINT content_height, LONGLONG time_100ns, LONGLONG duration_100ns = 0);
  HRESULT WriteAudio(const int16_t* pcm, UINT frames, LONGLONG time_100ns);
  HRESULT Finish(bool finalize = true);
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

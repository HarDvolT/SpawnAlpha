#ifndef RUNNER_CAPTION_OVERLAY_H_
#define RUNNER_CAPTION_OVERLAY_H_
#include <d3d11.h>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
struct RenderCaptionWord {
  UINT offset = 0, length = 0;
  int64_t start_us = 0, end_us = 0;
};
struct RenderCaption {
  int64_t start_us = 0, end_us = 0;
  std::wstring text;
  std::vector<RenderCaptionWord> words;
};
struct CaptionLayout {
  bool rtl = false;
  double edge = 0, bottom = 0, safe_top = 0, safe_bottom = 0, safe_right = 0;
  double font_size = 0, line_height = 0, min_size = 0;
  double padding = 0, radius = 0, shadow_offset = 0;
  uint32_t text_color = 0, plate_color = 0;
  UINT weight = 0;
  bool karaoke = false;
  uint32_t waiting_color = 0, underline_color = 0;
  double underline_size = 0, underline_gap = 0;
};
// Worker-only, bounded one-phrase layout. DirectWrite shapes bundled fonts and
// Direct2D composites onto the owned GPU frame. No system font installation.
class CaptionOverlay {
 public:
  CaptionOverlay();
  ~CaptionOverlay();
  void Open(ID3D11Device*, UINT width, UINT height, int64_t duration_us,
            const std::vector<RenderCaption>&, const CaptionLayout&);
  void Draw(ID3D11Texture2D*, int64_t output_us);
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif

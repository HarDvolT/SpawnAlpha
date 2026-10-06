#ifndef RUNNER_LOCAL_RENDER_H_
#define RUNNER_LOCAL_RENDER_H_
#include <windows.h>
#include <atomic>
#include <functional>
#include <string>
#include <vector>
#include "caption_overlay.h"
#include "screen_zoom.h"
#include "click_overlay.h"
struct RenderRange { int64_t start_us, end_us; };
struct LocalRenderRequest {
  std::wstring source, camera, output;
  int64_t source_duration_us = 0;
  UINT width = 1920, height = 1080;
  std::vector<RenderRange> ranges;
  double camera_inset = 0, camera_margin = 0;
  std::vector<RenderCaption> captions;
  CaptionLayout caption_layout;
  int64_t audio_join_fade_us = 0;
  std::vector<ScreenZoomStep> zoom_steps;
  ZoomSpring zoom_spring;
  std::vector<RenderClick> click_pulses;
  ClickLayout click_layout;
};
// COM/MF initialized worker only. Original media is read-only, packets are bounded,
// output is created exclusively, and failure/cancellation removes only that output.
void RenderLocalVideo(const LocalRenderRequest&, std::atomic<bool>&,
                      const std::function<void(double)>&);
#endif

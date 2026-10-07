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
#include "screen_frame.h"
#include "camera_placement.h"
#include "screen_motion_blur.h"
struct RenderRange { int64_t start_us, end_us; };
struct CameraPunchStep { int64_t time_us = 0; bool zoomed = false; };
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
  std::vector<RenderCaption> shortcut_badges;
  CaptionLayout shortcut_layout;
  ScreenFrameLayout screen_frame;
  std::vector<CameraPunchStep> punch_steps;
  bool punch_main = false;
  double punch_factor = 0;
  ZoomSpring punch_spring;
  std::vector<CameraTarget> camera_targets;
  CameraClearLayout camera_clear;
  ScreenBlurLayout screen_blur;
};
// COM/MF initialized worker only. Original media is read-only, packets are bounded,
// output is created exclusively, and failure/cancellation removes only that output.
void RenderLocalVideo(const LocalRenderRequest&, std::atomic<bool>&,
                      const std::function<void(double)>&);
#endif

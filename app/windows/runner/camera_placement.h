#ifndef RUNNER_CAMERA_PLACEMENT_H_
#define RUNNER_CAMERA_PLACEMENT_H_
#include "screen_zoom.h"

struct CameraTarget {
  int64_t start_us = 0, end_us = 0;
  double x = 0, y = 0;
  UINT width = 0, height = 0;
};
struct CameraClearLayout {
  bool enabled = false;
  double gap = 0;
  int64_t interval_us = 0;
  ZoomSpring spring;
};

// Only output geometry and saved anonymous targets. No device/input access.
class CameraPlacement {
 public:
  void Open(const std::vector<CameraTarget>& targets,
      const std::vector<ScreenZoomStep>& zooms, const CameraClearLayout& layout,
      int64_t duration_us, UINT width, UINT height) {
    if (!layout.enabled) { Require(targets.empty()); return; }
    Require(targets.size() <= 20000 && width > 0 && height > 0 &&
      Finite(layout.gap, 0, 100) && layout.interval_us >= 100000 && layout.interval_us <= 10000000 &&
      Finite(layout.spring.mass, .1, 10) && Finite(layout.spring.stiffness, 1, 1000) && Finite(layout.spring.damping, 1, 200));
    int64_t end = 0;
    for (const auto& target : targets) {
      Require(target.start_us >= end && target.end_us > target.start_us && target.end_us <= duration_us &&
        Finite(target.x, 0, 1) && Finite(target.y, 0, 1) &&
        target.width > 0 && target.width <= 100000 && target.height > 0 && target.height <= 100000);
      end = target.end_us;
    }
    targets_ = targets; zooms_ = zooms; layout_ = layout;
    gap_ = layout.gap * std::min(width, height) / 1080.0;
  }
  void Reset(int64_t output_us) {
    position_ = target_ = 1; velocity_ = 0; updated_us_ = output_us;
    last_move_us_ = output_us - layout_.interval_us;
    while (next_ < targets_.size() && targets_[next_].end_us <= output_us) ++next_;
    while (zoom_next_ < zooms_.size() && zooms_[zoom_next_].time_us < output_us) ++zoom_next_;
    zoom_active_ = false;
  }
  RECT Place(int64_t output_us, const RECT& main, const RECT& crop,
      const RECT& picture, const RECT& camera, LONG left_margin) {
    if (!layout_.enabled) return camera;
    Require(output_us >= updated_us_);
    Advance(static_cast<double>(output_us - updated_us_) / 1000000);
    updated_us_ = output_us;
    while (next_ < targets_.size() && targets_[next_].end_us <= output_us) ++next_;
    while (zoom_next_ < zooms_.size() && zooms_[zoom_next_].time_us <= output_us) {
      active_zoom_ = zooms_[zoom_next_++]; zoom_active_ = active_zoom_.factor > 1;
    }
    const LONG width = camera.right - camera.left;
    const RECT left{left_margin, camera.top, left_margin + width, camera.bottom};
    int left_score = 0, right_score = 0;
    const auto protect = [&](double x, double y, UINT sw, UINT sh) {
      const double mw = main.right - main.left, mh = main.bottom - main.top;
      const double fit = std::min(mw / sw, mh / sh);
      const double sx = main.left + (mw - sw * fit) / 2 + x * sw * fit;
      const double sy = main.top + (mh - sh * fit) / 2 + y * sh * fit;
      if (sx < crop.left || sx > crop.right || sy < crop.top || sy > crop.bottom) return;
      const double px = picture.left + (sx - crop.left) * (picture.right - picture.left) / (crop.right - crop.left);
      const double py = picture.top + (sy - crop.top) * (picture.bottom - picture.top) / (crop.bottom - crop.top);
      const auto covered = [&](const RECT& box) {
        return px >= box.left - gap_ && px <= box.right + gap_ && py >= box.top - gap_ && py <= box.bottom + gap_;
      };
      left_score += covered(left) ? 1 : 0; right_score += covered(camera) ? 1 : 0;
    };
    if (next_ < targets_.size() && targets_[next_].start_us <= output_us) {
      const auto& t = targets_[next_]; protect(t.x, t.y, t.width, t.height);
    }
    if (zoom_active_) protect(active_zoom_.x, active_zoom_.y, active_zoom_.width, active_zoom_.height);
    const auto current = target_ > .5 ? right_score : left_score;
    const auto alternative = target_ > .5 ? left_score : right_score;
    if (alternative < current && output_us - last_move_us_ >= layout_.interval_us) {
      target_ = 1 - target_; last_move_us_ = output_us;
    }
    const auto x = static_cast<LONG>(std::llround(left.left +
      std::clamp(position_, 0.0, 1.0) * (camera.left - left.left)));
    return {x, camera.top, x + width, camera.bottom};
  }
 private:
  static void Require(bool value) { if (!value) throw std::runtime_error("Invalid camera placement"); }
  static bool Finite(double v, double low, double high) { return std::isfinite(v) && v >= low && v <= high; }
  void Advance(double time) {
    const auto a = layout_.spring.damping / (2 * layout_.spring.mass);
    const auto omega = layout_.spring.stiffness / layout_.spring.mass;
    const auto delta = a * a - omega, offset = position_ - target_;
    double p = 0, v = 0;
    if (std::abs(delta) < 1e-8) {
      const auto c = velocity_ + a * offset, e = std::exp(-a * time);
      p = e * (offset + c * time); v = e * (c - a * (offset + c * time));
    } else if (delta > 0) {
      const auto b = std::sqrt(delta), first = -a + b, second = -a - b;
      const auto c1 = (velocity_ - second * offset) / (first - second), c2 = offset - c1;
      p = c1 * std::exp(first * time) + c2 * std::exp(second * time);
      v = first * c1 * std::exp(first * time) + second * c2 * std::exp(second * time);
    } else {
      const auto b = std::sqrt(-delta), c = (velocity_ + a * offset) / b;
      const auto e = std::exp(-a * time), cosine = std::cos(b * time), sine = std::sin(b * time);
      p = e * (offset * cosine + c * sine);
      v = e * ((-a * offset + b * c) * cosine + (-a * c - b * offset) * sine);
    }
    position_ = target_ + p; velocity_ = v;
  }
  CameraClearLayout layout_;
  std::vector<CameraTarget> targets_;
  std::vector<ScreenZoomStep> zooms_;
  ScreenZoomStep active_zoom_;
  size_t next_ = 0, zoom_next_ = 0;
  bool zoom_active_ = false;
  double position_ = 1, velocity_ = 0, target_ = 1, gap_ = 0;
  int64_t updated_us_ = 0, last_move_us_ = 0;
};
#endif

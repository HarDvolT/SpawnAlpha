#ifndef RUNNER_SCREEN_ZOOM_H_
#define RUNNER_SCREEN_ZOOM_H_
#include <windows.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

struct ScreenZoomStep {
  int64_t time_us = 0;
  double x = .5, y = .5, factor = 1;
  UINT width = 0, height = 0;
};
struct ZoomSpring {
  double mass = 0, stiffness = 0, damping = 0;
};
struct ZoomViewport { double left, top, right, bottom; };

class ScreenZoom {
 public:
  void Open(const std::vector<ScreenZoomStep>& steps, const ZoomSpring& spring,
      UINT width, UINT height, int64_t duration_us) {
    if (steps.empty()) return;
    Require(steps.size() <= 20000 && width > 0 && height > 0 &&
      Finite(spring.mass, .1, 10) && Finite(spring.stiffness, 1, 1000) && Finite(spring.damping, 1, 200));
    int64_t previous = 0;
    for (const auto& step : steps) {
      Require(step.time_us >= previous && step.time_us <= duration_us &&
        Finite(step.x, 0, 1) && Finite(step.y, 0, 1) && Finite(step.factor, 1, 3) &&
        step.width >= 1 && step.width <= 100000 && step.height >= 1 && step.height <= 100000);
      previous = step.time_us;
    }
    steps_ = steps; spring_ = spring; width_ = width; height_ = height;
  }
  void Reset(int64_t output_us) {
    x_ = {.5, 0, .5}; y_ = {.5, 0, .5}; factor_ = {1, 0, 1};
    started_us_ = output_us;
    while (next_ < steps_.size() && steps_[next_].time_us < output_us) ++next_;
  }
  RECT Crop(const RECT& box, int64_t output_us) {
    if (steps_.empty()) return box;
    Require(output_us >= started_us_);
    while (next_ < steps_.size() && steps_[next_].time_us <= output_us) {
      const auto& step = steps_[next_++];
      Advance(step.time_us);
      const auto fit = std::min(static_cast<double>(width_) / step.width, static_cast<double>(height_) / step.height);
      x_.target = ((width_ - step.width * fit) / 2 + step.x * step.width * fit) / width_;
      y_.target = ((height_ - step.height * fit) / 2 + step.y * step.height * fit) / height_;
      factor_.target = step.factor;
    }
    const auto time = static_cast<double>(output_us - started_us_) / 1000000;
    const auto factor = std::clamp(Evaluate(factor_, time).position, 1.0, 3.0);
    if (factor < 1.00001) return box;
    const LONG width = box.right - box.left, height = box.bottom - box.top;
    const auto crop_width = std::min(width, std::max<LONG>(2, static_cast<LONG>(width / factor) / 2 * 2));
    const auto crop_height = std::min(height, std::max<LONG>(2, static_cast<LONG>(height / factor) / 2 * 2));
    const auto x = static_cast<LONG>(std::clamp(Evaluate(x_, time).position, 0.0, 1.0) * width - crop_width / 2);
    const auto y = static_cast<LONG>(std::clamp(Evaluate(y_, time).position, 0.0, 1.0) * height - crop_height / 2);
    const LONG left = std::clamp<LONG>(x / 2 * 2, 0, width - crop_width);
    const LONG top = std::clamp<LONG>(y / 2 * 2, 0, height - crop_height);
    return {box.left + left, box.top + top, box.left + left + crop_width, box.top + top + crop_height};
  }
  // Call after Crop at this clock. Motion uses the unrounded spring geometry,
  // so a final two-pixel encoder crop adjustment cannot cause a blur flash.
  ZoomViewport Viewport(const RECT& box, int64_t output_us) const {
    const double width = box.right - box.left, height = box.bottom - box.top;
    if (steps_.empty()) return {static_cast<double>(box.left), static_cast<double>(box.top), static_cast<double>(box.right), static_cast<double>(box.bottom)};
    Require(output_us >= started_us_);
    const auto time = static_cast<double>(output_us - started_us_) / 1000000;
    const auto factor = std::clamp(Evaluate(factor_, time).position, 1.0, 3.0);
    const auto w = std::min(width, std::max(2.0, width / factor)), h = std::min(height, std::max(2.0, height / factor));
    const auto x = std::clamp(std::clamp(Evaluate(x_, time).position, 0.0, 1.0) * width - w / 2, 0.0, width - w);
    const auto y = std::clamp(std::clamp(Evaluate(y_, time).position, 0.0, 1.0) * height - h / 2, 0.0, height - h);
    return {box.left + x, box.top + y, box.left + x + w, box.top + y + h};
  }
 private:
  struct State { double position, velocity, target; };
  static void Require(bool value) { if (!value) throw std::runtime_error("Invalid screen zoom"); }
  static bool Finite(double value, double low, double high) { return std::isfinite(value) && value >= low && value <= high; }
  State Evaluate(const State& state, double time) const {
    const auto a = spring_.damping / (2 * spring_.mass), omega = spring_.stiffness / spring_.mass;
    const auto offset = state.position - state.target, delta = a * a - omega;
    double position = 0, velocity = 0;
    if (std::abs(delta) < 1e-8) {
      const auto coefficient = state.velocity + a * offset, envelope = std::exp(-a * time);
      position = envelope * (offset + coefficient * time);
      velocity = envelope * (coefficient - a * (offset + coefficient * time));
    } else if (delta > 0) {
      const auto b = std::sqrt(delta), first = -a + b, second = -a - b;
      const auto c1 = (state.velocity - second * offset) / (first - second), c2 = offset - c1;
      position = c1 * std::exp(first * time) + c2 * std::exp(second * time);
      velocity = first * c1 * std::exp(first * time) + second * c2 * std::exp(second * time);
    } else {
      const auto b = std::sqrt(-delta), c2 = (state.velocity + a * offset) / b, envelope = std::exp(-a * time);
      const auto cosine = std::cos(b * time), sine = std::sin(b * time);
      position = envelope * (offset * cosine + c2 * sine);
      velocity = envelope * ((-a * offset + b * c2) * cosine + (-a * c2 - b * offset) * sine);
    }
    return {state.target + position, velocity, state.target};
  }
  void Advance(int64_t output_us) {
    const auto time = static_cast<double>(output_us - started_us_) / 1000000;
    x_ = Evaluate(x_, time); y_ = Evaluate(y_, time); factor_ = Evaluate(factor_, time);
    started_us_ = output_us;
  }
  std::vector<ScreenZoomStep> steps_;
  ZoomSpring spring_;
  UINT width_ = 0, height_ = 0;
  size_t next_ = 0;
  int64_t started_us_ = 0;
  State x_{.5, 0, .5}, y_{.5, 0, .5}, factor_{1, 0, 1};
};
#endif

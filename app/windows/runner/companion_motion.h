#ifndef RUNNER_COMPANION_MOTION_H_
#define RUNNER_COMPANION_MOTION_H_
#include <algorithm>
#include <cmath>

// Pure placement/spring logic. Samples are transient; no input hook or history.
struct CompanionRect { double x, y, width, height; };
struct CompanionConfig {
  double width, height, gap, jitter, rest_seconds;
  double mass, stiffness, damping;
};
class CompanionMotion {
 public:
  explicit CompanionMotion(CompanionConfig config) : config_(config) {}
  void Reset(double x, double y) {
    x_ = x; y_ = y; vx_ = vy_ = 0; sampled_ = false;
  }
  CompanionRect Step(double pointer_x, double pointer_y, CompanionRect work,
                     double now, double elapsed) {
    const double width = std::min(config_.width, work.width);
    const double height = std::min(config_.height, work.height);
    const double max_x = work.x + work.width - width;
    const double max_y = work.y + work.height - height;
    if (!sampled_) {
      anchor_x_ = pointer_x; anchor_y_ = pointer_y; last_move_ = now;
      sampled_ = true; left_ = true; above_ = false;
    }
    const double dx = pointer_x - anchor_x_, dy = pointer_y - anchor_y_;
    if (std::hypot(dx, dy) >= config_.jitter) {
      if (std::abs(dx) >= config_.jitter) left_ = dx > 0;
      if (std::abs(dy) >= config_.jitter) above_ = dy > 0;
      anchor_x_ = pointer_x; anchor_y_ = pointer_y; last_move_ = now;
    }
    double target_x, target_y;
    if (now - last_move_ >= config_.rest_seconds) {
      target_x = work.x + (work.width - width) / 2;
      target_y = work.y;
    } else {
      target_x = left_ ? pointer_x - config_.gap - width : pointer_x + config_.gap;
      target_y = above_ ? pointer_y - config_.gap - height : pointer_y + config_.gap;
      if (target_x < work.x) target_x = pointer_x + config_.gap;
      else if (target_x > max_x) target_x = pointer_x - config_.gap - width;
      if (target_y < work.y) target_y = pointer_y + config_.gap;
      else if (target_y > max_y) target_y = pointer_y - config_.gap - height;
    }
    target_x = std::clamp(target_x, work.x, max_x);
    target_y = std::clamp(target_y, work.y, max_y);
    // Bounded numerical integration remains stable after a delayed UI frame.
    double remaining = std::clamp(elapsed, 0.0, 0.1);
    while (remaining > 0) {
      const double dt = std::min(remaining, 1.0 / 240.0);
      vx_ += ((target_x - x_) * config_.stiffness - vx_ * config_.damping) / config_.mass * dt;
      vy_ += ((target_y - y_) * config_.stiffness - vy_ * config_.damping) / config_.mass * dt;
      x_ += vx_ * dt; y_ += vy_ * dt; remaining -= dt;
    }
    // Includes spring frames and monitor changes, not only settled targets.
    const double bounded_x = std::clamp(x_, work.x, max_x);
    const double bounded_y = std::clamp(y_, work.y, max_y);
    if (bounded_x != x_) vx_ = 0;
    if (bounded_y != y_) vy_ = 0;
    x_ = bounded_x; y_ = bounded_y;
    return {x_, y_, width, height};
  }
 private:
  CompanionConfig config_;
  double x_ = 0, y_ = 0, vx_ = 0, vy_ = 0;
  double anchor_x_ = 0, anchor_y_ = 0, last_move_ = 0;
  bool sampled_ = false, left_ = true, above_ = false;
};
#endif

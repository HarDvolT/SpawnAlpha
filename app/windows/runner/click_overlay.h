#ifndef RUNNER_CLICK_OVERLAY_H_
#define RUNNER_CLICK_OVERLAY_H_
#include <d2d1_1.h>
#include <d3d11.h>
#include <winrt/base.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

struct RenderClick {
  int64_t start_us = 0, end_us = 0;
  double x = 0, y = 0;
  UINT width = 0, height = 0;
};
struct ClickLayout {
  double radius = 0, grow = 0, stroke = 0, halo = 0;
  double mass = 0, stiffness = 0, damping = 0;
  uint32_t color = 0;
};
class ClickOverlay {
 public:
  void Open(ID3D11Device* device, UINT width, UINT height, int64_t duration,
      const std::vector<RenderClick>& pulses, const ClickLayout& layout) {
    if (pulses.empty()) return;
    Require(pulses.size() <= 20000 && Fraction(layout.radius, 1, 40) &&
      Fraction(layout.grow, 1, 8) && Fraction(layout.stroke, .5, 10) &&
      Fraction(layout.halo, 0, .5) && Fraction(layout.mass, .1, 10) &&
      Fraction(layout.stiffness, 1, 1000) && Fraction(layout.damping, 1, 200) &&
      layout.damping * layout.damping < 4 * layout.mass * layout.stiffness);
    int64_t previous = 0;
    for (const auto& pulse : pulses) {
      Require(pulse.start_us >= previous && pulse.end_us > pulse.start_us &&
        pulse.end_us <= duration && pulse.end_us - pulse.start_us <= 1000000 &&
        Fraction(pulse.x, 0, 1) && Fraction(pulse.y, 0, 1) &&
        pulse.width > 0 && pulse.width <= 100000 && pulse.height > 0 && pulse.height <= 100000);
      previous = pulse.start_us;
    }
    pulses_ = pulses; options_ = layout;
    scale_ = static_cast<float>(std::min(width, height)) / 1080.0f;
    winrt::com_ptr<ID2D1Factory1> factory;
    winrt::check_hresult(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, factory.put()));
    winrt::com_ptr<ID3D11Device> owned; owned.copy_from(device);
    const auto dxgi = owned.as<IDXGIDevice>();
    winrt::com_ptr<ID2D1Device> d2d;
    winrt::check_hresult(factory->CreateDevice(dxgi.get(), d2d.put()));
    winrt::check_hresult(d2d->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, context_.put()));
    const D2D1_COLOR_F color{((layout.color >> 16) & 255) / 255.0f,
      ((layout.color >> 8) & 255) / 255.0f, (layout.color & 255) / 255.0f, (layout.color >> 24) / 255.0f};
    winrt::check_hresult(context_->CreateSolidColorBrush(color, ring_.put()));
    const D2D1_GRADIENT_STOP stops[]{{0, {color.r, color.g, color.b, static_cast<float>(layout.halo)}},
      {1, {color.r, color.g, color.b, 0}}};
    winrt::com_ptr<ID2D1GradientStopCollection> gradient;
    winrt::check_hresult(context_->CreateGradientStopCollection(stops, 2, gradient.put()));
    winrt::check_hresult(context_->CreateRadialGradientBrush(
      D2D1::RadialGradientBrushProperties(D2D1::Point2F(0, 0), D2D1::Point2F(0, 0), 1, 1), gradient.get(), halo_.put()));
  }
  void Draw(ID3D11Texture2D* frame, int64_t time, const RECT& source,
      const RECT& crop, const RECT& destination, const RECT& camera) {
    if (pulses_.empty()) return;
    const auto end = std::upper_bound(pulses_.begin(), pulses_.end(), time,
      [](int64_t t, const RenderClick& pulse) { return t < pulse.start_us; });
    auto begin = end;
    // Bound simultaneous rings to the most recent active 64.
    size_t active = 0;
    while (begin != pulses_.begin() && active < 64) {
      auto previous = begin - 1;
      if (previous->start_us + 1000000 <= time) break;
      begin = previous;
      if (begin->end_us > time) ++active;
    }
    if (!active) return;
    if (target_frame_.get() != frame) {
      target_ = nullptr; target_frame_.copy_from(frame);
      const auto surface = target_frame_.as<IDXGISurface>();
      const auto properties = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE), 96, 96);
      winrt::check_hresult(context_->CreateBitmapFromDxgiSurface(surface.get(), &properties, target_.put()));
    }
    context_->SetTarget(target_.get()); context_->BeginDraw();
    const bool excluded = camera.right > camera.left && camera.bottom > camera.top;
    const RECT clips[] = {excluded ? RECT{destination.left, destination.top, destination.right,
        std::clamp(camera.top, destination.top, destination.bottom)} : destination,
      {destination.left, std::clamp(camera.top, destination.top, destination.bottom),
        std::clamp(camera.left, destination.left, destination.right), std::clamp(camera.bottom, destination.top, destination.bottom)},
      {std::clamp(camera.right, destination.left, destination.right), std::clamp(camera.top, destination.top, destination.bottom),
        destination.right, std::clamp(camera.bottom, destination.top, destination.bottom)},
      {destination.left, std::clamp(camera.bottom, destination.top, destination.bottom), destination.right, destination.bottom}};
    for (const auto& clip : clips) {
      if (clip.right <= clip.left || clip.bottom <= clip.top) continue;
      context_->PushAxisAlignedClip(D2D1::RectF(static_cast<float>(clip.left), static_cast<float>(clip.top),
        static_cast<float>(clip.right), static_cast<float>(clip.bottom)), D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
      for (auto pulse = begin; pulse != end; ++pulse) {
        if (pulse->end_us <= time) continue;
        const auto sw = source.right - source.left, sh = source.bottom - source.top;
        const auto fit = std::min(static_cast<double>(sw) / pulse->width, static_cast<double>(sh) / pulse->height);
        const auto sx = source.left + (sw - pulse->width * fit) / 2 + pulse->x * pulse->width * fit;
        const auto sy = source.top + (sh - pulse->height * fit) / 2 + pulse->y * pulse->height * fit;
        const auto x = destination.left + (sx - crop.left) / (crop.right - crop.left) * (destination.right - destination.left);
        const auto y = destination.top + (sy - crop.top) / (crop.bottom - crop.top) * (destination.bottom - destination.top);
        const auto seconds = static_cast<double>(time - pulse->start_us) / 1000000;
        const auto a = options_.damping / (2 * options_.mass), b = std::sqrt(options_.stiffness / options_.mass - a * a);
        const auto remaining = std::exp(-a * seconds) * (std::cos(b * seconds) + a / b * std::sin(b * seconds));
        const auto progress = static_cast<double>(time - pulse->start_us) / (pulse->end_us - pulse->start_us);
        const auto radius = static_cast<float>(options_.radius * (1 + (options_.grow - 1) * std::clamp(1 - remaining, 0.0, 1.0))) * scale_;
        const auto center = D2D1::Point2F(static_cast<float>(x), static_cast<float>(y));
        const auto base = static_cast<float>(options_.radius) * scale_;
        halo_->SetCenter(center); halo_->SetRadiusX(base); halo_->SetRadiusY(base);
        halo_->SetOpacity(static_cast<float>(1 - progress)); ring_->SetOpacity(static_cast<float>(1 - progress));
        context_->FillEllipse(D2D1::Ellipse(center, base, base), halo_.get());
        context_->DrawEllipse(D2D1::Ellipse(center, radius, radius), ring_.get(), static_cast<float>(options_.stroke) * scale_);
      }
      context_->PopAxisAlignedClip();
      if (!excluded) break;
    }
    const auto drawn = context_->EndDraw(); context_->SetTarget(nullptr); winrt::check_hresult(drawn);
  }
 private:
  static void Require(bool value) { if (!value) throw std::runtime_error("Invalid click highlight"); }
  static bool Fraction(double value, double low, double high) { return std::isfinite(value) && value >= low && value <= high; }
  std::vector<RenderClick> pulses_;
  ClickLayout options_;
  float scale_ = 0;
  winrt::com_ptr<ID2D1DeviceContext> context_;
  winrt::com_ptr<ID2D1Bitmap1> target_;
  winrt::com_ptr<ID3D11Texture2D> target_frame_;
  winrt::com_ptr<ID2D1SolidColorBrush> ring_;
  winrt::com_ptr<ID2D1RadialGradientBrush> halo_;
};
#endif

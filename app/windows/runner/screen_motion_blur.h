#ifndef RUNNER_SCREEN_MOTION_BLUR_H_
#define RUNNER_SCREEN_MOTION_BLUR_H_
#include <d2d1_1.h>
#include <d2d1effects.h>
#include <d3d11.h>
#include <winrt/base.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include "screen_zoom.h"

struct ScreenBlurLayout {
  bool enabled = false;
  double maximum = 0, minimum = 0;
  int64_t shutter_us = 0;
};
struct ScreenBlurSample { double radius = 0, angle = 0; };

class ViewportMotion {
 public:
  void Open(const ScreenBlurLayout& layout, UINT width, UINT height) {
    if (!layout.enabled) return;
    Require(std::isfinite(layout.maximum) && layout.maximum > 0 && layout.maximum <= 20 &&
      std::isfinite(layout.minimum) && layout.minimum >= 0 && layout.minimum <= layout.maximum &&
      layout.shutter_us > 0 && layout.shutter_us <= 100000 && width > 0 && height > 0);
    layout_ = layout; scale_ = std::min(width, height) / 1080.0;
  }
  void Reset() { sampled_ = false; }
  ScreenBlurSample Sample(const RECT& crop, const RECT& picture, int64_t time_us) {
    return SampleViewport({static_cast<double>(crop.left), static_cast<double>(crop.top),
      static_cast<double>(crop.right), static_cast<double>(crop.bottom)}, picture, time_us);
  }
  ScreenBlurSample SampleViewport(const ZoomViewport& crop, const RECT& picture, int64_t time_us) {
    if (!layout_.enabled) return {};
    Require(std::isfinite(crop.left) && std::isfinite(crop.top) && std::isfinite(crop.right) && std::isfinite(crop.bottom) &&
      crop.right > crop.left && crop.bottom > crop.top && picture.right > picture.left && picture.bottom > picture.top && time_us >= 0);
    ScreenBlurSample result;
    if (sampled_) {
      Require(time_us > previous_us_);
      double vx = 0, vy = 0, speed = 0;
      const auto w = static_cast<double>(crop.right - crop.left), h = static_cast<double>(crop.bottom - crop.top);
      const auto pw = static_cast<double>(picture.right - picture.left), ph = static_cast<double>(picture.bottom - picture.top);
      // Compare where each previous viewport edge lands in the new viewport.
      for (int corner = 0; corner < 4; ++corner) {
        const double x = corner % 2 ? previous_.right : previous_.left;
        const double y = corner / 2 ? previous_.bottom : previous_.top;
        const double dx = ((x - crop.left) / w - (corner % 2 ? 1 : 0)) * pw;
        const double dy = ((y - crop.top) / h - (corner / 2 ? 1 : 0)) * ph;
        const double length = std::hypot(dx, dy);
        if (length > speed) { speed = length; vx = dx; vy = dy; }
      }
      const auto radius = std::min(layout_.maximum * scale_, speed * layout_.shutter_us / (time_us - previous_us_));
      if (radius >= layout_.minimum * scale_) result = {radius, -std::atan2(vy, vx) * 180 / 3.14159265358979323846};
    }
    previous_ = crop; previous_us_ = time_us; sampled_ = true;
    return result;
  }
 private:
  static void Require(bool value) { if (!value) throw std::runtime_error("Invalid screen blur"); }
  ScreenBlurLayout layout_;
  ZoomViewport previous_{};
  double scale_ = 0;
  int64_t previous_us_ = 0;
  bool sampled_ = false;
};

// Separate read-only GPU snapshot; it never samples the bitmap bound as target.
// The main picture is blurred before camera/captions/effects are composed.
class ScreenMotionBlur {
 public:
  void Open(ID3D11Device* device, UINT width, UINT height, const RECT& picture, const ScreenBlurLayout& layout) {
    if (!layout.enabled) return;
    ViewportMotion validation; validation.Open(layout, width, height);
    device->GetImmediateContext(gpu_.put());
    D3D11_TEXTURE2D_DESC desc{}; desc.Width = width; desc.Height = height;
    desc.MipLevels = desc.ArraySize = 1; desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
    winrt::check_hresult(device->CreateTexture2D(&desc, nullptr, copy_.put()));
    winrt::com_ptr<ID2D1Factory1> factory;
    winrt::check_hresult(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, factory.put()));
    winrt::com_ptr<ID3D11Device> owned; owned.copy_from(device);
    winrt::com_ptr<ID2D1Device> d2d;
    winrt::check_hresult(factory->CreateDevice(owned.as<IDXGIDevice>().get(), d2d.put()));
    winrt::check_hresult(d2d->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, context_.put()));
    const auto props = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_NONE,
      D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE), 96, 96);
    winrt::check_hresult(context_->CreateBitmapFromDxgiSurface(copy_.as<IDXGISurface>().get(), &props, source_.put()));
    winrt::com_ptr<ID2D1Effect> crop;
    winrt::check_hresult(context_->CreateEffect(CLSID_D2D1Crop, crop.put()));
    crop->SetInput(0, source_.get());
    picture_ = D2D1::RectF(static_cast<float>(picture.left), static_cast<float>(picture.top), static_cast<float>(picture.right), static_cast<float>(picture.bottom));
    winrt::check_hresult(crop->SetValue(D2D1_CROP_PROP_RECT, picture_));
    winrt::check_hresult(context_->CreateEffect(CLSID_D2D1DirectionalBlur, effect_.put()));
    effect_->SetInputEffect(0, crop.get());
    winrt::check_hresult(effect_->SetValue(D2D1_DIRECTIONALBLUR_PROP_BORDER_MODE, D2D1_BORDER_MODE_HARD));
    winrt::check_hresult(effect_->SetValue(D2D1_DIRECTIONALBLUR_PROP_OPTIMIZATION, D2D1_DIRECTIONALBLUR_OPTIMIZATION_QUALITY));
  }
  void Draw(ID3D11Texture2D* frame, const ScreenBlurSample& sample) {
    if (!context_ || sample.radius <= 0) return;
    gpu_->CopyResource(copy_.get(), frame);
    if (frame_.get() != frame) {
      target_ = nullptr; frame_.copy_from(frame);
      const auto props = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE), 96, 96);
      winrt::check_hresult(context_->CreateBitmapFromDxgiSurface(frame_.as<IDXGISurface>().get(), &props, target_.put()));
    }
    winrt::check_hresult(effect_->SetValue(D2D1_DIRECTIONALBLUR_PROP_STANDARD_DEVIATION, static_cast<float>(sample.radius / 3)));
    winrt::check_hresult(effect_->SetValue(D2D1_DIRECTIONALBLUR_PROP_ANGLE, static_cast<float>(sample.angle)));
    context_->SetTarget(target_.get()); context_->BeginDraw();
    context_->PushAxisAlignedClip(picture_, D2D1_ANTIALIAS_MODE_ALIASED);
    context_->DrawImage(effect_.get(), D2D1::Point2F(picture_.left, picture_.top), picture_, D2D1_INTERPOLATION_MODE_LINEAR, D2D1_COMPOSITE_MODE_SOURCE_COPY);
    context_->PopAxisAlignedClip();
    const auto result = context_->EndDraw(); context_->SetTarget(nullptr); winrt::check_hresult(result);
  }
 private:
  winrt::com_ptr<ID3D11DeviceContext> gpu_;
  winrt::com_ptr<ID3D11Texture2D> copy_, frame_;
  winrt::com_ptr<ID2D1DeviceContext> context_;
  winrt::com_ptr<ID2D1Bitmap1> source_, target_;
  winrt::com_ptr<ID2D1Effect> effect_;
  D2D1_RECT_F picture_{};
};
#endif

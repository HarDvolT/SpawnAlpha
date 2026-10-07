#ifndef RUNNER_SCREEN_FRAME_H_
#define RUNNER_SCREEN_FRAME_H_
#include <d2d1_1.h>
#include <d2d1effects.h>
#include <d3d11.h>
#include <winrt/base.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

struct FrameShadow { uint32_t color = 0; double x = 0, y = 0, sigma = 0; };
struct ScreenFrameLayout {
  bool enabled = false;
  double inset = 0, radius = 0;
  uint32_t top_color = 0, bottom_color = 0;
  std::vector<FrameShadow> shadows;
};
inline RECT ScreenFrameBounds(UINT width, UINT height, const ScreenFrameLayout& layout) {
  if (!layout.enabled) return {0, 0, static_cast<LONG>(width), static_cast<LONG>(height)};
  if (!std::isfinite(layout.inset) || layout.inset < .01 || layout.inset > .2)
    throw std::runtime_error("Invalid screen frame");
  const auto x = static_cast<LONG>(width * layout.inset), y = static_cast<LONG>(height * layout.inset);
  return {x, y, static_cast<LONG>(width) - x, static_cast<LONG>(height) - y};
}

// Bounded worker-only GPU mask: generated backdrop/shadow outside the rounded
// screen picture, excluding the independently composed camera rectangle.
class ScreenFrame {
 public:
  void Open(ID3D11Device* device, UINT width, UINT height, const RECT& picture, const ScreenFrameLayout& layout) {
    if (!layout.enabled) return;
    Require(width >= 2 && height >= 2 && width <= 4096 && height <= 4096 &&
      picture.left >= 0 && picture.top >= 0 && picture.right <= static_cast<LONG>(width) && picture.bottom <= static_cast<LONG>(height) &&
      picture.right > picture.left && picture.bottom > picture.top &&
      Valid(layout.radius, 0, 40) && (layout.top_color >> 24) == 255 && (layout.bottom_color >> 24) == 255 && layout.shadows.size() <= 4);
    ScreenFrameBounds(width, height, layout); // Validate the same placement used by the compositor.
    width_ = width; height_ = height; picture_ = picture;
    scale_ = static_cast<float>(std::min(width, height)) / 1080.0f;
    radius_ = std::min(static_cast<float>(layout.radius) * scale_, std::min(picture.right - picture.left, picture.bottom - picture.top) / 2.0f);
    winrt::check_hresult(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, factory_.put()));
    winrt::com_ptr<ID3D11Device> owned; owned.copy_from(device);
    winrt::com_ptr<ID2D1Device> d2d;
    winrt::check_hresult(factory_->CreateDevice(owned.as<IDXGIDevice>().get(), d2d.put()));
    winrt::check_hresult(d2d->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, context_.put()));
    const D2D1_GRADIENT_STOP stops[]{{0, Color(layout.top_color)}, {1, Color(layout.bottom_color)}};
    winrt::com_ptr<ID2D1GradientStopCollection> gradient;
    winrt::check_hresult(context_->CreateGradientStopCollection(stops, 2, gradient.put()));
    winrt::check_hresult(context_->CreateLinearGradientBrush(D2D1::LinearGradientBrushProperties(
      D2D1::Point2F(0, 0), D2D1::Point2F(static_cast<float>(width), static_cast<float>(height))), gradient.get(), backdrop_.put()));
    winrt::check_hresult(factory_->CreateRoundedRectangleGeometry(D2D1::RoundedRect(Rect(picture), radius_, radius_), rounded_.put()));
    winrt::check_hresult(factory_->CreateRectangleGeometry(D2D1::RectF(0, 0, static_cast<float>(width), static_cast<float>(height)), full_.put()));
    for (const auto& shadow : layout.shadows) {
      Require(Valid(shadow.x, -100, 100) && Valid(shadow.y, -100, 100) && Valid(shadow.sigma, 0, 100));
      winrt::com_ptr<ID2D1CommandList> commands;
      winrt::check_hresult(context_->CreateCommandList(commands.put()));
      context_->SetTarget(commands.get()); context_->BeginDraw();
      winrt::com_ptr<ID2D1SolidColorBrush> ink;
      winrt::check_hresult(context_->CreateSolidColorBrush(Color(shadow.color), ink.put()));
      const auto x = static_cast<float>(shadow.x) * scale_, y = static_cast<float>(shadow.y) * scale_;
      context_->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(picture.left + x, picture.top + y,
        picture.right + x, picture.bottom + y), radius_, radius_), ink.get());
      const auto result = context_->EndDraw(); context_->SetTarget(nullptr); winrt::check_hresult(result);
      winrt::check_hresult(commands->Close());
      winrt::com_ptr<ID2D1Effect> blurred;
      winrt::check_hresult(context_->CreateEffect(CLSID_D2D1GaussianBlur, blurred.put()));
      blurred->SetInput(0, commands.get());
      winrt::check_hresult(blurred->SetValue(D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION, static_cast<float>(shadow.sigma) * scale_));
      shadows_.push_back(std::move(blurred));
    }
  }
  void Draw(ID3D11Texture2D* frame, const RECT& camera) {
    if (!context_) return;
    if (!mask_ || !EqualRect(&camera, &camera_)) {
      camera_ = camera;
      auto outside = Combine(full_.get(), rounded_.get(), D2D1_COMBINE_MODE_EXCLUDE);
      if (camera.right > camera.left && camera.bottom > camera.top) {
        winrt::com_ptr<ID2D1RectangleGeometry> box;
        winrt::check_hresult(factory_->CreateRectangleGeometry(Rect(camera), box.put()));
        mask_ = Combine(outside.get(), box.get(), D2D1_COMBINE_MODE_EXCLUDE);
      } else mask_ = std::move(outside);
    }
    if (target_frame_.get() != frame) {
      target_ = nullptr; target_frame_.copy_from(frame);
      const auto properties = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE), 96, 96);
      winrt::check_hresult(context_->CreateBitmapFromDxgiSurface(target_frame_.as<IDXGISurface>().get(), &properties, target_.put()));
    }
    context_->SetTarget(target_.get()); context_->BeginDraw();
    context_->PushLayer(D2D1::LayerParameters(D2D1::InfiniteRect(), mask_.get()), nullptr);
    context_->FillRectangle(D2D1::RectF(0, 0, static_cast<float>(width_), static_cast<float>(height_)), backdrop_.get());
    for (const auto& shadow : shadows_) context_->DrawImage(shadow.get());
    context_->PopLayer();
    const auto result = context_->EndDraw(); context_->SetTarget(nullptr); winrt::check_hresult(result);
  }
 private:
  static void Require(bool ok) { if (!ok) throw std::runtime_error("Invalid screen frame"); }
  static bool Valid(double n, double low, double high) { return std::isfinite(n) && n >= low && n <= high; }
  static D2D1_RECT_F Rect(const RECT& r) { return D2D1::RectF(static_cast<float>(r.left), static_cast<float>(r.top), static_cast<float>(r.right), static_cast<float>(r.bottom)); }
  static D2D1_COLOR_F Color(uint32_t n) { return {((n >> 16) & 255) / 255.0f, ((n >> 8) & 255) / 255.0f, (n & 255) / 255.0f, (n >> 24) / 255.0f}; }
  winrt::com_ptr<ID2D1PathGeometry> Combine(ID2D1Geometry* a, ID2D1Geometry* b, D2D1_COMBINE_MODE mode) {
    winrt::com_ptr<ID2D1PathGeometry> path; winrt::com_ptr<ID2D1GeometrySink> sink;
    winrt::check_hresult(factory_->CreatePathGeometry(path.put())); winrt::check_hresult(path->Open(sink.put()));
    winrt::check_hresult(a->CombineWithGeometry(b, mode, nullptr, sink.get())); winrt::check_hresult(sink->Close()); return path;
  }
  UINT width_ = 0, height_ = 0;
  RECT picture_{}, camera_{};
  float scale_ = 0, radius_ = 0;
  winrt::com_ptr<ID2D1Factory1> factory_;
  winrt::com_ptr<ID2D1DeviceContext> context_;
  winrt::com_ptr<ID2D1RoundedRectangleGeometry> rounded_;
  winrt::com_ptr<ID2D1RectangleGeometry> full_;
  winrt::com_ptr<ID2D1PathGeometry> mask_;
  winrt::com_ptr<ID2D1LinearGradientBrush> backdrop_;
  winrt::com_ptr<ID2D1Bitmap1> target_;
  winrt::com_ptr<ID3D11Texture2D> target_frame_;
  std::vector<winrt::com_ptr<ID2D1Effect>> shadows_;
};
#endif

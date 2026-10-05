#include "screen_preview.h"
#include "screen_sources.h"

#include <d3d11.h>
#include <dxgi.h>
#include <roapi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <mutex>
#include <vector>

namespace {
using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using winrt::Windows::Graphics::SizeInt32;
using ::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess;
using flutter::EncodableMap;
using flutter::EncodableValue;

struct Pixels {
  size_t width = 0;
  size_t height = 0;
  std::vector<uint8_t> rgba;
};

// Each render callback owns a snapshot until Flutter releases it. A new capture
// frame never mutates a pixel buffer already handed to Flutter's render thread.
struct PixelLease {
  std::shared_ptr<const Pixels> pixels;
  FlutterDesktopPixelBuffer buffer{};
};

struct MappedTexture {
  ID3D11DeviceContext* context;
  ID3D11Texture2D* texture;
  ~MappedTexture() { context->Unmap(texture, 0); }
};

class PreviewSession : public std::enable_shared_from_this<PreviewSession> {
 public:
  explicit PreviewSession(flutter::TextureRegistrar* textures) : textures_(textures) {}

  void Start(const std::string& source) {
    if (!GraphicsCaptureSession::IsSupported()) throw hresult_error(E_NOTIMPL);
    HMONITOR monitor = nullptr;
    HWND window = nullptr;
    if (!ResolveScreenSource(source, &monitor, &window)) throw hresult_error(E_INVALIDARG);
    source_window_ = window;
    const auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    if (window) {
      check_hresult(interop->CreateForWindow(window, guid_of<GraphicsCaptureItem>(), put_abi(item_)));
    } else {
      check_hresult(interop->CreateForMonitor(monitor, guid_of<GraphicsCaptureItem>(), put_abi(item_)));
    }
    size_ = item_.Size();
    if (size_.Width <= 0 || size_.Height <= 0) throw hresult_error(E_INVALIDARG);

    HRESULT created = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
        device_.put(), nullptr, context_.put());
    if (FAILED(created)) {
      check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
          device_.put(), nullptr, context_.put()));
    }
    const auto dxgi = device_.as<IDXGIDevice>();
    com_ptr<IInspectable> inspectable;
    check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
    rt_device_ = inspectable.as<IDirect3DDevice>();

    const auto weak = weak_from_this();
    texture_ = std::make_shared<flutter::TextureVariant>(flutter::PixelBufferTexture(
        [weak](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
          if (const auto session = weak.lock()) return session->CopyPixels();
          return nullptr;
        }));
    texture_id_ = textures_->RegisterTexture(texture_.get());
    if (texture_id_ < 0) throw hresult_error(E_FAIL);
    pool_ = Direct3D11CaptureFramePool::CreateFreeThreaded(rt_device_,
        DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size_);
    frame_token_ = pool_.FrameArrived([weak](const auto& sender, const auto&) {
      if (const auto session = weak.lock()) session->OnFrame(sender);
    });
    closed_token_ = item_.Closed([weak](const auto&, const auto&) {
      if (const auto session = weak.lock()) session->closed_ = true;
    });
    capture_ = pool_.CreateCaptureSession(item_);
    // Keep Windows' capture border. This slice never writes frames or audio.
    capture_.StartCapture();
  }

  int64_t texture_id() const { return texture_id_; }

  EncodableMap Status() {
    std::lock_guard<std::mutex> lock(pixels_mutex_);
    const bool unavailable = source_window_ && IsIconic(source_window_);
    return {
      {EncodableValue("width"), EncodableValue(static_cast<int32_t>(pixels_ ? pixels_->width : size_.Width))},
      {EncodableValue("height"), EncodableValue(static_cast<int32_t>(pixels_ ? pixels_->height : size_.Height))},
      {EncodableValue("ready"), EncodableValue(pixels_ != nullptr && !unavailable)},
      {EncodableValue("closed"), EncodableValue(closed_.load())},
      {EncodableValue("failed"), EncodableValue(failed_.load() || unavailable)},
    };
  }

  void Stop() {
    if (stopped_.exchange(true)) return;
    Direct3D11CaptureFramePool pool{nullptr};
    GraphicsCaptureSession capture{nullptr};
    GraphicsCaptureItem item{nullptr};
    {
      // Wait for the last frame conversion, then close outside the lock: WinRT
      // may wait for an outstanding event handler while Close is running.
      std::lock_guard<std::mutex> lock(capture_mutex_);
      pool = std::exchange(pool_, nullptr);
      capture = std::exchange(capture_, nullptr);
      item = std::exchange(item_, nullptr);
    }
    try {
      if (item) item.Closed(closed_token_);
      if (pool) pool.FrameArrived(frame_token_);
      if (capture) capture.Close();
      if (pool) pool.Close();
    } catch (...) { /* No private source details in logs. */ }
    if (texture_id_ >= 0) {
      auto keep_texture = std::move(texture_);
      textures_->UnregisterTexture(texture_id_, [keep_texture]() {});
      texture_id_ = -1;
    }
    std::lock_guard<std::mutex> lock(pixels_mutex_);
    pixels_.reset();
  }

  ~PreviewSession() { Stop(); }

 private:
  const FlutterDesktopPixelBuffer* CopyPixels() {
    std::lock_guard<std::mutex> lock(pixels_mutex_);
    if (!pixels_ || stopped_) return nullptr;
    auto* lease = new PixelLease{pixels_};
    lease->buffer.buffer = lease->pixels->rgba.data();
    lease->buffer.width = lease->pixels->width;
    lease->buffer.height = lease->pixels->height;
    lease->buffer.release_context = lease;
    lease->buffer.release_callback = [](void* value) { delete static_cast<PixelLease*>(value); };
    return &lease->buffer;
  }

  void OnFrame(const Direct3D11CaptureFramePool& pool) noexcept {
    std::lock_guard<std::mutex> lock(capture_mutex_);
    if (stopped_ || closed_ || failed_) return;
    try {
      auto frame = pool.TryGetNextFrame();
      if (!frame) return;
      const auto content = frame.ContentSize();
      const bool resized = content.Width != size_.Width || content.Height != size_.Height;
      const auto now = std::chrono::steady_clock::now();
      // Preview only: cap costly CPU readback at 15 fps. Full recording will
      // use GPU surfaces and the platform encoder instead of this pixel path.
      if (resized || now - last_frame_ >= std::chrono::milliseconds(66)) {
        const auto access = frame.Surface().as<IDirect3DDxgiInterfaceAccess>();
        com_ptr<ID3D11Texture2D> surface;
        check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), surface.put_void()));
        D3D11_TEXTURE2D_DESC desc{};
        surface->GetDesc(&desc);
        const auto width = std::min(desc.Width, static_cast<UINT>(std::max(0, content.Width)));
        const auto height = std::min(desc.Height, static_cast<UINT>(std::max(0, content.Height)));
        if (width > 0 && height > 0) {
          D3D11_TEXTURE2D_DESC staging_desc = desc;
          staging_desc.Usage = D3D11_USAGE_STAGING;
          staging_desc.BindFlags = 0;
          staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
          staging_desc.MiscFlags = 0;
          if (!staging_ || staging_width_ != desc.Width || staging_height_ != desc.Height) {
            staging_ = nullptr;
            check_hresult(device_->CreateTexture2D(&staging_desc, nullptr, staging_.put()));
            staging_width_ = desc.Width;
            staging_height_ = desc.Height;
          }
          context_->CopyResource(staging_.get(), surface.get());
          D3D11_MAPPED_SUBRESOURCE mapped{};
          check_hresult(context_->Map(staging_.get(), 0, D3D11_MAP_READ, 0, &mapped));
          const MappedTexture mapping{context_.get(), staging_.get()};
          auto pixels = std::make_shared<Pixels>();
          pixels->width = width;
          pixels->height = height;
          pixels->rgba.resize(static_cast<size_t>(width) * height * 4);
          for (UINT y = 0; y < height; ++y) {
            const auto* src = static_cast<const uint8_t*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch;
            auto* dst = pixels->rgba.data() + static_cast<size_t>(y) * width * 4;
            for (UINT x = 0; x < width; ++x) {
              dst[x * 4] = src[x * 4 + 2];
              dst[x * 4 + 1] = src[x * 4 + 1];
              dst[x * 4 + 2] = src[x * 4];
              dst[x * 4 + 3] = 255;
            }
          }
          {
            std::lock_guard<std::mutex> pixels_lock(pixels_mutex_);
            pixels_ = std::move(pixels);
          }
          textures_->MarkTextureFrameAvailable(texture_id_);
          last_frame_ = now;
        }
      }
      frame.Close();
      if (resized && content.Width > 0 && content.Height > 0) {
        pool.Recreate(rt_device_, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, content);
        // Status reads this fallback only before a pixel snapshot exists.
        std::lock_guard<std::mutex> pixels_lock(pixels_mutex_);
        size_ = content;
      }
    } catch (...) { failed_ = true; }
  }

  flutter::TextureRegistrar* textures_;
  std::shared_ptr<flutter::TextureVariant> texture_;
  int64_t texture_id_ = -1;
  HWND source_window_ = nullptr;
  std::mutex capture_mutex_;
  std::mutex pixels_mutex_;
  std::shared_ptr<const Pixels> pixels_;
  std::atomic<bool> stopped_{false}, closed_{false}, failed_{false};
  std::chrono::steady_clock::time_point last_frame_{};
  GraphicsCaptureItem item_{nullptr};
  GraphicsCaptureSession capture_{nullptr};
  Direct3D11CaptureFramePool pool_{nullptr};
  IDirect3DDevice rt_device_{nullptr};
  SizeInt32 size_{};
  event_token frame_token_{}, closed_token_{};
  com_ptr<ID3D11Device> device_;
  com_ptr<ID3D11DeviceContext> context_;
  com_ptr<ID3D11Texture2D> staging_;
  UINT staging_width_ = 0, staging_height_ = 0;
};

int64_t ReadId(const EncodableMap& args) {
  const auto value = args.find(EncodableValue("sessionId"));
  if (value == args.end()) return -1;
  if (const auto id = std::get_if<int64_t>(&value->second)) return *id;
  if (const auto id = std::get_if<int32_t>(&value->second)) return *id;
  return -1;
}
}  // namespace

class ScreenPreview::Impl {
 public:
  Impl(flutter::BinaryMessenger* messenger, flutter::TextureRegistrar* textures)
      : textures_(textures), channel_(messenger, "spawnalpha/screen_preview",
                                     &flutter::StandardMethodCodec::GetInstance()) {
    initialized_ = SUCCEEDED(RoInitialize(RO_INIT_SINGLETHREADED));
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid", "Choose a source first."); return; }
      try {
        if (call.method_name() == "start") {
          const auto source = args->find(EncodableValue("sourceId"));
          if (source == args->end() || !std::holds_alternative<std::string>(source->second)) {
            result->Error("invalid", "Choose a source first."); return;
          }
          StopActive();
          auto session = std::make_shared<PreviewSession>(textures_);
          session->Start(std::get<std::string>(source->second));
          active_ = session;
          ++generation_;
          auto info = session->Status();
          info.emplace(EncodableValue("sessionId"), EncodableValue(generation_));
          info.emplace(EncodableValue("textureId"), EncodableValue(session->texture_id()));
          result->Success(EncodableValue(info));
        } else if (call.method_name() == "stop") {
          if (ReadId(*args) == generation_) StopActive();
          result->Success();
        } else if (call.method_name() == "status") {
          result->Success(EncodableValue(active_ && ReadId(*args) == generation_ ? active_->Status() :
            EncodableMap{{EncodableValue("closed"), EncodableValue(true)}}));
        } else { result->NotImplemented(); }
      } catch (...) {
        StopActive();
        result->Error("unavailable", "Could not preview this source. Restore the window and try again.");
      }
    });
  }
  ~Impl() {
    channel_.SetMethodCallHandler(nullptr);
    StopActive();
    if (initialized_) RoUninitialize();
  }
 private:
  void StopActive() {
    if (active_) active_->Stop();
    active_.reset();
  }
  flutter::TextureRegistrar* textures_;
  flutter::MethodChannel<EncodableValue> channel_;
  std::shared_ptr<PreviewSession> active_;
  int64_t generation_ = 0;
  bool initialized_ = false;
};

ScreenPreview::ScreenPreview(flutter::BinaryMessenger* messenger, flutter::TextureRegistrar* textures)
    : impl_(std::make_unique<Impl>(messenger, textures)) {}
ScreenPreview::~ScreenPreview() = default;

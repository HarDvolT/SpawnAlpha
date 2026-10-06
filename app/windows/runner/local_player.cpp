#include "local_player.h"
#include "local_media_path.h"
#include <d3d11_4.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Storage.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>
#include <vector>

namespace {
using namespace winrt;
using namespace winrt::Windows::Media::Playback;
using winrt::Windows::Media::Core::MediaSource;
using winrt::Windows::Storage::StorageFile;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface;
using flutter::EncodableMap;
using flutter::EncodableValue;
struct Pixels { UINT width, height; std::vector<uint8_t> rgba; };
struct Lease { std::shared_ptr<const Pixels> pixels; FlutterDesktopPixelBuffer buffer{}; };

class PlayerSession : public std::enable_shared_from_this<PlayerSession> {
 public:
  explicit PlayerSession(flutter::TextureRegistrar* textures) : textures_(textures) {}
  void Start(const std::wstring& path) {
    CheckLocalMediaPath(path);
    const auto weak = weak_from_this();
    texture_ = std::make_shared<flutter::TextureVariant>(flutter::PixelBufferTexture(
        [weak](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
          const auto self = weak.lock();
          if (!self || self->stopped_) return nullptr;
          std::lock_guard<std::mutex> lock(self->pixels_mutex_);
          if (!self->pixels_) return nullptr;
          auto* lease = new Lease{self->pixels_};
          lease->buffer.buffer = lease->pixels->rgba.data();
          lease->buffer.width = lease->pixels->width;
          lease->buffer.height = lease->pixels->height;
          lease->buffer.release_context = lease;
          lease->buffer.release_callback = [](void* p) { delete static_cast<Lease*>(p); };
          return &lease->buffer;
        }));
    texture_id_ = textures_->RegisterTexture(texture_.get());
    if (texture_id_ < 0) throw hresult_error(E_FAIL);
    worker_ = std::thread([weak, path] {
      try {
        init_apartment(apartment_type::multi_threaded);
        if (const auto self = weak.lock()) self->Open(path);
        uninit_apartment();
      } catch (...) { if (const auto self = weak.lock()) self->failed_ = true; }
    });
  }
  int64_t texture_id() const { return texture_id_; }
  EncodableMap Status() {
    std::lock_guard<std::mutex> lock(media_mutex_);
    int64_t position = 0, duration = 0;
    int32_t width = 0, height = 0;
    bool playing = false, buffering = false;
    try {
      if (player_ && ready_) {
        const auto session = player_.PlaybackSession();
        position = session.Position().count() / 10;
        duration = session.NaturalDuration().count() / 10;
        width = static_cast<int32_t>(session.NaturalVideoWidth());
        height = static_cast<int32_t>(session.NaturalVideoHeight());
        playing = session.PlaybackState() == MediaPlaybackState::Playing;
        buffering = session.PlaybackState() == MediaPlaybackState::Buffering;
      }
    } catch (...) { failed_ = true; }
    return {{EncodableValue("ready"), EncodableValue(ready_.load())},
      {EncodableValue("failed"), EncodableValue(failed_.load())},
      {EncodableValue("closed"), EncodableValue(stopped_.load())},
      {EncodableValue("playing"), EncodableValue(playing)},
      {EncodableValue("buffering"), EncodableValue(buffering)},
      {EncodableValue("ended"), EncodableValue(ended_.load())},
      {EncodableValue("positionUs"), EncodableValue(position)},
      {EncodableValue("durationUs"), EncodableValue(duration)},
      {EncodableValue("width"), EncodableValue(width)},
      {EncodableValue("height"), EncodableValue(height)},
      {EncodableValue("frames"), EncodableValue(frames_.load())},
      {EncodableValue("failureCode"), EncodableValue(failure_code_.load())},
      {EncodableValue("failureStage"), EncodableValue(failure_stage_.load())}};
  }
  void Command(const std::string& command, int64_t time, bool mute) {
    std::lock_guard<std::mutex> lock(media_mutex_);
    if (!player_ || !ready_ || failed_ || stopped_) throw hresult_error(E_FAIL);
    if (command == "play") { ended_ = false; player_.Play(); }
    else if (command == "pause") player_.Pause();
    else if (command == "mute") player_.IsMuted(mute);
    else if (command == "seek") {
      const auto duration = player_.PlaybackSession().NaturalDuration().count() / 10;
      if (time < 0 || time > duration) throw hresult_error(E_INVALIDARG);
      ended_ = false;
      player_.PlaybackSession().Position(winrt::Windows::Foundation::TimeSpan(time * 10));
    }
  }
  void Stop() noexcept {
    if (stopped_.exchange(true)) return;
    if (worker_.joinable()) worker_.join();
    MediaPlayer player{nullptr};
    MediaSource source{nullptr};
    {
      std::lock_guard<std::mutex> lock(media_mutex_);
      player = std::exchange(player_, nullptr);
      source = std::exchange(source_, nullptr);
    }
    // Close outside callback locks; the OS may wait for an outstanding frame.
    try { if (player) { player.Pause(); player.Source(nullptr); player.Close(); } } catch (...) {}
    try { if (source) source.Close(); } catch (...) {}
    { std::lock_guard<std::mutex> lock(frame_mutex_); }
    if (texture_id_ >= 0) {
      const auto keep = std::move(texture_);
      textures_->UnregisterTexture(texture_id_, [keep]() {});
      texture_id_ = -1;
    }
    std::lock_guard<std::mutex> lock(pixels_mutex_);
    pixels_.reset();
  }
  ~PlayerSession() { Stop(); }
 private:
  void Open(const std::wstring& path) noexcept {
    try {
      // StorageFile accepts only the already checked local file. It cannot
      // interpret a URI or silently fall back to a network source.
      auto native_path = std::filesystem::path(path).lexically_normal();
      native_path.make_preferred();
      auto file = StorageFile::GetFileFromPathAsync(native_path.wstring()).get();
      if (stopped_) return;
      const auto weak = weak_from_this();
      MediaPlayer player;
      player.AutoPlay(false);
      player.CommandManager().IsEnabled(false);
      player.IsVideoFrameServerEnabled(true);
      player.MediaOpened([weak](const auto&, const auto&) {
        if (const auto self = weak.lock()) self->ready_ = true;
      });
      player.MediaFailed([weak](const auto&, const auto& args) {
        if (const auto self = weak.lock()) { self->failure_stage_ = 2; self->failure_code_ = args.ExtendedErrorCode().value; self->failed_ = true; }
      });
      player.MediaEnded([weak](const auto&, const auto&) {
        if (const auto self = weak.lock()) self->ended_ = true;
      });
      player.VideoFrameAvailable([weak](const auto& sender, const auto&) {
        if (const auto self = weak.lock()) self->Frame(sender);
      });
      auto source = MediaSource::CreateFromStorageFile(file);
      std::lock_guard<std::mutex> lock(media_mutex_);
      if (stopped_) { source.Close(); player.Close(); return; }
      source_ = source; player_ = player;
      player_.Source(source_);
    } catch (...) { failure_stage_ = 1; failure_code_ = to_hresult().value; failed_ = true; }
  }
  void Frame(const MediaPlayer& player) noexcept {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    if (stopped_ || failed_) return;
    try {
      const auto now = std::chrono::steady_clock::now();
      // Preview readback stays bounded. Export retains full GPU surfaces.
      if (now - last_frame_ < std::chrono::milliseconds(60)) return;
      const auto session = player.PlaybackSession();
      const auto width = session.NaturalVideoWidth(), height = session.NaturalVideoHeight();
      if (!width || !height || width > 16384 || height > 16384) return;
      const double scale = std::min({1.0, 1280.0 / width, 720.0 / height});
      const UINT w = std::max(1U, static_cast<UINT>(width * scale));
      const UINT h = std::max(1U, static_cast<UINT>(height * scale));
      if (!device_) {
        check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
          nullptr, 0, D3D11_SDK_VERSION, device_.put(), nullptr, context_.put()));
        context_.as<ID3D11Multithread>()->SetMultithreadProtected(TRUE);
      }
      if (!image_ || w != width_ || h != height_) {
        surface_ = nullptr; image_ = nullptr; staging_ = nullptr;
        D3D11_TEXTURE2D_DESC desc{};
        desc.Width = w; desc.Height = h; desc.MipLevels = 1; desc.ArraySize = 1;
        desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1;
        desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
        check_hresult(device_->CreateTexture2D(&desc, nullptr, image_.put()));
        com_ptr<IInspectable> inspectable;
        check_hresult(CreateDirect3D11SurfaceFromDXGISurface(image_.as<IDXGISurface>().get(), inspectable.put()));
        surface_ = inspectable.as<IDirect3DSurface>();
        desc.Usage = D3D11_USAGE_STAGING; desc.BindFlags = 0; desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        check_hresult(device_->CreateTexture2D(&desc, nullptr, staging_.put()));
        width_ = w; height_ = h;
      }
      player.CopyFrameToVideoSurface(surface_);
      context_->CopyResource(staging_.get(), image_.get());
      auto pixels = std::make_shared<Pixels>();
      pixels->width = w; pixels->height = h; pixels->rgba.resize(static_cast<size_t>(w) * h * 4);
      D3D11_MAPPED_SUBRESOURCE mapped{};
      check_hresult(context_->Map(staging_.get(), 0, D3D11_MAP_READ, 0, &mapped));
      for (UINT y = 0; y < h; ++y) {
        const auto* src = static_cast<const uint8_t*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch;
        auto* dst = pixels->rgba.data() + static_cast<size_t>(y) * w * 4;
        for (UINT x = 0; x < w; ++x) {
          dst[x * 4] = src[x * 4 + 2]; dst[x * 4 + 1] = src[x * 4 + 1];
          dst[x * 4 + 2] = src[x * 4]; dst[x * 4 + 3] = 255;
        }
      }
      context_->Unmap(staging_.get(), 0);
      { std::lock_guard<std::mutex> pixel_lock(pixels_mutex_); pixels_ = std::move(pixels); }
      textures_->MarkTextureFrameAvailable(texture_id_);
      ++frames_; last_frame_ = now;
    } catch (...) { failure_stage_ = 3; failure_code_ = to_hresult().value; failed_ = true; }
  }
  flutter::TextureRegistrar* textures_;
  std::shared_ptr<flutter::TextureVariant> texture_;
  int64_t texture_id_ = -1;
  std::thread worker_;
  std::atomic<bool> ready_{false}, failed_{false}, stopped_{false}, ended_{false};
  std::atomic<int64_t> frames_{0};
  std::atomic<int32_t> failure_code_{0}, failure_stage_{0};
  std::mutex media_mutex_, frame_mutex_, pixels_mutex_;
  MediaPlayer player_{nullptr}; MediaSource source_{nullptr};
  com_ptr<ID3D11Device> device_; com_ptr<ID3D11DeviceContext> context_;
  com_ptr<ID3D11Texture2D> image_, staging_;
  IDirect3DSurface surface_{nullptr};
  UINT width_ = 0, height_ = 0;
  std::shared_ptr<const Pixels> pixels_;
  std::chrono::steady_clock::time_point last_frame_{};
};
int64_t Number(const EncodableMap& args, const char* key) {
  const auto found = args.find(EncodableValue(key));
  if (found == args.end()) return -1;
  if (const auto value = std::get_if<int64_t>(&found->second)) return *value;
  if (const auto value = std::get_if<int32_t>(&found->second)) return *value;
  return -1;
}
}
class LocalPlayer::Impl {
 public:
  Impl(flutter::BinaryMessenger* messenger, flutter::TextureRegistrar* textures)
      : textures_(textures), channel_(messenger, "spawnalpha/player", &flutter::StandardMethodCodec::GetInstance()) {
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid", "Choose a local take."); return; }
      try {
        const auto& method = call.method_name();
        if (method == "open") {
          const auto found = args->find(EncodableValue("path"));
          if (found == args->end() || !std::holds_alternative<std::string>(found->second)) throw hresult_error(E_INVALIDARG);
          const std::wstring path(to_hstring(std::get<std::string>(found->second)));
          CheckLocalMediaPath(path);
          if (active_) active_->Stop();
          active_ = std::make_shared<PlayerSession>(textures_);
          active_->Start(path); ++generation_;
          result->Success(EncodableValue(EncodableMap{
            {EncodableValue("sessionId"), EncodableValue(generation_)},
            {EncodableValue("textureId"), EncodableValue(active_->texture_id())}}));
        } else if (method == "close") {
          if (Number(*args, "sessionId") == generation_ && active_) { active_->Stop(); active_.reset(); }
          result->Success();
        } else if (method == "status") {
          result->Success(EncodableValue(active_ && Number(*args, "sessionId") == generation_ ? active_->Status() :
            EncodableMap{{EncodableValue("closed"), EncodableValue(true)}}));
        } else if (method == "play" || method == "pause" || method == "seek" || method == "mute") {
          if (!active_ || Number(*args, "sessionId") != generation_) throw hresult_error(E_INVALIDARG);
          const auto muted = args->find(EncodableValue("muted"));
          active_->Command(method, Number(*args, "positionUs"), muted != args->end() && muted->second == EncodableValue(true));
          result->Success();
        } else result->NotImplemented();
      } catch (...) { result->Error("unavailable", "This video could not be played. Your file is safe."); }
    });
  }
  ~Impl() { channel_.SetMethodCallHandler(nullptr); if (active_) active_->Stop(); }
 private:
  flutter::TextureRegistrar* textures_;
  flutter::MethodChannel<EncodableValue> channel_;
  std::shared_ptr<PlayerSession> active_;
  int64_t generation_ = 0;
};
LocalPlayer::LocalPlayer(flutter::BinaryMessenger* messenger, flutter::TextureRegistrar* textures)
  : impl_(std::make_unique<Impl>(messenger, textures)) {}
LocalPlayer::~LocalPlayer() = default;

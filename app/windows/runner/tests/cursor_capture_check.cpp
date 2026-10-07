// Explicit non-shipping check. Captures only its own generated-color window.
// Two WGC sessions must independently preserve/remove the Windows pointer.
#include <windows.h>
#include <d3d11_4.h>
#include <dxgi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <iostream>
#include <algorithm>
#include <atomic>
#include <mutex>

namespace {
using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using ::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess;
const char* operation = "start";
int DifferentPixels(ID3D11Device*, ID3D11DeviceContext*, const Direct3D11CaptureFrame&, POINT, std::atomic<int>&);
std::mutex gpu_mutex;
void Require(bool value) { if (!value) throw hresult_error(E_FAIL); }
LRESULT CALLBACK Fixture(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{}; const auto dc = BeginPaint(window, &paint);
    RECT rect{}; GetClientRect(window, &rect);
    const auto brush = CreateSolidBrush(RGB(32, 96, 224));
    FillRect(dc, &rect, brush); DeleteObject(brush); EndPaint(window, &paint);
    return 0;
  }
  if (message == WM_SETCURSOR) { SetCursor(LoadCursorW(nullptr, IDC_ARROW)); return TRUE; }
  return DefWindowProcW(window, message, wparam, lparam);
}
struct Session {
  Direct3D11CaptureFramePool pool{nullptr};
  GraphicsCaptureSession capture{nullptr};
  std::atomic<int> x{220}, y{120}, different{-1};
  std::atomic<HRESULT> error{S_OK};
  std::atomic<int> phase{0};
  event_token token{};
  void Watch(ID3D11Device* device, ID3D11DeviceContext* context) {
    token = pool.FrameArrived([this, device, context](const auto& sender, const auto&) {
      try {
        std::lock_guard<std::mutex> lock(gpu_mutex);
        phase = 1;
        auto frame = sender.TryGetNextFrame();
        if (!frame) return;
        different = DifferentPixels(device, context, frame, {x.load(), y.load()}, phase);
        phase = 8;
        frame.Close();
      } catch (...) { error = to_hresult(); }
    });
  }
  void Close() {
    if (pool) pool.FrameArrived(token);
    if (capture) capture.Close();
    if (pool) pool.Close();
    capture = nullptr; pool = nullptr;
  }
  ~Session() { try { Close(); } catch (...) {} }
};
int DifferentPixels(ID3D11Device* device, ID3D11DeviceContext* context,
                    const Direct3D11CaptureFrame& frame, POINT location, std::atomic<int>& phase) {
  phase = 2;
  com_ptr<ID3D11Texture2D> texture;
  check_hresult(frame.Surface().as<IDirect3DDxgiInterfaceAccess>()->GetInterface(
      __uuidof(ID3D11Texture2D), texture.put_void()));
  D3D11_TEXTURE2D_DESC desc{}; texture->GetDesc(&desc);
  desc.Usage = D3D11_USAGE_STAGING; desc.BindFlags = 0;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ; desc.MiscFlags = 0;
  com_ptr<ID3D11Texture2D> staging;
  phase = 3;
  check_hresult(device->CreateTexture2D(&desc, nullptr, staging.put()));
  context->CopyResource(staging.get(), texture.get());
  D3D11_MAPPED_SUBRESOURCE mapped{};
  phase = 4;
  check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
  int different = 0;
  phase = 5;
  const auto size = frame.ContentSize();
  // The entire source is a known color, so verify pointer pixels throughout
  // the picture without assuming a particular Windows pointer scale.
  (void)location;
  for (int y = 0; y < size.Height; ++y) {
    for (int x = 0; x < size.Width; ++x) {
      if (x < 0 || y < 0 || x >= size.Width || y >= size.Height) continue;
      const auto* pixel = static_cast<const BYTE*>(mapped.pData) + y * mapped.RowPitch + x * 4;
      if (std::abs(static_cast<int>(pixel[0]) - 224) > 10 ||
          std::abs(static_cast<int>(pixel[1]) - 96) > 10 ||
          std::abs(static_cast<int>(pixel[2]) - 32) > 10) ++different;
    }
  }
  context->Unmap(staging.get(), 0);
  return different;
}
void Compare(HWND window, ID3D11Device* device, ID3D11DeviceContext* context,
             Session& original, Session& clean, POINT location) {
  (void)device; (void)context;
  original.x = clean.x = location.x; original.y = clean.y = location.y;
  original.different = clean.different = -1;
  POINT point = location; Require(ClientToScreen(window, &point));
  Require(SetCursorPos(point.x, point.y));
  SetCursor(LoadCursorW(nullptr, IDC_ARROW));
  int original_count = -1, clean_count = -1;
  const auto started = GetTickCount64();
  while (GetTickCount64() - started < 2000) {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    InvalidateRect(window, nullptr, FALSE);
    if (FAILED(original.error.load()) || FAILED(clean.error.load())) {
      std::cout << "Generated event phase: original=" << original.phase << ", clean=" << clean.phase << "\n";
      operation = "original event"; check_hresult(original.error.load());
      operation = "clean event"; check_hresult(clean.error.load());
    }
    if (GetTickCount64() - started > 500) {
      original_count = original.different; clean_count = clean.different;
    }
    if (original_count > 20 && clean_count == 0) return;
    Sleep(10);
  }
  std::cout << "Generated pointer pixels: original=" << original_count << ", clean=" << clean_count << "\n";
  CURSORINFO cursor{}; cursor.cbSize = sizeof(cursor);
  POINT actual{}; RECT bounds{};
  GetCursorInfo(&cursor); GetPhysicalCursorPos(&actual); GetWindowRect(window, &bounds);
  std::cout << "Generated pointer state: showing=" << !!(cursor.flags & CURSOR_SHOWING)
            << " inside=" << !!PtInRect(&bounds, actual)
            << " own=" << (WindowFromPoint(actual) == window)
            << " relative=" << actual.x - bounds.left << "/" << actual.y - bounds.top
            << " expected=" << location.x << "/" << location.y << "\n";
  Require(original_count > 20 && clean_count == 0);
}
}
int wmain() {
  HWND window = nullptr;
  POINT previous{}; const bool restore = GetCursorPos(&previous) != FALSE;
  const char* stage = "create fixture";
  try {
    init_apartment(apartment_type::multi_threaded);
    WNDCLASSW type{}; type.lpfnWndProc = Fixture; type.hInstance = GetModuleHandleW(nullptr);
    type.lpszClassName = L"SpawnAlphaCursorCaptureFixture"; type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    Require(RegisterClassW(&type) != 0);
    window = CreateWindowW(type.lpszClassName, L"SpawnAlpha generated cursor check",
        WS_POPUP | WS_VISIBLE, 100, 100, 640, 360, nullptr, nullptr, type.hInstance, nullptr);
    Require(window != nullptr); ShowWindow(window, SW_SHOW); UpdateWindow(window);
    Require(SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE));
    {
      com_ptr<ID3D11Device> device; com_ptr<ID3D11DeviceContext> context;
      check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
      context.as<ID3D11Multithread>()->SetMultithreadProtected(TRUE);
      com_ptr<IInspectable> inspectable;
      check_hresult(CreateDirect3D11DeviceFromDXGIDevice(device.as<IDXGIDevice>().get(), inspectable.put()));
      auto rt_device = inspectable.as<IDirect3DDevice>();
      GraphicsCaptureItem item{nullptr};
      const auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
      check_hresult(interop->CreateForWindow(window, guid_of<GraphicsCaptureItem>(), put_abi(item)));
      Session original, clean;
      original.pool = Direct3D11CaptureFramePool::CreateFreeThreaded(rt_device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, item.Size());
      clean.pool = Direct3D11CaptureFramePool::CreateFreeThreaded(rt_device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, item.Size());
      original.Watch(device.get(), context.get()); clean.Watch(device.get(), context.get());
      original.capture = original.pool.CreateCaptureSession(item);
      clean.capture = clean.pool.CreateCaptureSession(item);
      stage = "independent cursor flags";
      original.capture.IsCursorCaptureEnabled(true);
      clean.capture.IsCursorCaptureEnabled(false);
      Require(original.capture.IsCursorCaptureEnabled() && !clean.capture.IsCursorCaptureEnabled());
      original.capture.StartCapture(); clean.capture.StartCapture();
      stage = "simultaneous cursor pixels";
      Compare(window, device.get(), context.get(), original, clean, {220, 120});
      Compare(window, device.get(), context.get(), original, clean, {400, 180});
      // Reverse startup order, proving a last-started session cannot suppress
      // the original pointer or leak it into the clean session.
      stage = "recreate frame pools";
      original.Close(); clean.Close();
      original.pool = Direct3D11CaptureFramePool::CreateFreeThreaded(rt_device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, item.Size());
      clean.pool = Direct3D11CaptureFramePool::CreateFreeThreaded(rt_device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, item.Size());
      original.Watch(device.get(), context.get()); clean.Watch(device.get(), context.get());
      original.capture = original.pool.CreateCaptureSession(item);
      clean.capture = clean.pool.CreateCaptureSession(item);
      original.capture.IsCursorCaptureEnabled(true); clean.capture.IsCursorCaptureEnabled(false);
      clean.capture.StartCapture(); original.capture.StartCapture();
      stage = "reverse startup pixels";
      Compare(window, device.get(), context.get(), original, clean, {320, 140});
    }
    DestroyWindow(window); window = nullptr;
    if (restore) SetCursorPos(previous.x, previous.y);
    uninit_apartment();
    std::cout << "Cursor capture check passed: original pointer preserved, clean pixels verified, both startup orders.\n";
    return 0;
  } catch (...) {
    if (window) DestroyWindow(window);
    if (restore) SetCursorPos(previous.x, previous.y);
    std::cerr << "Cursor capture check failed at " << stage << " / " << operation << ": 0x" << std::hex << static_cast<unsigned long>(winrt::to_hresult()) << "\n";
    uninit_apartment(); return 1;
  }
}

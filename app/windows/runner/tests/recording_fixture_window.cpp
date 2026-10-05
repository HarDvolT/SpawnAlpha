// Non-shipping source for the end-to-end Flutter recording check. Generates
// only colored pixels, accepts no input and closes automatically after 30 s.
#include <windows.h>
namespace {
LRESULT CALLBACK Fixture(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{};
    const auto dc = BeginPaint(hwnd, &paint);
    RECT rect{}; GetClientRect(hwnd, &rect);
    const auto brush = CreateSolidBrush(RGB(32, 96, 224));
    FillRect(dc, &rect, brush); DeleteObject(brush); EndPaint(hwnd, &paint);
    return 0;
  }
  if (message == WM_TIMER) { DestroyWindow(hwnd); return 0; }
  if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
  const wchar_t* type = L"SpawnAlphaGeneratedRecordingFixture";
  WNDCLASSW wc{}; wc.hInstance = instance; wc.lpfnWndProc = Fixture; wc.lpszClassName = type;
  if (!RegisterClassW(&wc)) return 1;
  const auto window = CreateWindowW(type, L"SpawnAlpha generated recording fixture",
    WS_OVERLAPPEDWINDOW, 100, 100, 672, 399, nullptr, nullptr, instance, nullptr);
  if (!window) return 1;
  ShowWindow(window, SW_SHOWNOACTIVATE); UpdateWindow(window); SetTimer(window, 1, 30000, nullptr);
  MSG msg{}; while (GetMessageW(&msg, nullptr, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageW(&msg); }
  return 0;
}

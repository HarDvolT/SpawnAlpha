#include "flutter_window.h"

#include <optional>
#include <flutter/plugin_registrar_windows.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  screen_sources_ = RegisterScreenSources(flutter_controller_->engine()->messenger());
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(flutter_controller_->engine()->GetRegistrarForPlugin("ScreenPreview"));
  screen_preview_ = std::make_unique<ScreenPreview>(registrar->messenger(), registrar->texture_registrar());
  floating_prompter_ = std::make_unique<FloatingPrompterHost>(GetHandle(), project_, registrar->messenger());
  screen_recorder_ = std::make_unique<ScreenRecorder>(registrar->messenger());
  recording_hud_ = std::make_unique<RecordingHud>(GetHandle(), project_, registrar->messenger());
  camera_bubble_ = std::make_unique<CameraBubbleHost>(project_, registrar->messenger(), [this] {
    return screen_recorder_ ? screen_recorder_->LatestCamera() : nullptr;
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  screen_recorder_.reset();
  camera_bubble_.reset();
  recording_hud_.reset();
  floating_prompter_.reset();
  screen_preview_.reset();
  screen_sources_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

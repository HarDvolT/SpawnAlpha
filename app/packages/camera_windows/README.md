# camera_windows (vendored)

This is `camera_windows` 0.3.0 from
[flutter/packages](https://github.com/flutter/packages/tree/main/packages/camera/camera_windows),
copied here under its BSD-3-Clause licence ([LICENSE](LICENSE), Copyright 2013 The
Flutter Authors). The app uses it through `dependency_overrides` in `app/pubspec.yaml`.

## SpawnAlpha changes

- `windows/capture_controller.cpp`: records from the microphone chosen in the app,
  or else the Windows default microphone. Upstream always used the first
  microphone Windows lists, which recorded silence on PCs with several inputs.
- `windows/audio_input.{h,cpp}` (new): the `spawnalpha/audio_input` method channel.
  It lists the active microphones, selects the one to record from, and measures a
  microphone's level (Core Audio and WASAPI) for the level meter and voice pacing.
- `windows/camera_plugin.cpp`: registers that channel.
- `windows/CMakeLists.txt`: builds the new files. The upstream unit-test target is
  not vendored.

The Dart code in `lib/` is unchanged. When updating to a newer upstream version,
re-apply these changes and keep the licence notice.

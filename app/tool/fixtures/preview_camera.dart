// Generated camera fixture for widget checks and screenshots only.
import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spawnalpha/src/theme/theme.dart';

// This helper is imported only by widget tests and screenshot tests.
// ignore: invalid_use_of_visible_for_testing_member
class PreviewCamera extends CameraPlatform with MockPlatformInterfaceMixin {
  PreviewCamera(this.name);
  final String name;
  final events = <String>[];
  final errors = StreamController<CameraErrorEvent>.broadcast();
  int next = 0;
  @override
  Future<List<CameraDescription>> availableCameras() async => [
    CameraDescription(
      name: '$name <generated-camera>',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
  ];
  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? preset, {
    bool enableAudio = false,
  }) async {
    events.add(enableAudio ? 'camera-audio' : 'camera-preview');
    return ++next;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Future<void> prepareForVideoRecording() async {}
  @override
  Future<void> dispose(int cameraId) async => events.add('camera-dispose');
  @override
  Widget buildPreview(int cameraId) =>
      ColoredBox(color: SaPalette.dark.stageTintSlower);
}

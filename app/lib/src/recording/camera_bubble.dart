import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'screen_source.dart';

class CameraBubbleHandle {
  const CameraBubbleHandle(this.sessionId);
  final int sessionId;
}

/// The child receives only display metadata and the recording camera texture.
/// It opens no second device and never receives output paths or device IDs.
abstract class CameraBubbles {
  factory CameraBubbles.platform() => Platform.isWindows
      ? const WindowsCameraBubbles()
      : const UnsupportedCameraBubbles();
  bool get supported;
  Future<CameraBubbleHandle> open(ScreenSource source, String cameraName);
  Future<bool> isSafe(CameraBubbleHandle handle);
  Future<void> close(CameraBubbleHandle handle);
}

class WindowsCameraBubbles implements CameraBubbles {
  const WindowsCameraBubbles();
  static const channel = MethodChannel('spawnalpha/camera_bubble');
  @override
  bool get supported => true;
  @override
  Future<CameraBubbleHandle> open(
    ScreenSource source,
    String cameraName,
  ) async {
    final id = await channel.invokeMethod<int>('open', {
      'sourceId': source.id,
      'name': cameraName,
      'diameter': SaPrompter.cameraBubbleSize.round(),
      'readerWidth': SaPrompter.floatingWidth.round(),
      'inset': SaSpace.s6.round(),
      'pollMs': SaDurations.recordingPoll.inMilliseconds,
    });
    if (id == null || id <= 0) {
      throw const FormatException('Missing protected camera preview');
    }
    final handle = CameraBubbleHandle(id);
    try {
      final attempts =
          (SaDurations.beat * 5).inMicroseconds ~/
          SaDurations.previewPoll.inMicroseconds;
      for (var i = 0; i < attempts; ++i) {
        final state = await channel.invokeMapMethod<String, Object?>('status', {
          'sessionId': id,
        });
        if (state?['excluded'] != true) {
          throw const FormatException('Camera preview exclusion unavailable');
        }
        if (state?['ready'] == true) return handle;
        await Future<void>.delayed(SaDurations.previewPoll);
      }
      throw TimeoutException('Protected camera preview unavailable');
    } on Object {
      await close(handle);
      rethrow;
    }
  }

  @override
  Future<bool> isSafe(CameraBubbleHandle handle) async {
    final state = await channel.invokeMapMethod<String, Object?>('status', {
      'sessionId': handle.sessionId,
    });
    return state?['excluded'] == true && state?['ready'] == true;
  }

  @override
  Future<void> close(CameraBubbleHandle handle) =>
      channel.invokeMethod<void>('close', {'sessionId': handle.sessionId});
}

class UnsupportedCameraBubbles implements CameraBubbles {
  const UnsupportedCameraBubbles();
  @override
  bool get supported => false;
  @override
  Future<CameraBubbleHandle> open(
    ScreenSource source,
    String cameraName,
  ) async => throw UnsupportedError('Windows only');
  @override
  Future<bool> isSafe(CameraBubbleHandle handle) async => false;
  @override
  Future<void> close(CameraBubbleHandle handle) async {}
}

class CameraBubbleState {
  const CameraBubbleState({
    this.textureId = -1,
    this.width = 0,
    this.height = 0,
    this.name = 'Camera',
    this.live = false,
  });
  final int textureId, width, height;
  final String name;
  final bool live;
  factory CameraBubbleState.fromJson(Map<Object?, Object?> json) {
    final id = json['textureId'],
        width = json['width'],
        height = json['height'];
    return CameraBubbleState(
      textureId: id is int && id >= 0 ? id : -1,
      width: width is int && width > 0 ? width : 0,
      height: height is int && height > 0 ? height : 0,
      name: json['name'] is String ? json['name'] as String : 'Camera',
      live:
          json['live'] == true &&
          id is int &&
          id >= 0 &&
          width is int &&
          width > 0 &&
          height is int &&
          height > 0,
    );
  }
}

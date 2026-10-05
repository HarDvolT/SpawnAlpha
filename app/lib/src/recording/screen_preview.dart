import 'dart:io';

import 'package:flutter/services.dart';

import 'screen_source.dart';

class PreviewHandle {
  const PreviewHandle({required this.sessionId, required this.textureId, required this.width, required this.height});
  final int sessionId;
  final int textureId;
  final int width;
  final int height;
}

class PreviewStatus {
  const PreviewStatus({this.width = 0, this.height = 0, this.ready = false, this.closed = false, this.failed = false});
  final int width;
  final int height;
  final bool ready;
  final bool closed;
  final bool failed;
}

/// Capture is preview-only: no audio, file writes, telemetry or network traffic.
abstract class ScreenPreviews {
  factory ScreenPreviews.platform() =>
      Platform.isWindows ? const WindowsScreenPreviews() : const UnsupportedScreenPreviews();
  bool get supported;
  Future<PreviewHandle> start(ScreenSource source);
  Future<PreviewStatus> status(PreviewHandle handle);
  Future<void> stop(PreviewHandle handle);
}

class WindowsScreenPreviews implements ScreenPreviews {
  const WindowsScreenPreviews();
  static const channel = MethodChannel('spawnalpha/screen_preview');
  @override
  bool get supported => true;

  @override
  Future<PreviewHandle> start(ScreenSource source) async {
    final info = await channel.invokeMapMethod<String, Object?>('start', {'sourceId': source.id});
    final sessionId = info?['sessionId'];
    final textureId = info?['textureId'];
    final width = info?['width'];
    final height = info?['height'];
    if (sessionId is! int ||
        textureId is! int ||
        textureId < 0 ||
        width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0) {
      // If a partial reply includes a session, still release the native capture.
      if (sessionId is int) await channel.invokeMethod<void>('stop', {'sessionId': sessionId});
      throw const FormatException('Invalid preview reply');
    }
    return PreviewHandle(sessionId: sessionId, textureId: textureId, width: width, height: height);
  }

  @override
  Future<PreviewStatus> status(PreviewHandle handle) async {
    final info = await channel.invokeMapMethod<String, Object?>('status', {'sessionId': handle.sessionId});
    if (info == null) throw const FormatException('Missing preview status');
    return PreviewStatus(
      width: info['width'] as int? ?? 0,
      height: info['height'] as int? ?? 0,
      ready: info['ready'] == true,
      closed: info['closed'] == true,
      failed: info['failed'] == true,
    );
  }

  @override
  Future<void> stop(PreviewHandle handle) => channel.invokeMethod<void>('stop', {'sessionId': handle.sessionId});
}

class UnsupportedScreenPreviews implements ScreenPreviews {
  const UnsupportedScreenPreviews();
  @override
  bool get supported => false;
  @override
  Future<PreviewHandle> start(ScreenSource source) async =>
      throw UnsupportedError('Screen preview is Windows-only for now');
  @override
  Future<PreviewStatus> status(PreviewHandle handle) async => const PreviewStatus(closed: true);
  @override
  Future<void> stop(PreviewHandle handle) async {}
}

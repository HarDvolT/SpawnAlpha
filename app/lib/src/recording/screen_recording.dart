import 'dart:io';

import 'package:flutter/services.dart';

import 'screen_source.dart';

enum ScreenRecordingPhase {
  starting,
  recording,
  paused,
  saving,
  finished,
  failed,
}

enum ScreenRecordingReason {
  none,
  cancelled,
  source,
  microphone,
  encoder,
  camera,
  systemAudio,
}

class ScreenRecordingHandle {
  const ScreenRecordingHandle(this.sessionId);
  final int sessionId;
}

class ScreenRecordingStatus {
  const ScreenRecordingStatus({
    required this.phase,
    this.reason = ScreenRecordingReason.none,
    this.width = 0,
    this.height = 0,
    this.frames = 0,
    this.audioFrames = 0,
    this.cameraFrames = 0,
    this.systemAudioFrames = 0,
    this.duration = Duration.zero,
    this.peakDb = -100,
    this.rmsDb = -100,
    this.loudestRmsDb = -100,
    this.loudestSystemRmsDb = -100,
  });
  final ScreenRecordingPhase phase;
  final ScreenRecordingReason reason;
  final int width, height, frames, audioFrames, cameraFrames, systemAudioFrames;
  final Duration duration;
  final double peakDb, rmsDb, loudestRmsDb, loudestSystemRmsDb;
  bool get terminal =>
      phase == ScreenRecordingPhase.finished ||
      phase == ScreenRecordingPhase.failed;
}

/// Owns the Windows GPU recorder. The caller chooses the source, microphone and
/// a new local path. Start/stop are nonblocking; status reports safe finalization.
abstract class ScreenRecordings {
  factory ScreenRecordings.platform() => Platform.isWindows
      ? const WindowsScreenRecordings()
      : const UnsupportedScreenRecordings();
  bool get supported;
  Future<ScreenRecordingHandle> start({
    required ScreenSource source,
    required String path,
    required bool recordAudio,
    bool recordSystemAudio = false,
    String? microphoneId,
    String? cameraId,
    String? cameraPath,
  });
  Future<ScreenRecordingStatus> status(ScreenRecordingHandle handle);
  Future<void> stop(ScreenRecordingHandle handle);
  Future<void> pause(ScreenRecordingHandle handle, bool paused);

  /// Stops and joins the native worker before any capture protection is removed.
  Future<void> release(ScreenRecordingHandle handle);
}

class WindowsScreenRecordings implements ScreenRecordings {
  const WindowsScreenRecordings();
  static const channel = MethodChannel('spawnalpha/screen_recording');
  @override
  bool get supported => true;
  @override
  Future<ScreenRecordingHandle> start({
    required ScreenSource source,
    required String path,
    required bool recordAudio,
    bool recordSystemAudio = false,
    String? microphoneId,
    String? cameraId,
    String? cameraPath,
  }) async {
    if ((cameraId == null) != (cameraPath == null) ||
        cameraId == '' ||
        cameraPath == '' ||
        cameraPath == path) {
      throw ArgumentError('Choose a camera and a separate new file together');
    }
    final info = await channel.invokeMapMethod<String, Object?>('start', {
      'sourceId': source.id,
      'path': path,
      'recordAudio': recordAudio,
      'recordSystemAudio': recordSystemAudio,
      'microphoneId': ?microphoneId,
      'cameraId': ?cameraId,
      'cameraPath': ?cameraPath,
    });
    final id = info?['sessionId'];
    if (id is! int || id <= 0) {
      throw const FormatException('Invalid recording session');
    }
    return ScreenRecordingHandle(id);
  }

  @override
  Future<ScreenRecordingStatus> status(ScreenRecordingHandle handle) async {
    final info = await channel.invokeMapMethod<String, Object?>('status', {
      'sessionId': handle.sessionId,
    });
    if (info == null) throw const FormatException('Missing recording status');
    final phase = ScreenRecordingPhase.values
        .where((v) => v.name == info['state'])
        .firstOrNull;
    final reason = ScreenRecordingReason.values
        .where((v) => v.name == info['reason'])
        .firstOrNull;
    if (phase == null || reason == null) {
      throw const FormatException('Invalid recording status');
    }
    int integer(String name) {
      final value = info[name];
      if (value == null && phase == ScreenRecordingPhase.failed) return 0;
      if (value is! int || value < 0) {
        throw const FormatException('Invalid recording count');
      }
      return value;
    }

    double level(String name) {
      final value = info[name];
      if (value == null && phase == ScreenRecordingPhase.failed) return -100;
      if (value is! num || !value.isFinite) {
        throw const FormatException('Invalid recording level');
      }
      return value.toDouble().clamp(-100, 0);
    }

    return ScreenRecordingStatus(
      phase: phase,
      reason: reason,
      width: integer('width'),
      height: integer('height'),
      frames: integer('frames'),
      audioFrames: integer('audioFrames'),
      cameraFrames: info['cameraFrames'] == null ? 0 : integer('cameraFrames'),
      systemAudioFrames: info['systemAudioFrames'] == null
          ? 0
          : integer('systemAudioFrames'),
      duration: Duration(microseconds: integer('durationUs')),
      peakDb: level('peakDb'),
      rmsDb: level('rmsDb'),
      loudestRmsDb: level('loudestRmsDb'),
      loudestSystemRmsDb: info['loudestSystemRmsDb'] == null
          ? -100
          : level('loudestSystemRmsDb'),
    );
  }

  @override
  Future<void> stop(ScreenRecordingHandle handle) =>
      channel.invokeMethod<void>('stop', {'sessionId': handle.sessionId});
  @override
  Future<void> pause(ScreenRecordingHandle handle, bool paused) =>
      channel.invokeMethod<void>('pause', {
        'sessionId': handle.sessionId,
        'paused': paused,
      });
  @override
  Future<void> release(ScreenRecordingHandle handle) =>
      channel.invokeMethod<void>('release', {'sessionId': handle.sessionId});
}

class UnsupportedScreenRecordings implements ScreenRecordings {
  const UnsupportedScreenRecordings();
  @override
  bool get supported => false;
  @override
  Future<ScreenRecordingHandle> start({
    required ScreenSource source,
    required String path,
    required bool recordAudio,
    bool recordSystemAudio = false,
    String? microphoneId,
    String? cameraId,
    String? cameraPath,
  }) async => throw UnsupportedError('Windows only');
  @override
  Future<ScreenRecordingStatus> status(ScreenRecordingHandle handle) async =>
      const ScreenRecordingStatus(
        phase: ScreenRecordingPhase.failed,
        reason: ScreenRecordingReason.cancelled,
      );
  @override
  Future<void> stop(ScreenRecordingHandle handle) async {}
  @override
  Future<void> pause(ScreenRecordingHandle handle, bool paused) async {}
  @override
  Future<void> release(ScreenRecordingHandle handle) async {}
}

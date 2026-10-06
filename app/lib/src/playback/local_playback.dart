import 'dart:io';

import 'package:flutter/services.dart';

class PlaybackHandle {
  const PlaybackHandle(this.sessionId, this.textureId);
  final int sessionId, textureId;
}

class PlaybackStatus {
  const PlaybackStatus({
    this.ready = false,
    this.closed = false,
    this.failed = false,
    this.playing = false,
    this.buffering = false,
    this.ended = false,
    this.width = 0,
    this.height = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.frames = 0,
  });
  final bool ready, closed, failed, playing, buffering, ended;
  final int width, height, frames;
  final Duration position, duration;
}

abstract class LocalPlayback {
  factory LocalPlayback.platform() => Platform.isWindows
      ? const WindowsLocalPlayback()
      : const UnavailablePlayback();
  bool get supported;
  Future<PlaybackHandle> open(String path);
  Future<PlaybackStatus> status(PlaybackHandle handle);
  Future<void> play(PlaybackHandle handle);
  Future<void> pause(PlaybackHandle handle);
  Future<void> seek(PlaybackHandle handle, Duration position);
  Future<void> mute(PlaybackHandle handle, bool muted);
  Future<void> close(PlaybackHandle handle);
}

class WindowsLocalPlayback implements LocalPlayback {
  const WindowsLocalPlayback();
  static const channel = MethodChannel('spawnalpha/player');
  @override
  bool get supported => true;
  @override
  Future<PlaybackHandle> open(String path) async {
    // Native validation also checks the drive and every component for links.
    if (!RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
        path.substring(2).contains(':') ||
        path.contains('\u0000')) {
      throw const FormatException('Choose a local video');
    }
    final info = await channel.invokeMapMethod<String, Object?>('open', {
      'path': path,
    });
    final id = info?['sessionId'], texture = info?['textureId'];
    if (id is! int || id <= 0 || texture is! int || texture < 0) {
      if (id is int) {
        await channel.invokeMethod<void>('close', {'sessionId': id});
      }
      throw const FormatException('Invalid playback reply');
    }
    return PlaybackHandle(id, texture);
  }

  @override
  Future<PlaybackStatus> status(PlaybackHandle handle) async {
    final info = await channel.invokeMapMethod<String, Object?>('status', {
      'sessionId': handle.sessionId,
    });
    if (info == null) throw const FormatException('Missing playback status');
    if (info['closed'] == true) return const PlaybackStatus(closed: true);
    int number(String key, int maximum) {
      final value = info[key];
      if (value is! int || value < 0 || value > maximum) {
        throw const FormatException('Invalid playback status');
      }
      return value;
    }

    final duration = number(
      'durationUs',
      const Duration(hours: 24).inMicroseconds,
    );
    return PlaybackStatus(
      ready: info['ready'] == true,
      failed: info['failed'] == true,
      playing: info['playing'] == true,
      buffering: info['buffering'] == true,
      ended: info['ended'] == true,
      width: number('width', 16384),
      height: number('height', 16384),
      position: Duration(
        microseconds: number(
          'positionUs',
          duration + const Duration(seconds: 1).inMicroseconds,
        ),
      ),
      duration: Duration(microseconds: duration),
      frames: number('frames', 100000000),
    );
  }

  Future<void> _call(
    String method,
    PlaybackHandle handle, [
    Map<String, Object?> extra = const {},
  ]) => channel.invokeMethod<void>(method, {
    'sessionId': handle.sessionId,
    ...extra,
  });
  @override
  Future<void> play(PlaybackHandle handle) => _call('play', handle);
  @override
  Future<void> pause(PlaybackHandle handle) => _call('pause', handle);
  @override
  Future<void> seek(PlaybackHandle handle, Duration position) =>
      _call('seek', handle, {'positionUs': position.inMicroseconds});
  @override
  Future<void> mute(PlaybackHandle handle, bool muted) =>
      _call('mute', handle, {'muted': muted});
  @override
  Future<void> close(PlaybackHandle handle) => _call('close', handle);
}

class UnavailablePlayback implements LocalPlayback {
  const UnavailablePlayback();
  @override
  bool get supported => false;
  @override
  Future<PlaybackHandle> open(String path) async =>
      throw UnsupportedError('Playback is available on Windows first');
  @override
  Future<PlaybackStatus> status(PlaybackHandle handle) async =>
      const PlaybackStatus(closed: true);
  @override
  Future<void> play(PlaybackHandle handle) async {}
  @override
  Future<void> pause(PlaybackHandle handle) async {}
  @override
  Future<void> seek(PlaybackHandle handle, Duration position) async {}
  @override
  Future<void> mute(PlaybackHandle handle, bool muted) async {}
  @override
  Future<void> close(PlaybackHandle handle) async {}
}

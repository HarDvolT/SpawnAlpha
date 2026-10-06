// Only opens generated fixture video. No camera, microphone or owner take.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/playback/local_playback.dart';
import 'package:spawnalpha/src/playback/playback_controller.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';

// Exercise the real platform, keeping only generated fixture tones muted.
class MutedFixturePlayback implements LocalPlayback {
  const MutedFixturePlayback(this.backend);
  final WindowsLocalPlayback backend;
  @override
  bool get supported => true;
  @override
  Future<PlaybackHandle> open(String path) => backend.open(path);
  @override
  Future<PlaybackStatus> status(PlaybackHandle handle) =>
      backend.status(handle);
  @override
  Future<void> play(PlaybackHandle handle) => backend.play(handle);
  @override
  Future<void> pause(PlaybackHandle handle) => backend.pause(handle);
  @override
  Future<void> seek(PlaybackHandle handle, Duration position) =>
      backend.seek(handle, position);
  @override
  Future<void> mute(PlaybackHandle handle, bool muted) =>
      backend.mute(handle, true);
  @override
  Future<void> close(PlaybackHandle handle) => backend.close(handle);
}

void require(bool value) {
  if (!value) throw StateError('Generated playback check failed');
}

Future<PlaybackStatus> waitFor(
  WindowsLocalPlayback backend,
  PlaybackHandle handle,
  bool Function(PlaybackStatus) predicate,
) async {
  for (var i = 0; i < 100; ++i) {
    final status = await backend.status(handle);
    if (status.failed) {
      final info = await WindowsLocalPlayback.channel
          .invokeMapMethod<String, Object?>('status', {
            'sessionId': handle.sessionId,
          });
      // Fixed native stage and numeric HRESULT only; no paths or media text.
      // ignore: avoid_print
      print(
        'Player platform failure ${info?['failureStage']}: ${info?['failureCode']}',
      );
    }
    require(!status.failed && !status.closed);
    if (predicate(status)) return status;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Generated playback timed out');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Checking local playback…'))),
    ),
  );
  var stage = 'find generated fixture';
  PlaybackHandle? handle;
  TakePlaybackController? excerptPlayer;
  const backend = WindowsLocalPlayback();
  try {
    final fixture = File(
      '${Directory.current.path}/build/playback/generated.mp4',
    );
    require(await fixture.exists());
    stage = 'copy Unicode fixture';
    final unicode = await fixture.copy(
      '${fixture.parent.path}/generated-é-العربية.mp4',
    );
    for (var i = 0; i < 3; ++i) {
      stage = 'open local channel';
      handle = await backend.open(unicode.path);
      stage = 'wait for platform media';
      var status = await waitFor(
        backend,
        handle,
        (s) => s.ready && s.frames > 0,
      );
      require(!status.playing && status.duration >= const Duration(seconds: 3));
      stage = 'play and receive video frames';
      await backend.mute(
        handle,
        true,
      ); // Generated tones need not disturb the owner.
      await backend.play(handle);
      status = await waitFor(
        backend,
        handle,
        (s) => s.frames > 2 && s.position > const Duration(milliseconds: 300),
      );
      require(status.width == 640 && status.height == 360);
      stage = 'pause';
      await backend.pause(handle);
      status = await waitFor(backend, handle, (s) => !s.playing);
      final paused = status.position;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      require(
        ((await backend.status(handle)).position - paused).abs() <
            const Duration(milliseconds: 100),
      );
      stage = 'seek while paused';
      final frames = status.frames;
      await backend.seek(handle, const Duration(milliseconds: 2500));
      status = await waitFor(
        backend,
        handle,
        (s) =>
            s.position >= const Duration(milliseconds: 2400) &&
            s.frames > frames,
      );
      require(!status.playing);
      stage = 'resume and finish';
      await backend.play(handle);
      await waitFor(backend, handle, (s) => s.ended);
      stage = 'close';
      await backend.close(handle);
      require((await backend.status(handle)).closed);
      handle = null;
    }
    stage = 'bounded controller phrase preview';
    excerptPlayer = TakePlaybackController(const MutedFixturePlayback(backend));
    await excerptPlayer.open(unicode.path);
    handle = excerptPlayer.handle;
    require(handle != null);
    await waitFor(backend, handle!, (s) => s.ready && s.frames > 0);
    await excerptPlayer.poll();
    require(excerptPlayer.ready && !excerptPlayer.status.playing);
    await excerptPlayer.preview(
      SourceRange(
        start: const Duration(milliseconds: 500),
        end: const Duration(milliseconds: 1200),
      ),
    );
    var pausedExcerpt = await waitFor(
      backend,
      handle,
      (s) => !s.playing && s.position >= const Duration(milliseconds: 1200),
    );
    require(
      pausedExcerpt.position < const Duration(milliseconds: 1900) &&
          !excerptPlayer.previewing,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    require(
      ((await backend.status(handle)).position - pausedExcerpt.position).abs() <
          const Duration(milliseconds: 100),
    );
    excerptPlayer.dispose();
    excerptPlayer = null;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    require((await backend.status(handle)).closed);
    handle = null;
    stage = 'reject unavailable and remote inputs';
    for (final path in [
      'https://example.com/video.mp4',
      r'\\server\share\video.mp4',
      '${fixture.parent.path}/missing.mp4',
    ]) {
      var rejected = false;
      try {
        await backend.open(path);
      } on Object {
        rejected = true;
      }
      require(rejected);
    }
    // ignore: avoid_print
    print(
      'Local playback check passed: Unicode file, paused start, decoded frames, pause, seek, end, bounded phrase preview/auto-pause, repeated close and remote rejection.',
    );
  } on Object {
    // Static stage only; do not print private paths or OS exception messages.
    // ignore: avoid_print
    print('Local playback check failed at $stage.');
  } finally {
    excerptPlayer?.dispose();
    if (handle != null) await backend.close(handle);
  }
}

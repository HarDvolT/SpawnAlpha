import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/playback/local_playback.dart';
import 'package:spawnalpha/src/playback/playback_controller.dart';

class FakePlayback implements LocalPlayback {
  @override
  bool get supported => true;
  Completer<PlaybackHandle>? delayed;
  Completer<void>? pendingPlay;
  final closed = <PlaybackHandle>[];
  final commands = <String>[];
  PlaybackStatus value = const PlaybackStatus(
    ready: true,
    width: 640,
    height: 360,
    duration: Duration(seconds: 4),
  );
  @override
  Future<PlaybackHandle> open(String path) async =>
      delayed != null ? delayed!.future : const PlaybackHandle(1, 1);
  @override
  Future<PlaybackStatus> status(PlaybackHandle handle) async => value;
  @override
  Future<void> play(PlaybackHandle handle) async {
    commands.add('play');
    await pendingPlay?.future;
  }

  @override
  Future<void> pause(PlaybackHandle handle) async {
    commands.add('pause');
  }

  @override
  Future<void> seek(PlaybackHandle handle, Duration position) async {
    commands.add('seek:${position.inMicroseconds}');
  }

  @override
  Future<void> mute(PlaybackHandle handle, bool muted) async {
    commands.add('mute:$muted');
  }

  @override
  Future<void> close(PlaybackHandle handle) async {
    closed.add(handle);
  }
}

void main() {
  test('background pause waits for a pending play', () async {
    final fake = FakePlayback()..pendingPlay = Completer<void>();
    final player = TakePlaybackController(fake);
    await player.open('generated');
    final playing = player.toggle();
    final pausing = player.pause();
    expect(fake.commands, ['play']);
    fake.pendingPlay!.complete();
    await Future.wait([playing, pausing]);
    expect(fake.commands, ['play', 'pause']);
    expect(player.commanding, isFalse);
    player.dispose();
  });
  test('queued background pause cannot affect a replacement session', () async {
    final fake = FakePlayback()..pendingPlay = Completer<void>();
    final player = TakePlaybackController(fake);
    await player.open('first generated');
    final playing = player.toggle(), pausing = player.pause();
    await player.open('second generated');
    // The fake deliberately reuses the same native handle: generation matters.
    fake.pendingPlay!.complete();
    await Future.wait([playing, pausing]);
    expect(fake.commands, ['play']);
    expect(player.ready, isTrue);
    expect(player.commanding, isFalse);
    player.dispose();
  });
  test('disposing during queued pause closes without a late command', () async {
    final fake = FakePlayback()..pendingPlay = Completer<void>();
    final player = TakePlaybackController(fake);
    await player.open('generated');
    final playing = player.toggle(), pausing = player.pause();
    player.dispose();
    fake.pendingPlay!.complete();
    await Future.wait([playing, pausing]);
    expect(fake.commands, ['play']);
    expect(fake.closed, [const PlaybackHandle(1, 1)]);
  });
  test('paused start, bounded seek, mute, replay and close', () async {
    final fake = FakePlayback(),
        player = TakePlaybackController(FakePlayback());
    player.dispose();
    final owned = TakePlaybackController(fake);
    await owned.open('generated');
    expect(owned.ready, isTrue);
    expect(fake.commands, isEmpty);
    await owned.toggle();
    await owned.seek(const Duration(seconds: 20));
    await owned.toggleMute();
    fake.value = const PlaybackStatus(
      ready: true,
      ended: true,
      position: Duration(seconds: 4),
      duration: Duration(seconds: 4),
    );
    await owned.poll();
    await owned.toggle();
    expect(fake.commands, [
      'play',
      'seek:4000000',
      'mute:true',
      'seek:0',
      'play',
    ]);
    owned.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(fake.closed.length, 1);
  });
  test('late open after disposal is closed and never polled', () async {
    final fake = FakePlayback()..delayed = Completer<PlaybackHandle>();
    final player = TakePlaybackController(fake);
    final pending = player.open('generated');
    await Future<void>.delayed(Duration.zero);
    player.dispose();
    const handle = PlaybackHandle(5, 5);
    fake.delayed!.complete(handle);
    await pending;
    expect(fake.closed, [handle]);
    expect(fake.commands, isEmpty);
  });
  test('decode failure closes media and can be retried', () async {
    final fake = FakePlayback()..value = const PlaybackStatus(failed: true);
    final player = TakePlaybackController(fake);
    await player.open('generated');
    expect(player.problem, isNotNull);
    expect(player.handle, isNull);
    expect(fake.closed.length, 1);
    fake.value = const PlaybackStatus(
      ready: true,
      duration: Duration(seconds: 4),
    );
    await player.open('generated');
    expect(player.problem, isNull);
    expect(player.ready, isTrue);
    player.dispose();
  });
}

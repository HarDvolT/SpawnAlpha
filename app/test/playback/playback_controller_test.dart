import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/playback/local_playback.dart';
import 'package:spawnalpha/src/playback/playback_controller.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';

class FakePlayback implements LocalPlayback {
  @override
  bool get supported => true;
  Completer<PlaybackHandle>? delayed;
  Completer<void>? pendingPlay;
  Completer<void>? pendingSeek;
  Completer<PlaybackStatus>? pendingStatus;
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
  Future<PlaybackStatus> status(PlaybackHandle handle) async =>
      pendingStatus == null ? value : pendingStatus!.future;
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
    await pendingSeek?.future;
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
  test(
    'explicit phrase preview turns sound on and pauses at its bound',
    () async {
      final fake = FakePlayback();
      final owned = TakePlaybackController(fake);
      await owned.open('generated');
      await owned.toggleMute();
      await owned.preview(
        SourceRange(
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 2),
        ),
      );
      expect(fake.commands, [
        'mute:true',
        'pause',
        'seek:1000000',
        'mute:false',
        'play',
      ]);
      expect(owned.muted, isFalse);
      expect(owned.previewing, isTrue);
      fake.value = const PlaybackStatus(
        ready: true,
        playing: true,
        position: Duration(milliseconds: 2100),
        duration: Duration(seconds: 4),
      );
      await owned.poll();
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands.last, 'pause');
      expect(owned.previewing, isFalse);
      owned.dispose();
    },
  );
  test(
    'out-of-file preview never plays and a clamped excerpt ends normally',
    () async {
      final fake = FakePlayback();
      final player = TakePlaybackController(fake);
      await player.open('generated');
      await player.preview(
        SourceRange(
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 5),
        ),
      );
      expect(fake.commands, isEmpty);
      await player.preview(
        SourceRange(
          start: const Duration(seconds: 3),
          end: const Duration(seconds: 5),
        ),
      );
      expect(player.previewing, isTrue);
      fake.value = const PlaybackStatus(
        ready: true,
        ended: true,
        position: Duration(seconds: 4),
        duration: Duration(seconds: 4),
      );
      await player.poll();
      expect(player.previewing, isFalse);
      player.dispose();
    },
  );
  test('backgrounding during an excerpt seek cancels any late play', () async {
    final fake = FakePlayback()..pendingSeek = Completer<void>();
    final player = TakePlaybackController(fake);
    await player.open('generated');
    final preview = player.preview(
      SourceRange(
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 2),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final pausing = player.pause();
    fake.pendingSeek!.complete();
    await Future.wait([preview, pausing]);
    expect(fake.commands, ['pause', 'seek:1000000', 'pause']);
    expect(player.previewing, isFalse);
    player.dispose();
  });
  test(
    'replacing or disposing during an excerpt cannot play on a reused handle',
    () async {
      for (final dispose in [false, true]) {
        final fake = FakePlayback()..pendingSeek = Completer<void>();
        final player = TakePlaybackController(fake);
        await player.open('first generated');
        final preview = player.preview(
          SourceRange(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        if (dispose) {
          player.dispose();
        } else {
          await player.open('second generated');
        }
        fake.pendingSeek!.complete();
        await preview;
        expect(fake.commands, ['pause', 'seek:1000000']);
        expect(player.previewing, isFalse);
        if (!dispose) player.dispose();
      }
    },
  );
  test(
    'the latest queued excerpt owns playback and manual seeking ends it',
    () async {
      final fake = FakePlayback()..pendingPlay = Completer<void>();
      final player = TakePlaybackController(fake);
      await player.open('generated');
      final playing = player.toggle();
      final first = player.preview(
        SourceRange(
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 2),
        ),
      );
      final latest = player.preview(
        SourceRange(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 3),
        ),
      );
      fake.pendingPlay!.complete();
      await Future.wait([playing, first, latest]);
      expect(fake.commands, [
        'play',
        'pause',
        'seek:2000000',
        'mute:false',
        'play',
      ]);
      expect(player.previewing, isTrue);
      await player.seek(Duration.zero);
      expect(player.previewing, isFalse);
      player.dispose();
    },
  );
  test(
    'late poll and replay seek cannot affect a replacement generation',
    () async {
      final fake = FakePlayback();
      final owned = TakePlaybackController(fake);
      await owned.open('first generated');
      fake.pendingStatus = Completer<PlaybackStatus>();
      final pendingStatus = fake.pendingStatus!;
      final polling = owned.poll();
      fake.pendingStatus = null;
      await owned.open('second generated');
      pendingStatus.complete(const PlaybackStatus(failed: true));
      await polling;
      await owned.poll();
      expect(owned.ready, isTrue);
      expect(owned.problem, isNull);
      fake.value = const PlaybackStatus(
        ready: true,
        ended: true,
        duration: Duration(seconds: 4),
      );
      await owned.poll();
      fake.pendingSeek = Completer<void>();
      final replaying = owned.toggle();
      await Future<void>.delayed(Duration.zero);
      await owned.open('third generated');
      fake.pendingSeek!.complete();
      await replaying;
      expect(fake.commands, ['seek:0']);
      owned.dispose();
    },
  );
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

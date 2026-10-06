import 'dart:async';

import 'package:flutter/foundation.dart';

import '../theme/tokens.g.dart';
import 'local_playback.dart';

/// Owns late opens, polling and commands. A removed view never keeps playing.
class TakePlaybackController extends ChangeNotifier {
  TakePlaybackController(this.backend);
  final LocalPlayback backend;
  PlaybackHandle? handle;
  PlaybackStatus status = const PlaybackStatus();
  bool loading = false, commanding = false, muted = false;
  String? problem;
  bool _disposed = false;
  int _generation = 0;
  Timer? _timer;
  bool _polling = false;
  DateTime? _opened;
  bool get ready =>
      status.ready &&
      !status.failed &&
      !status.closed &&
      handle != null &&
      !loading;
  Future<void> _close(PlaybackHandle? value) async {
    if (value == null) return;
    try {
      await backend.close(value);
    } on Object {
      /* Generic UI only. */
    }
  }

  Future<void> open(String path) async {
    if (_disposed) return;
    final generation = ++_generation;
    _timer?.cancel();
    final previous = handle;
    handle = null;
    loading = true;
    problem = null;
    status = const PlaybackStatus();
    commanding = false;
    muted = false;
    notifyListeners();
    await _close(previous);
    if (_disposed || generation != _generation) return;
    try {
      final opened = await backend.open(path);
      if (_disposed || generation != _generation) {
        await _close(opened);
        return;
      }
      handle = opened;
      _opened = DateTime.now();
      await poll();
      if (_disposed || generation != _generation) return;
      if (handle != opened) return;
      _timer = Timer.periodic(
        SaDurations.previewPoll,
        (_) => unawaited(poll()),
      );
    } on Object {
      if (_disposed || generation != _generation) return;
      loading = false;
      problem = 'This video could not be played. Your original is safe. Try again or open the file.';
      notifyListeners();
    }
  }

  Future<void> poll() async {
    final current = handle;
    if (_disposed || current == null || _polling) return;
    _polling = true;
    try {
      final next = await backend.status(current);
      if (_disposed || handle != current) return;
      status = next;
      if (next.ready) loading = false;
      final timedOut =
          loading &&
          DateTime.now().difference(_opened!) > const Duration(seconds: 15);
      if (next.failed || next.closed || timedOut) {
        loading = false;
        _timer?.cancel();
        handle = null;
        await _close(current);
        problem = 'This video could not be played. Your original is safe. Try again or open the file.';
      }
      if (!_disposed && (handle == current || handle == null)) {
        notifyListeners();
      }
    } on Object {
      if (_disposed || handle != current) return;
      loading = false;
      _timer?.cancel();
      handle = null;
      await _close(current);
      problem = 'Playback stopped. Your file is safe. Try again.';
      if (!_disposed) notifyListeners();
    } finally {
      _polling = false;
    }
  }

  Future<void> _command(Future<void> Function(PlaybackHandle) action) async {
    final current = handle;
    if (!ready || commanding || current == null || _disposed) return;
    commanding = true;
    notifyListeners();
    try {
      await action(current);
      if (!_disposed && handle == current) await poll();
    } on Object {
      if (!_disposed && handle == current) {
        problem = 'That playback control did not work. Try again.';
      }
    } finally {
      if (!_disposed && handle == current) {
        commanding = false;
        notifyListeners();
      }
    }
  }

  Future<void> toggle() => _command((current) async {
    if (status.playing) {
      await backend.pause(current);
    } else {
      if (status.ended || status.position >= status.duration) {
        await backend.seek(current, Duration.zero);
      }
      await backend.play(current);
    }
  });
  Future<void> pause() => _command(backend.pause);
  Future<void> seek(Duration position) => _command(
    (current) => backend.seek(
      current,
      Duration(
        microseconds: position.inMicroseconds.clamp(
          0,
          status.duration.inMicroseconds,
        ),
      ),
    ),
  );
  Future<void> toggleMute() => _command((current) async {
    final next = !muted;
    await backend.mute(current, next);
    if (!_disposed && handle == current) muted = next;
  });
  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    final current = handle;
    handle = null;
    unawaited(_close(current));
    super.dispose();
  }
}

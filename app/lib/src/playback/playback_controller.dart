import 'dart:async';

import 'package:flutter/foundation.dart';

import '../theme/tokens.g.dart';
import '../model/cut_plan.dart';
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
  Completer<void>? _commandCompletion;
  DateTime? _opened;
  Duration? _previewEnd;
  int _previewGeneration = 0;
  bool get previewing => _previewEnd != null;
  bool _owns(PlaybackHandle current, int generation) =>
      !_disposed && generation == _generation && handle == current;
  void _cancelPreview() {
    _previewEnd = null;
    ++_previewGeneration;
  }

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
    _cancelPreview();
    _timer?.cancel();
    final previous = handle;
    handle = null;
    loading = true;
    problem = null;
    status = const PlaybackStatus();
    commanding = false;
    _commandCompletion = null;
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
    final current = handle, generation = _generation;
    if (_disposed || current == null || _polling) return;
    _polling = true;
    try {
      final next = await backend.status(current);
      if (!_owns(current, generation)) return;
      status = next;
      if (next.ready) loading = false;
      if (next.ended) _cancelPreview();
      if (_previewEnd != null &&
          next.playing &&
          next.position >= _previewEnd!) {
        _previewEnd = null;
        // Never await our own command completion from a command's status poll.
        unawaited(pause());
      }
      final timedOut =
          loading &&
          DateTime.now().difference(_opened!) > const Duration(seconds: 15);
      if (next.failed || next.closed || timedOut) {
        loading = false;
        _cancelPreview();
        _timer?.cancel();
        handle = null;
        await _close(current);
        problem = 'This video could not be played. Your original is safe. Try again or open the file.';
      }
      if (!_disposed &&
          generation == _generation &&
          (handle == current || handle == null)) {
        notifyListeners();
      }
    } on Object {
      if (!_owns(current, generation)) return;
      loading = false;
      _cancelPreview();
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
    final current = handle, generation = _generation;
    if (!ready || commanding || current == null || _disposed) return;
    final completion = _commandCompletion = Completer<void>();
    commanding = true;
    notifyListeners();
    try {
      await action(current);
      if (!_disposed && generation == _generation && handle == current) {
        await poll();
      }
    } on Object {
      if (!_disposed && generation == _generation && handle == current) {
        problem = 'That playback control did not work. Try again.';
      }
    } finally {
      if (!_disposed && generation == _generation && handle == current) {
        commanding = false;
        notifyListeners();
      }
      completion.complete();
      if (identical(_commandCompletion, completion)) _commandCompletion = null;
    }
  }

  Future<void> toggle() {
    _cancelPreview();
    final generation = _generation;
    return _command((current) async {
      if (status.playing) {
        await backend.pause(current);
      } else {
        if (status.ended || status.position >= status.duration) {
          await backend.seek(current, Duration.zero);
          if (!_owns(current, generation)) return;
        }
        await backend.play(current);
      }
    });
  }

  Future<void> pause() async {
    _cancelPreview();
    final current = handle, generation = _generation;
    if (!ready || current == null || _disposed) return;
    // Backgrounding can arrive while Play, Seek or Mute is awaiting the platform.
    // Preserve the pause until those commands finish, on this session only.
    while (commanding) {
      final completion = _commandCompletion;
      if (completion == null) return;
      await completion.future;
      if (_disposed || generation != _generation || handle != current) return;
    }
    if (!_disposed && generation == _generation && handle == current) {
      _cancelPreview();
      await _command(backend.pause);
    }
  }

  Future<void> seek(Duration position) {
    _cancelPreview();
    return _command(
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
  }

  Future<void> preview(SourceRange excerpt) async {
    final current = handle, generation = _generation;
    if (!ready ||
        current == null ||
        _disposed ||
        excerpt.start >= status.duration) {
      return;
    }
    final request = ++_previewGeneration;
    while (commanding) {
      final completion = _commandCompletion;
      if (completion == null) return;
      await completion.future;
      if (!_owns(current, generation) || request != _previewGeneration) return;
    }
    bool ownsRequest() =>
        _owns(current, generation) && request == _previewGeneration;
    final end = excerpt.end > status.duration ? status.duration : excerpt.end;
    await _command((player) async {
      await backend.pause(player);
      if (!ownsRequest()) return;
      await backend.seek(player, excerpt.start);
      if (!ownsRequest()) return;
      await backend.mute(player, false);
      if (!ownsRequest()) return;
      muted = false;
      _previewEnd = end;
      await backend.play(player);
    });
    if (ownsRequest() && problem != null) _cancelPreview();
  }

  Future<void> toggleMute() {
    final generation = _generation;
    return _command((current) async {
      final next = !muted;
      await backend.mute(current, next);
      if (_owns(current, generation)) muted = next;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPreview();
    ++_generation;
    _timer?.cancel();
    final current = handle;
    handle = null;
    unawaited(_close(current));
    super.dispose();
  }
}

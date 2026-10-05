import 'dart:async';

import 'package:flutter/foundation.dart';

import '../theme/tokens.g.dart';
import 'screen_preview.dart';
import 'screen_source.dart';

enum PreviewPhase { starting, live, unavailable }

/// Owns native capture lifetime and status polling; widgets only render it.
/// A generation guard releases late replies after retry, source change or exit.
class ScreenPreviewController extends ChangeNotifier {
  ScreenPreviewController(this.backend);
  final ScreenPreviews backend;
  PreviewHandle? _handle;
  Timer? _poll;
  Timer? _firstFrameDeadline;
  int _generation = 0;
  bool _disposed = false;
  bool _polling = false;
  PreviewPhase _phase = PreviewPhase.starting;
  String? _problem;
  int _width = 1, _height = 1;

  PreviewHandle? get handle => _handle;
  PreviewPhase get phase => _phase;
  String? get problem => _problem;
  double get aspectRatio => _width / _height;

  Future<void> _release(PreviewHandle? handle) async {
    if (handle == null) return;
    try {
      await backend.stop(handle);
    } on Object {
      /* Native owner also stops on engine shutdown. Never log private errors. */
    }
  }

  Future<void> show(ScreenSource source) async {
    if (_disposed) return;
    final generation = ++_generation;
    _poll?.cancel();
    _firstFrameDeadline?.cancel();
    unawaited(_release(_handle));
    _handle = null;
    _phase = PreviewPhase.starting;
    _problem = null;
    _width = source.width;
    _height = source.height;
    notifyListeners();
    _firstFrameDeadline = Timer(SaDurations.beat * 5, () {
      if (!_disposed &&
          generation == _generation &&
          _phase == PreviewPhase.starting) {
        ++_generation;
        _poll?.cancel();
        unawaited(_release(_handle));
        _handle = null;
        _phase = PreviewPhase.unavailable;
        _problem = 'No preview received. Restore the window and try again.';
        notifyListeners();
      }
    });
    try {
      final handle = await backend.start(source);
      if (_disposed || generation != _generation) {
        await _release(handle);
        return;
      }
      _handle = handle;
      _width = handle.width;
      _height = handle.height;
      _poll = Timer.periodic(
        SaDurations.previewPoll,
        (_) => unawaited(checkStatus()),
      );
      await checkStatus();
    } on Object {
      if (!_disposed && generation == _generation) {
        _firstFrameDeadline?.cancel();
        _phase = PreviewPhase.unavailable;
        _problem =
            'Could not preview this source. Restore the window and try again.';
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    ++_generation;
    _poll?.cancel();
    _firstFrameDeadline?.cancel();
    final handle = _handle;
    _handle = null;
    _phase = PreviewPhase.unavailable;
    _problem = 'Preview paused.';
    if (!_disposed) notifyListeners();
    await _release(handle);
  }

  Future<void> checkStatus() async {
    final handle = _handle;
    if (_disposed || _polling || handle == null) return;
    final generation = _generation;
    _polling = true;
    try {
      final status = await backend.status(handle);
      if (_disposed || generation != _generation) return;
      if (status.closed || status.failed) {
        _firstFrameDeadline?.cancel();
        _poll?.cancel();
        _handle = null;
        _phase = PreviewPhase.unavailable;
        _problem = status.closed
            ? 'This source closed. Choose another.'
            : 'Source unavailable. Restore it or choose another.';
        unawaited(_release(handle));
      } else {
        if (status.width > 0 && status.height > 0) {
          _width = status.width;
          _height = status.height;
        }
        _phase = status.ready ? PreviewPhase.live : PreviewPhase.starting;
        if (status.ready) _firstFrameDeadline?.cancel();
      }
      notifyListeners();
    } on Object {
      if (!_disposed && generation == _generation) {
        _firstFrameDeadline?.cancel();
        _poll?.cancel();
        _handle = null;
        _phase = PreviewPhase.unavailable;
        _problem = 'Preview stopped. Try again.';
        unawaited(_release(handle));
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _poll?.cancel();
    _firstFrameDeadline?.cancel();
    unawaited(_release(_handle));
    _handle = null;
    super.dispose();
  }
}

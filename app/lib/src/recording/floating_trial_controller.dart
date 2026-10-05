import 'dart:async';
import 'package:flutter/foundation.dart';
import 'floating_prompter.dart';
import '../theme/theme.dart';

/// Owns a preview's floating window, including late replies after the page exits.
class FloatingTrialController extends ChangeNotifier {
  FloatingTrialController(this.backend, this.presentation);
  final FloatingPrompters backend;
  final FloatingPresentation presentation;
  FloatingHandle? _handle;
  bool _disposed = false;
  int _generation = 0;
  Timer? _poll;
  bool _polling = false;
  bool opening = false;
  bool get visible => _handle != null;
  String? problem;

  Future<void> toggle() async {
    if (_disposed || opening) return;
    if (visible) { await hide(); return; }
    final generation = ++_generation;
    opening = true;
    problem = null;
    notifyListeners();
    try {
      final handle = await backend.open(presentation);
      if (_disposed || generation != _generation) { await _release(handle); return; }
      _handle = handle;
      _poll = Timer.periodic(SaDurations.previewPoll, (_) => unawaited(_checkWindow()));
    } on Object {
      if (!_disposed && generation == _generation) {
        problem = 'The hidden prompter could not open. Try again.';
      }
    } finally {
      if (!_disposed && generation == _generation) { opening = false; notifyListeners(); }
    }
  }
  Future<void> hide() async {
    _poll?.cancel();
    _poll = null;
    ++_generation;
    opening = false;
    final handle = _handle;
    _handle = null;
    if (!_disposed) notifyListeners();
    if (handle != null) await _release(handle);
  }
  Future<void> _checkWindow() async {
    final handle = _handle;
    if (_disposed || _polling || handle == null) return;
    final generation = _generation;
    _polling = true;
    bool live = false;
    try { live = await backend.isOpen(handle); } on Object { /* Fail closed. */ }
    finally { _polling = false; }
    if (!_disposed && generation == _generation && !live) await hide();
  }
  Future<void> _release(FloatingHandle handle) async {
    try { await backend.close(handle); } on Object { /* Engine shutdown also owns cleanup. */ }
  }
  @override
  void dispose() {
    _disposed = true;
    unawaited(hide());
    super.dispose();
  }
}

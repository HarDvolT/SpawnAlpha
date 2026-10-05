import 'package:flutter/foundation.dart';

import 'screen_source.dart';

/// Keeps selection valid when windows close or displays are disconnected.
/// Nothing is persisted: a native window handle must not survive an app restart.
class SourceSelection extends ChangeNotifier {
  SourceSelection(this.backend, {this._selected});

  final ScreenSources backend;
  List<ScreenSource> _sources = const [];
  ScreenSource? _selected;
  bool _loading = false;
  bool _disposed = false;
  String? _problem;

  List<ScreenSource> get sources => _sources;
  ScreenSource? get selected => _selected;
  bool get loading => _loading;
  String? get problem => _problem;

  Future<void> refresh() async {
    if (_loading || _disposed) return;
    _loading = true;
    _problem = null;
    notifyListeners();
    try {
      final fresh = await backend.list();
      if (_disposed) return;
      _sources = List.unmodifiable(fresh);
      final previousId = _selected?.id;
      _selected = fresh.where((s) => s.id == previousId).firstOrNull;
      if (previousId != null && _selected == null) {
        _problem = 'That source is no longer available. Choose another.';
      }
    } on Object {
      if (_disposed) return;
      _sources = const [];
      _selected = null;
      // Exceptions may include private window titles. Never log their contents.
      _problem = 'Could not list screens and windows. Try Refresh.';
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void choose(String id) {
    if (_loading || _disposed) return;
    _selected = _sources.where((s) => s.id == id).firstOrNull;
    _problem = null;
    notifyListeners();
  }

  /// Re-enumerate at confirmation, so a closed window cannot be accepted.
  Future<ScreenSource?> confirm() async {
    if (_loading || _selected == null || _disposed) return null;
    await refresh();
    return _disposed ? null : _selected;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

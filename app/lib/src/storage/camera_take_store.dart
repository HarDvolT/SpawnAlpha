import 'dart:convert';
import 'dart:io';

import '../model/mark.dart';
import '../model/note_timeline.dart';
import '../model/script_document.dart';

/// Frozen recording aid for camera-only takes. The camera plugin owns video;
/// this store owns only our private metadata and card clock.
class CameraTakeSnapshot {
  CameraTakeSnapshot._(this.file, this.document, this.recordedAt);
  final File file;
  final ScriptDocument document;
  final DateTime recordedAt;
  late final NoteTimeline? clock = document.usesNotes ? NoteTimeline(document.notes.cards.length) : null;
  Future<void> _writes = Future<void>.value();
  String _state = 'pendingCamera';
  Take? _take;
  static Future<CameraTakeSnapshot> reserve(Directory directory, ScriptDocument document) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}${newId()}-camera-notes.json');
    final snapshot = CameraTakeSnapshot._(
      file,
      document.copyWith(takes: const [], suggestions: const []),
      DateTime.now(),
    );
    await snapshot._save();
    return snapshot;
  }

  Future<void> select(int index, Duration time) {
    if (clock?.observe(index, time, paused: false) != true) return _writes;
    return _save();
  }

  Future<void> finish(Take take) {
    _state = 'saved';
    _take = take;
    return _save();
  }

  Future<void> cancel() {
    _state = 'cancelled';
    return _save();
  }

  Future<void> _save() {
    final data = jsonEncode({
      'version': 1,
      'state': _state,
      'mode': 'camera',
      'script': document.toJson(),
      'recordedAt': recordedAt.toIso8601String(),
      if (clock != null) 'noteChanges': clock!.toJson(),
      if (_take != null) 'take': _take!.toJson(),
    });
    final next = _writes.then((_) async {
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(data, flush: true);
      await temp.rename(file.path);
    });
    _writes = next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/script_document.dart';

/// Where scripts are kept.
abstract interface class ScriptStore {
  Future<List<ScriptDocument>> loadAll();

  Future<void> save(ScriptDocument script);

  Future<void> delete(String id);
}

/// One JSON file per script in [directory].
class FileScriptStore implements ScriptStore {
  FileScriptStore(this.directory);

  final Directory directory;

  File _file(String id) => File('${directory.path}${Platform.pathSeparator}$id.json');

  @override
  Future<List<ScriptDocument>> loadAll() async {
    if (!await directory.exists()) return [];
    final scripts = <ScriptDocument>[];
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entry.readAsString());
        if (json is Map<String, Object?>) scripts.add(ScriptDocument.fromJson(json));
      } on FormatException catch (e) {
        debugPrint('Skipping unreadable script ${entry.path}: $e');
      }
    }
    scripts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return scripts;
  }

  @override
  Future<void> save(ScriptDocument script) async {
    await directory.create(recursive: true);
    // Write then rename, so a crash mid-write can't corrupt the script.
    final target = _file(script.id);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(script.toJson()), flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<void> delete(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }
}

/// Keeps scripts in memory, for tests.
class MemoryScriptStore implements ScriptStore {
  final Map<String, ScriptDocument> scripts = {};

  @override
  Future<List<ScriptDocument>> loadAll() async =>
      scripts.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> save(ScriptDocument script) async => scripts[script.id] = script;

  @override
  Future<void> delete(String id) async => scripts.remove(id);
}

/// The scripts the user has, kept in step with a [ScriptStore].
class ScriptLibrary extends ChangeNotifier {
  ScriptLibrary(this._store);

  final ScriptStore _store;
  List<ScriptDocument> _scripts = [];
  bool _loaded = false;

  List<ScriptDocument> get scripts => _scripts;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _scripts = await _store.loadAll();
    _loaded = true;
    notifyListeners();
  }

  ScriptDocument? byId(String id) {
    for (final s in _scripts) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> save(ScriptDocument script) async {
    _scripts = [script, for (final s in _scripts) if (s.id != script.id) s];
    notifyListeners();
    await _store.save(script);
  }

  Future<void> delete(String id) async {
    _scripts = [for (final s in _scripts) if (s.id != id) s];
    notifyListeners();
    await _store.delete(id);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/camera_take_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import '../model/note_deck_test.dart' show fixtureNotes;

void main() {
  for (final language in ScriptLanguage.values) {
    test('file store and camera snapshot preserve old notes after edits $language', () async {
      final dir = await Directory.systemTemp.createTemp('spawnalpha-notes-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileScriptStore(dir);
      final doc = ScriptDocument.create(language: language).copyWith(recordingAid: RecordingAid.notes, notes: fixtureNotes(language));
      await store.save(doc);
      expect((await store.loadAll()).single.notes.cards.first.title, doc.notes.cards.first.title);
      final snapshot = await CameraTakeSnapshot.reserve(dir, doc);
      await snapshot.select(1, const Duration(seconds: 2));
      await store.save(doc.copyWith(notes: NoteDeck([NoteCard.create(title: 'Later edit')])));
      final take = Take(path: '${dir.path}/generated.mp4', recordedAt: DateTime.now(), duration: const Duration(seconds: 4));
      await snapshot.finish(take);
      final saved = jsonDecode(await snapshot.file.readAsString()) as Map<String, dynamic>;
      expect((saved['script'] as Map)['notes'], doc.notes.toJson());
      expect(saved['noteChanges'], [{'cardIndex': 0, 'timeUs': 0}, {'cardIndex': 1, 'timeUs': 2000000}]);
      expect(saved['state'], 'saved');
    });
  }
  test('private malformed documents do not break readable library or enter logs', () async {
    final dir = await Directory.systemTemp.createTemp('spawnalpha-notes-');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileScriptStore(dir);
    await store.save(ScriptDocument.create(text: 'Read this'));
    await File('${dir.path}/bad.json').writeAsString('{ PRIVATE TEXT');
    await File('${dir.path}/wrong.json').writeAsString('{"text": ["PRIVATE TEXT"]}');
    expect(await store.loadAll(), hasLength(1));
    expect(await File('${dir.path}/bad.json').exists(), isTrue);
  });
  test('overlapping library saves leave the latest complete file', () async {
    final dir = await Directory.systemTemp.createTemp('spawnalpha-notes-');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileScriptStore(dir), library = ScriptLibrary(FileScriptStore(dir));
    addTearDown(library.dispose);
    final document = ScriptDocument.create(text: 'Keep');
    await Future.wait([
      for (var i = 0; i < 20; i++) library.save(document.copyWith(title: 'Edit $i')),
    ]);
    expect((await store.loadAll()).single.title, 'Edit 19');
  });
}

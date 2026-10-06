import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/storage/script_store.dart';

class FailingStore extends MemoryScriptStore {
  Completer<void>? wait;
  @override
  Future<void> save(ScriptDocument script) async {
    if (script.title == 'Fail') {
      if (wait != null) await wait!.future;
      throw const FileSystemException('Generated failed save');
    }
    await super.save(script);
  }
}

void main() {
  test('failed first save removes its optimistic document', () async {
    final library = ScriptLibrary(FailingStore());
    addTearDown(library.dispose);
    final script = ScriptDocument.create(title: 'Fail');
    await expectLater(
      library.save(script),
      throwsA(isA<FileSystemException>()),
    );
    expect(library.byId(script.id), isNull);
  });
  test('failed replacement restores saved data', () async {
    final library = ScriptLibrary(FailingStore());
    addTearDown(library.dispose);
    final script = ScriptDocument.create(title: 'Keep');
    await library.save(script);
    await expectLater(
      library.save(script.copyWith(title: 'Fail')),
      throwsA(isA<FileSystemException>()),
    );
    expect(library.byId(script.id), same(script));
  });
  test('failed earlier write cannot roll back a later edit', () async {
    final store = FailingStore()..wait = Completer<void>();
    final library = ScriptLibrary(store);
    addTearDown(library.dispose);
    final script = ScriptDocument.create(title: 'Keep');
    await library.save(script);
    final failure = expectLater(
      library.save(script.copyWith(title: 'Fail')),
      throwsA(isA<FileSystemException>()),
    );
    final latest = script.copyWith(title: 'Later');
    final next = library.save(latest);
    store.wait!.complete();
    await Future.wait([failure, next]);
    expect(library.byId(script.id), same(latest));
    expect(store.scripts[script.id], same(latest));
  });
}

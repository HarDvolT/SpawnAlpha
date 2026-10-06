import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/transcription/script_alignment.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';

import '../cut/clean_plan_test.dart' show cleanFixture, gap;

void main() {
  test(
    'local plans survive restart and refuse stale transcript revisions',
    () async {
      final dir = await Directory.systemTemp.createTemp('spawnalpha-cut-');
      addTearDown(() => dir.delete(recursive: true));
      final library = ScriptLibrary(MemoryScriptStore());
      final words = cleanFixture(ScriptLanguage.en);
      final take = Take(
        path: '${dir.path}/generated.mp4',
        recordedAt: DateTime(2026),
        duration: words.duration,
        wordsPath: '${dir.path}/words.json',
      );
      final doc = ScriptDocument.create(
        text: words.words.map((w) => w.text).join(' '),
      ).copyWith(takes: [take]);
      await library.save(doc);
      final spoken = SavedTranscript(
        sourcePath: take.path,
        transcript: words,
        snapshot: doc,
        quiet: [gap()],
        alignment: {'attemptCount': alignTranscript(doc, words).attemptCount},
      );
      final store = CleanCutStore(Directory('${dir.path}/cuts'), library);
      final plan = await store.create(doc, take, spoken);
      final saved = library.byId(doc.id)!.takes.single;
      expect(saved.cutPath, isNotNull);
      expect(await File(take.path).exists(), isFalse);
      expect(
        (await store.load(saved))!.asCutPlan().toJson(),
        plan.asCutPlan().toJson(),
      );
      await library.save(
        library.byId(doc.id)!.withText('Later edits stay here.'),
      );
      await store.save(doc.id, saved, plan.restoreAll());
      expect(
        (await store.load(library.byId(doc.id)!.takes.single))!
            .asCutPlan()
            .duration,
        take.duration,
      );
      expect(library.byId(doc.id)!.text, 'Later edits stay here.');
      final newer = library
          .byId(doc.id)!
          .takes
          .single
          .withWords('${dir.path}/new-words.json');
      await library.save(library.byId(doc.id)!.copyWith(takes: [newer]));
      await expectLater(store.save(doc.id, saved, plan), throwsFormatException);
      expect(
        await store.load(
          saved.withWords('different.json').withCut(saved.cutPath!),
        ),
        isNull,
      );
      library.dispose();
    },
  );
}

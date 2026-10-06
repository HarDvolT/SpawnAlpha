import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/transcription/script_alignment.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';

import '../cut/clean_plan_test.dart' show cleanFixture, gap;
import '../cut/filler_review_test.dart'
    show fillerFixture, fillerQuiet, fillerScript;

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'filler review, choice, restore and stale-cut rejection survive disk $language',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'spawnalpha-fillers-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final library = ScriptLibrary(MemoryScriptStore());
        final words = fillerFixture(language),
            frozen = fillerScript(fillerFixture(language));
        final take = Take(
          path: '${dir.path}/generated.mp4',
          recordedAt: DateTime(2026),
          duration: words.duration,
          wordsPath: '${dir.path}/words.json',
        );
        final document = frozen.copyWith(takes: [take]);
        await library.save(document);
        final store = CleanCutStore(Directory('${dir.path}/cuts'), library);
        final old = planQuietCut(
          takeId: 'generated',
          transcript: words,
          quiet: fillerQuiet(words),
          snapshot: frozen,
          alignment: alignTranscript(frozen, words),
        );
        await store.save(document.id, take, old);
        final oldTake = library.byId(document.id)!.takes.single;
        final oldBytes = await File(oldTake.cutPath!).readAsString();
        final spoken = SavedTranscript(
          sourcePath: take.path,
          transcript: words,
          snapshot: frozen,
          quiet: fillerQuiet(words),
          alignment: {'attemptCount': 1},
        );
        final plan = await store.create(document, oldTake, spoken, base: old);
        expect(plan.fillersReviewed, isTrue);
        expect(plan.changes.single.enabled, isFalse);
        var latest = library.byId(document.id)!.takes.single;
        final enabled = plan.withEnabled(plan.changes.single.id, true);
        await store.save(document.id, latest, enabled);
        expect(await File(oldTake.cutPath!).readAsString(), oldBytes);
        expect(
          speechOnCleanCut(
            words,
            (await store.load(library.byId(document.id)!.takes.single))!,
          ).words,
          hasLength(2),
        );
        await expectLater(
          store.save(document.id, latest, plan),
          throwsFormatException,
        );
        latest = library.byId(document.id)!.takes.single;
        await store.save(document.id, latest, enabled.restoreAll());
        expect(
          speechOnCleanCut(
            words,
            (await store.load(library.byId(document.id)!.takes.single))!,
          ).toJson(),
          words.toJson(),
        );
        library.dispose();
      },
    );
  }
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

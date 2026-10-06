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
import '../cut/retake_review_test.dart'
    show retakeWords, retakeScript, retakeQuiet;

import 'package:spawnalpha/src/cut/retake_choice.dart';

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'retake enrichment, choice, restore, provenance and revisions survive disk $language',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'spawnalpha-retakes-',
        );
        addTearDown(() => root.delete(recursive: true));
        final library = ScriptLibrary(MemoryScriptStore());
        final words = retakeWords(language), frozen = retakeScript(language);
        final take = Take(
          path: '${root.path}/generated.mp4',
          recordedAt: DateTime(2026),
          duration: words.duration,
          wordsPath: '${root.path}/words.json',
        );
        final document = frozen.copyWith(takes: [take]);
        await library.save(document);
        final store = CleanCutStore(Directory('${root.path}/cuts'), library);
        final old = planQuietCut(
          takeId: 'generated',
          transcript: words,
          quiet: retakeQuiet(words),
          snapshot: frozen,
          alignment: alignTranscript(frozen, words),
        );
        await store.save(document.id, take, old);
        final oldTake = library.byId(document.id)!.takes.single;
        final bytes = await File(oldTake.cutPath!).readAsBytes();
        final spoken = SavedTranscript(
          sourcePath: take.path,
          transcript: words,
          snapshot: frozen,
          quiet: retakeQuiet(words),
          alignment: {'attemptCount': 2},
        );
        final plan = await store.create(document, oldTake, spoken, base: old);
        expect(plan.retakes.single.selected, isNull);
        expect(
          plan.changes.map((c) => c.enabled),
          old.changes.map((c) => c.enabled),
        );
        var latest = library.byId(document.id)!.takes.single;
        final chosen = plan.withAttempt(plan.retakes.single.id, 1);
        await store.save(document.id, latest, chosen);
        final current = library.byId(document.id)!.takes.single;
        expect((await store.load(current))!.retakes.single.selected, 1);
        expect(
          speechOnCleanCut(words, (await store.load(current))!).words,
          hasLength(3),
        );
        expect(await File(oldTake.cutPath!).readAsBytes(), bytes);
        await expectLater(
          store.save(document.id, latest, plan),
          throwsFormatException,
        );
        final option = chosen.retakes.single.options.first;
        final forged = CleanPlan(
          takeId: chosen.takeId,
          language: language,
          sourceDuration: words.duration,
          changes: chosen.changes,
          fillersReviewed: true,
          retakesReviewed: true,
          retakes: [
            RetakeChoice(
              id: chosen.retakes.single.id,
              selected: 1,
              options: [
                RetakeOption(
                  firstWord: option.firstWord,
                  lastWord: option.lastWord,
                  text: 'changed provenance',
                  preview: option.preview,
                  complete: option.complete,
                  removal: option.removal,
                ),
                chosen.retakes.single.options.last,
              ],
            ),
          ],
        );
        await expectLater(
          store.save(document.id, current, forged),
          throwsFormatException,
        );
        latest = library.byId(document.id)!.takes.single;
        await store.save(document.id, latest, chosen.restoreAll());
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

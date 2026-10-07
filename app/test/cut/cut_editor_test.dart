import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/cut/cut_timeline.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/transcription/captions.dart';

import 'clean_plan_test.dart' show cleanFixture, gap;
import 'retake_review_test.dart' show retakeWords, retakePlan;

SourceRange range(int start, int end) => SourceRange(
  start: Duration(milliseconds: start),
  end: Duration(milliseconds: end),
);
CleanPlan editorFixture(ScriptLanguage language) => CleanPlan(
  takeId: 'generated',
  language: language,
  sourceDuration: const Duration(seconds: 4),
  changes: [CutChange(id: 'quiet-0', range: range(650, 2700))],
);

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'inward gap handles only restore original time and preserve words $language',
      () {
        final initial = editorFixture(language), words = cleanFixture(language);
        final edited = initial.withRange('quiet-0', range(1000, 2300));
        expect(initial.changes.single.originalRange, isNull);
        expect(
          edited.changes.single.bounds.toJson(),
          initial.changes.single.range.toJson(),
        );
        expect(edited.asCutPlan().duration, const Duration(milliseconds: 2700));
        expect(
          speechOnCleanCut(words, edited).words.map((w) => w.text),
          words.words.map((w) => w.text),
        );
        expect(
          speechOnCleanCut(words, edited).words.last.start,
          const Duration(milliseconds: 1700),
        );
        final reset = edited.withRange('quiet-0', edited.changes.single.bounds);
        expect(reset.asCutPlan().toJson(), initial.asCutPlan().toJson());
        expect(edited.restoreAll().asCutPlan().duration, words.duration);
        expect(
          edited.withEnabled('quiet-0', false).changes.single.bounds.toJson(),
          initial.changes.single.range.toJson(),
        );
        expect(
          CleanPlan.fromJson(
            jsonDecode(jsonEncode(edited.toJson())) as Map<String, Object?>,
          ).toJson(),
          edited.toJson(),
        );
        final old = CleanPlan.fromJson(
          jsonDecode(jsonEncode(initial.toJson())) as Map<String, Object?>,
        );
        expect(
          old.changes.single.bounds.toJson(),
          initial.changes.single.range.toJson(),
        );
        expect(old.toJson(), initial.toJson());
      },
    );
    test(
      'timeline has complete source coverage and safe exact edge selection $language',
      () {
        final plan = editorFixture(language);
        final timeline = cutTimeline(plan);
        expect(timeline.map((s) => s.removed), [false, true, false]);
        expect(timeline.map((s) => s.range.toJson()), [
          range(0, 650).toJson(),
          range(650, 2700).toJson(),
          range(2700, 4000).toJson(),
        ]);
        expect(timelineAt(timeline, Duration.zero).removed, isFalse);
        expect(
          timelineAt(timeline, const Duration(milliseconds: 650)).removed,
          isTrue,
        );
        expect(
          timelineAt(timeline, const Duration(milliseconds: 2700)).removed,
          isFalse,
        );
        expect(
          timelineAt(timeline, plan.sourceDuration).range.end,
          plan.sourceDuration,
        );
        expect(cutTimeline(plan.restoreAll()), hasLength(1));
        expect(() => timeline.clear(), throwsUnsupportedError);
        expect(
          () => timelineAt(timeline, const Duration(microseconds: -1)),
          throwsArgumentError,
        );
        expect(
          () => timelineAt(timeline, const Duration(microseconds: 4000001)),
          throwsArgumentError,
        );
      },
    );
    test(
      'retake and quiet overlaps share the timeline without duplicate time $language',
      () {
        final words = retakeWords(language), plan = retakePlan(words);
        final chosen = plan.withAttempt(plan.retakes.single.id, 1);
        final timeline = cutTimeline(chosen);
        expect(
          timeline.fold(Duration.zero, (sum, s) => sum + s.range.duration),
          words.duration,
        );
        expect(
          timeline
              .where((s) => !s.removed)
              .fold(Duration.zero, (sum, s) => sum + s.range.duration),
          chosen.asCutPlan().duration,
        );
        for (var i = 1; i < timeline.length; ++i) {
          expect(timeline[i].range.start, timeline[i - 1].range.end);
        }
      },
    );
    test(
      'edited handles reopen, reset and export without rewriting previous plans $language',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'spawnalpha-gap-edit-',
        );
        addTearDown(() => root.delete(recursive: true));
        final library = ScriptLibrary(
          FileScriptStore(Directory('${root.path}/scripts')),
        );
        addTearDown(library.dispose);
        final take = Take(
          path: '${root.path}/generated.mp4',
          wordsPath: '${root.path}/words.json',
          recordedAt: DateTime(2026),
          duration: const Duration(seconds: 4),
        );
        final document = ScriptDocument.create(language: language)
            .copyWith(takes: [take]);
        await library.save(document);
        final store = CleanCutStore(Directory('${root.path}/cuts'), library);
        final original = editorFixture(language);
        await store.save(document.id, take, original);
        var latest = library.byId(document.id)!.takes.single;
        final previous = File(latest.cutPath!);
        final oldBytes = await previous.readAsBytes();
        final edited = original.withRange('quiet-0', range(1000, 2300));
        await store.save(document.id, latest, edited);
        await library.load();
        latest = library.byId(document.id)!.takes.single;
        final reopened = (await store.load(latest))!;
        expect(reopened.toJson(), edited.toJson());
        expect(await previous.readAsBytes(), oldBytes);
        expect(
          subtitleText(
            captionsFromSpeech(
              speechOnCleanCut(cleanFixture(language), reopened),
            ),
          ),
          contains('00:00:01,700'),
        );
        final forged = CleanPlan(
          takeId: original.takeId,
          language: language,
          sourceDuration: original.sourceDuration,
          changes: [CutChange(id: 'quiet-0', range: range(600, 2800))],
        );
        await expectLater(
          store.save(document.id, latest, forged),
          throwsFormatException,
        );
        await expectLater(
          store.save(
            document.id,
            latest,
            CleanPlan(
              takeId: 'other',
              language: language,
              sourceDuration: original.sourceDuration,
              changes: original.changes,
            ),
          ),
          throwsFormatException,
        );
        expect((await store.load(latest))!.toJson(), edited.toJson());
        await store.save(
          document.id,
          latest,
          reopened.withRange('quiet-0', reopened.changes.single.bounds),
        );
        latest = library.byId(document.id)!.takes.single;
        expect(
          (await store.load(latest))!.asCutPlan().toJson(),
          original.asCutPlan().toJson(),
        );
      },
    );
  }
  test('handles reject expanded, unknown, non-quiet and corrupt bounds', () {
    final plan = editorFixture(ScriptLanguage.en);
    expect(
      () => plan.withRange('quiet-0', range(649, 2700)),
      throwsFormatException,
    );
    expect(
      () => plan.withRange('quiet-0', range(650, 2701)),
      throwsFormatException,
    );
    expect(
      () => plan.withRange('quiet-7', range(1000, 2000)),
      throwsFormatException,
    );
    final filler = CutChange(
      id: 'filler-0',
      kind: CutChangeKind.filler,
      text: 'um',
      spokenIndices: const [0],
      range: gap(),
    );
    expect(() => filler.withRange(range(1000, 2000)), throwsFormatException);
    expect(
      () => CutChange(
        id: 'filler-0',
        kind: CutChangeKind.filler,
        text: 'um',
        spokenIndices: const [0],
        range: gap(),
        originalRange: gap(),
      ),
      throwsFormatException,
    );
    for (final bad in [
      true,
      <String, Object?>{'startUs': '0', 'endUs': 1},
      <String, Object?>{'startUs': 0, 'endUs': 1, 'extra': true},
      <String, Object?>{'startUs': 700000, 'endUs': 2500000},
    ]) {
      final json = plan.toJson();
      (json['changes'] as List).single['originalRange'] = bad;
      expect(() => CleanPlan.fromJson(json), throwsFormatException);
    }
  });
}

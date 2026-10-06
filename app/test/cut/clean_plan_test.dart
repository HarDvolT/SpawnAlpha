import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/script_alignment.dart';
import 'package:spawnalpha/src/transcription/speech_windows.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

WordTranscript cleanFixture(
  ScriptLanguage language, {
  double? confidence = .9,
}) {
  final text = switch (language) {
    ScriptLanguage.en => 'Hello everyone.',
    ScriptLanguage.fr => 'Bonjour tous.',
    ScriptLanguage.ar => 'مرحبا بالجميع.',
  };
  final words = text.split(' ');
  return WordTranscript(
    language: language,
    duration: const Duration(seconds: 4),
    words: [
      SpokenWord(
        text: words.first,
        start: const Duration(milliseconds: 200),
        end: const Duration(milliseconds: 500),
        confidence: confidence,
      ),
      SpokenWord(
        text: words.last,
        start: const Duration(seconds: 3),
        end: const Duration(milliseconds: 3400),
        confidence: confidence,
      ),
    ],
  );
}

SourceRange gap() => SourceRange(
  start: const Duration(milliseconds: 500),
  end: const Duration(seconds: 3),
);
void main() {
  for (final language in ScriptLanguage.values) {
    final transcript = cleanFixture(language);
    final script = ScriptDocument.create(
      language: language,
      text: transcript.words.map((w) => w.text).join(' '),
    );
    test(
      'quiet change is reversible and captions keep actual words $language',
      () {
        final clean = planQuietCut(
          takeId: 'generated',
          transcript: transcript,
          quiet: [gap()],
          snapshot: script,
          alignment: alignTranscript(script, transcript),
        );
        expect(clean.changes, hasLength(1));
        expect(clean.asCutPlan().duration, const Duration(milliseconds: 1950));
        final moved = speechOnCut(transcript, clean.asCutPlan());
        expect(
          moved.words.map((w) => w.text),
          transcript.words.map((w) => w.text),
        );
        expect(moved.words.last.start, const Duration(milliseconds: 950));
        expect(
          clean
              .withEnabled(clean.changes.single.id, false)
              .asCutPlan()
              .duration,
          transcript.duration,
        );
        expect(
          CleanPlan.fromJson(
            jsonDecode(jsonEncode(clean.toJson())) as Map<String, Object?>,
          ).asCutPlan().toJson(),
          clean.asCutPlan().toJson(),
        );
      },
    );
    for (final kind in [
      MarkKind.pauseShort,
      MarkKind.pauseLong,
      MarkKind.breath,
    ]) {
      test('accepted $kind is fully preserved $language', () {
        final marked = script.copyWith(
          marks: [Mark.gap(id: 'gap', kind: kind, after: 0)],
        );
        expect(
          planQuietCut(
            takeId: 'generated',
            transcript: transcript,
            quiet: [gap()],
            snapshot: marked,
            alignment: alignTranscript(marked, transcript),
          ).changes,
          isEmpty,
        );
      });
    }
    test(
      'pending cue and unrelated old script cannot remove speech $language',
      () {
        final marked = script.copyWith(
          marks: [
            const Mark.gap(
              id: 'gap',
              kind: MarkKind.pauseLong,
              after: 0,
              accepted: false,
            ),
          ],
        );
        expect(
          planQuietCut(
            takeId: 'generated',
            transcript: transcript,
            quiet: [gap()],
            snapshot: marked,
            alignment: alignTranscript(marked, transcript),
          ).changes,
          hasLength(1),
        );
        expect(
          planQuietCut(
            takeId: 'generated',
            transcript: transcript,
            quiet: [gap()],
            snapshot: script,
          ).changes,
          isEmpty,
        );
      },
    );
    test('Notes use speech and screen context stays intact $language', () {
      final notes = script
          .withText('Different reminder')
          .copyWith(recordingAid: RecordingAid.notes);
      final plan = planQuietCut(
        takeId: 'generated',
        transcript: transcript,
        quiet: [gap()],
        snapshot: notes,
      );
      expect(plan.changes, hasLength(1));
      expect(
        planQuietCut(
          takeId: 'generated',
          transcript: transcript,
          quiet: [gap()],
          snapshot: notes,
          screenContext: true,
        ).changes,
        isEmpty,
      );
    });
    test(
      'unknown confidence protects neighbourhoods and missing evidence keeps original $language',
      () {
        final uncertain = cleanFixture(language, confidence: null);
        expect(
          planQuietCut(
            takeId: 'generated',
            transcript: uncertain,
            quiet: [gap()],
            snapshot: script,
            alignment: alignTranscript(script, uncertain),
          ).changes,
          isEmpty,
        );
        expect(
          planQuietCut(
            takeId: 'generated',
            transcript: transcript,
            quiet: [],
            snapshot: script,
            alignment: alignTranscript(script, transcript),
          ).asCutPlan().duration,
          transcript.duration,
        );
      },
    );
  }
  test(
    'invalid plans and cuts through words are rejected without changing words',
    () {
      final transcript = cleanFixture(ScriptLanguage.en);
      final invalid = CutPlan(
        takeId: 'generated',
        language: ScriptLanguage.en,
        sourceDuration: transcript.duration,
        ranges: [
          SourceRange(
            start: const Duration(milliseconds: 300),
            end: transcript.duration,
          ),
        ],
      );
      expect(() => speechOnCut(transcript, invalid), throwsFormatException);
      expect(() => CleanPlan.fromJson({'version': 9}), throwsFormatException);
      final notes = ScriptDocument.create().copyWith(
        recordingAid: RecordingAid.notes,
      );
      expect(
        () => planQuietCut(
          takeId: 'generated',
          transcript: transcript,
          snapshot: notes,
          quiet: [gap(), gap()],
        ),
        throwsFormatException,
      );
    },
  );
  test('quiet seams merge, wrong clock and malformed evidence fail', () {
    Map<String, Object?> window(int start, int end) => {
      'keepStartUs': start,
      'keepEndUs': end,
      'quiet': [
        {'startUs': start, 'endUs': end},
      ],
    };
    final quiet = quietFromWindows(const Duration(seconds: 3), [
      window(0, 1000000),
      window(1000000, 3000000),
    ]);
    expect(quiet, hasLength(1));
    expect(quiet.single.duration, const Duration(seconds: 3));
    expect(
      () => quietFromWindows(const Duration(seconds: 2), [window(0, 3000000)]),
      throwsFormatException,
    );
    expect(
      () => quietFromWindows(const Duration(seconds: 3), [
        window(0, 2000000),
        window(1000000, 3000000),
      ]),
      throwsFormatException,
    );
  });
  test('take duration preserves microseconds across disk and clears stale cuts on new speech', () {
    final take = Take(
      path: 'generated.mp4',
      recordedAt: DateTime(2026),
      duration: const Duration(microseconds: 3456789),
      wordsPath: 'words.json',
      cutPath: 'cut.json',
      mode: TakeMode.both,
      cameraPath: 'camera.mp4',
    );
    final loaded = Take.fromJson(
      jsonDecode(jsonEncode(take.toJson())) as Map<String, Object?>,
    )!;
    expect(loaded.duration, take.duration);
    expect(loaded.cutPath, take.cutPath);
    expect(loaded.withWords('new.json').cutPath, isNull);
    expect(loaded.withCut('second.json').cameraPath, take.cameraPath);
    final legacy = take.toJson()
      ..remove('durationUs')
      ..remove('cutPath');
    expect(Take.fromJson(legacy)!.duration, const Duration(milliseconds: 3456));
  });
}

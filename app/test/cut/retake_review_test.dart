import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/cut/filler_review.dart';
import 'package:spawnalpha/src/cut/retake_review.dart';
import 'package:spawnalpha/src/cut/retake_choice.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/script_alignment.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

ScriptDocument retakeScript(ScriptLanguage language) => ScriptDocument.create(
  language: language,
  text: switch (language) {
    ScriptLanguage.en => 'We launch today.',
    ScriptLanguage.fr => 'Nous lançons demain.',
    ScriptLanguage.ar => 'نحن نبدأ الآن.',
  },
);

WordTranscript retakeWords(
  ScriptLanguage language, {
  bool filler = false,
  bool partial = false,
  double? firstConfidence = .9,
}) {
  final text = retakeScript(language).tokens.map((t) => t.text).toList();
  final starts = [
    200,
    400,
    if (!partial) 600,
    if (filler) 1100,
    2000,
    2200,
    2400,
  ];
  final said = [
    ...text.take(partial ? 2 : 3),
    if (filler)
      switch (language) {
        ScriptLanguage.en => 'um,',
        ScriptLanguage.fr => 'euh,',
        ScriptLanguage.ar => 'إيه،',
      },
    ...text,
  ];
  return WordTranscript(
    language: language,
    duration: const Duration(seconds: 4),
    words: [
      for (final (i, word) in said.indexed)
        SpokenWord(
          text: word,
          start: Duration(milliseconds: starts[i]),
          end: Duration(milliseconds: starts[i] + 100),
          confidence: i == 0 ? firstConfidence : .9,
        ),
    ],
  );
}

List<SourceRange> retakeQuiet(WordTranscript words) => [
  SourceRange(start: Duration.zero, end: words.words.first.start),
  for (var i = 0; i + 1 < words.words.length; i++)
    SourceRange(start: words.words[i].end, end: words.words[i + 1].start),
  SourceRange(start: words.words.last.end, end: words.duration),
];

CleanPlan retakePlan(
  WordTranscript words, {
  ScriptDocument? script,
  bool screen = false,
  List<SourceRange>? quiet,
  bool noAlignment = false,
}) {
  script ??= retakeScript(words.language);
  final alignment = noAlignment || script.usesNotes
      ? null
      : alignTranscript(script, words);
  final evidence = quiet ?? retakeQuiet(words);
  final base = withFillerReview(
    base: planQuietCut(
      takeId: 'generated',
      transcript: words,
      quiet: evidence,
      snapshot: script,
      alignment: alignment,
      screenContext: screen,
    ),
    transcript: words,
    quiet: evidence,
    snapshot: script,
    alignment: alignment,
    screenContext: screen,
  );
  return withRetakeReview(
    base: base,
    transcript: words,
    quiet: evidence,
    snapshot: script,
    alignment: alignment,
    screenContext: screen,
  );
}

void main() {
  test('a long bounded set of attempts stays complete and reversible', () {
    final script = retakeScript(ScriptLanguage.en);
    final said = [for (var i = 0; i < 800; i++) ...script.tokens];
    final words = WordTranscript(
      language: script.language,
      duration: const Duration(hours: 1),
      words: [
        for (final (i, token) in said.indexed)
          SpokenWord(
            text: token.text,
            start: Duration(milliseconds: 200 + i * 500),
            end: Duration(milliseconds: 300 + i * 500),
            confidence: .9,
          ),
      ],
    );
    final plan = retakePlan(words, script: script);
    expect(plan.retakes.single.options, hasLength(800));
    expect(speechOnCleanCut(words, plan.restoreAll()).words, hasLength(2400));
    expect(
      speechOnCleanCut(
        words,
        plan.restoreAll().withAttempt(plan.retakes.single.id, 799),
      ).words,
      hasLength(3),
    );
  });
  for (final language in ScriptLanguage.values) {
    test(
      'a partial repeated section cannot replace the complete attempt $language',
      () {
        final script = ScriptDocument.create(
          language: language,
          text: switch (language) {
            ScriptLanguage.en => 'We launch today with confidence.',
            ScriptLanguage.fr => 'Nous lançons demain avec confiance.',
            ScriptLanguage.ar => 'نحن نبدأ الآن بكل ثقة.',
          },
        );
        final said = [...script.tokens.take(3), ...script.tokens];
        final words = WordTranscript(
          language: language,
          duration: const Duration(seconds: 8),
          words: [
            for (final (i, token) in said.indexed)
              SpokenWord(
                text: token.text,
                start: Duration(milliseconds: 200 + i * 700),
                end: Duration(milliseconds: 300 + i * 700),
                confidence: .9,
              ),
          ],
        );
        final choice = retakePlan(words, script: script).retakes.single;
        expect(choice.canSelect(0), isFalse);
        expect(choice.canSelect(1), isTrue);
        expect(() => choice.withSelected(0), throwsFormatException);
      },
    );
    test(
      'a pause owned by a retained preceding section blocks the boundary $language',
      () {
        final text = retakeScript(language).text;
        final script = retakeScript(language)
            .withText('$text $text')
            .copyWith(
              marks: [
                Mark.gap(
                  id: 'retained-pause',
                  kind: MarkKind.pauseLong,
                  after: 2,
                ),
              ],
            );
        final said = [...script.tokens, ...script.tokens];
        final words = WordTranscript(
          language: language,
          duration: const Duration(seconds: 9),
          words: [
            for (final (i, token) in said.indexed)
              SpokenWord(
                text: token.text,
                start: Duration(milliseconds: 200 + i * 600),
                end: Duration(milliseconds: 300 + i * 600),
                confidence: .9,
              ),
          ],
        );
        final choice = retakePlan(words, script: script).retakes.last;
        expect(choice.options.every((o) => o.removal == null), isTrue);
        expect(choice.canSelect(0), isFalse);
        expect(choice.canSelect(1), isFalse);
      },
    );
    test(
      'choose either safe attempt, retime actual captions and restore $language',
      () {
        final words = retakeWords(language),
            plan = retakePlan(retakeWords(language));
        expect(plan.retakesReviewed, isTrue);
        expect(plan.retakes.single.selected, isNull);
        expect(plan.retakes.single.canSelect(0), isTrue);
        expect(plan.retakes.single.canSelect(1), isTrue);
        final all = plan.restoreAll();
        expect(speechOnCleanCut(words, all).toJson(), words.toJson());
        for (final selected in [0, 1]) {
          final choice = all.withAttempt(all.retakes.single.id, selected);
          final moved = speechOnCleanCut(words, choice);
          expect(moved.words, hasLength(3));
          expect(
            moved.words.map((w) => w.text),
            words.words.skip(selected * 3).take(3).map((w) => w.text),
          );
          expect(
            moved.words.first.start,
            selected == 0
                ? words.words.first.start
                : words.words[3].start -
                      all.retakes.single.options.first.removal!.duration,
          );
          expect(
            () => speechOnCut(words, choice.asCutPlan()),
            throwsFormatException,
          );
          final json = CleanPlan.fromJson(
            jsonDecode(jsonEncode(choice.toJson())) as Map<String, Object?>,
          );
          expect(speechOnCleanCut(words, json).toJson(), moved.toJson());
          expect(
            speechOnCleanCut(words, choice.restoreAll()).toJson(),
            words.toJson(),
          );
        }
        expect(words.words, hasLength(6));
      },
    );
    test(
      'quiet choices overlap discarded attempt safely and stay reversible $language',
      () {
        final words = retakeWords(language),
            plan = retakePlan(retakeWords(language));
        final chosen = plan.withAttempt(plan.retakes.single.id, 1);
        expect(
          chosen.changes.map((c) => c.enabled),
          plan.changes.map((c) => c.enabled),
        );
        final cut = chosen.asCutPlan();
        for (var i = 1; i < cut.ranges.length; i++) {
          expect(cut.ranges[i].start >= cut.ranges[i - 1].end, isTrue);
        }
        expect(speechOnCleanCut(words, chosen).words, hasLength(3));
        final restored = chosen.withAttempt(chosen.retakes.single.id, null);
        expect(restored.asCutPlan().toJson(), plan.asCutPlan().toJson());
      },
    );
    test(
      'discarded fillers merge with retakes and restore independent choices $language',
      () {
        final words = retakeWords(language, filler: true),
            plan = retakePlan(retakeWords(language, filler: true));
        final filler = plan.changes.singleWhere(
          (c) => c.kind == CutChangeKind.filler,
        );
        final chosen = plan.withAttempt(plan.retakes.single.id, 1);
        final both = chosen.withEnabled(filler.id, true);
        expect(both.asCutPlan().toJson(), chosen.asCutPlan().toJson());
        expect(speechOnCleanCut(words, both).words, hasLength(3));
        expect(
          speechOnCleanCut(
            words,
            both.withAttempt(plan.retakes.single.id, null),
          ).words,
          hasLength(6),
        );
        expect(speechOnCleanCut(words, both.restoreAll()).words, hasLength(7));
      },
    );
    test(
      'missing quiet, free speech and Screen context never get unsafe removals $language',
      () {
        final words = retakeWords(language);
        final unmeasured = retakePlan(words, quiet: []).retakes.single;
        expect(unmeasured.options.every((o) => o.removal == null), isTrue);
        expect(unmeasured.canSelect(0), isFalse);
        expect(() => unmeasured.withSelected(0), throwsFormatException);
        expect(
          retakePlan(
            words,
            script: retakeScript(language)
                .copyWith(recordingAid: RecordingAid.notes),
          ).retakes,
          isEmpty,
        );
        expect(retakePlan(words, screen: true).retakes, isEmpty);
        expect(retakePlan(words, noAlignment: true).retakes, isEmpty);
      },
    );
    test(
      'uncertain losing words stay, and wording revisions reject old choices $language',
      () {
        final words = retakeWords(language, firstConfidence: null),
            plan = retakePlan(retakeWords(language, firstConfidence: null));
        expect(plan.retakes.single.canSelect(1), isFalse);
        expect(plan.retakes.single.canSelect(0), isTrue);
        expect(
          speechOnCleanCut(
            words,
            plan.withAttempt(plan.retakes.single.id, 0),
          ).words.first.confidence,
          isNull,
        );
        final changed = words.withWord(1, switch (language) {
          ScriptLanguage.en => 'start',
          ScriptLanguage.fr => 'débutons',
          ScriptLanguage.ar => 'نفتتح',
        });
        expect(() => speechOnCleanCut(changed, plan), throwsFormatException);
      },
    );
    test(
      'selected attempt cue gaps remain while rejected attempt cues can leave $language',
      () {
        final script = retakeScript(language).copyWith(
          marks: [
            Mark(
              id: 'generated-breath',
              kind: MarkKind.breath,
              start: 0,
              end: 0,
              accepted: true,
            ),
          ],
        );
        final words = retakeWords(language),
            plan = retakePlan(
              retakeWords(language),
              script: script,
            ).restoreAll();
        final chosen = plan.withAttempt(plan.retakes.single.id, 1);
        expect(
          chosen.asCutPlan().ranges.any(
            (r) =>
                r.start <= words.words[3].end && r.end >= words.words[4].start,
          ),
          isTrue,
        );
        expect(speechOnCleanCut(words, chosen).words, hasLength(3));
      },
    );
  }
  test('retake JSON rejects invalid selections, provenance and overlapping word spans', () {
    final words = retakeWords(ScriptLanguage.en),
        plan = retakePlan(retakeWords(ScriptLanguage.en));
    final choice = plan.retakes.single;
    expect(() => choice.withSelected(-1), throwsFormatException);
    expect(() => choice.withSelected(2), throwsFormatException);
    expect(() => plan.withAttempt('missing', 0), throwsFormatException);
    expect(
      () => RetakeChoice(
        id: choice.id,
        options: [choice.options[0], choice.options[0]],
      ),
      throwsFormatException,
    );
    expect(
      () => RetakeOption(
        firstWord: 0,
        lastWord: 2,
        text: 'x',
        complete: true,
        preview: choice.options[0].preview,
        removal: SourceRange(
          start: const Duration(milliseconds: 300),
          end: const Duration(seconds: 1),
        ),
      ),
      throwsFormatException,
    );
    final value = jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>;
    ((value['retakes'] as List).first as Map)['selected'] = 42;
    expect(() => CleanPlan.fromJson(value), throwsFormatException);
    final legacy = CleanPlan(
      takeId: 'generated',
      language: words.language,
      sourceDuration: words.duration,
      changes: [],
    );
    expect(CleanPlan.fromJson(legacy.toJson()).retakesReviewed, isFalse);
    expect(CleanPlan.fromJson(legacy.toJson()).retakes, isEmpty);
  });
}

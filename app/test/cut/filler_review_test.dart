import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/cut/filler_review.dart';
import 'package:spawnalpha/src/markup/lexicon.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/script_alignment.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

WordTranscript fillerFixture(
  ScriptLanguage language, {
  String? phrase,
  double? confidence = .9,
  double? neighbourConfidence = .9,
}) {
  final text = switch (language) {
    ScriptLanguage.en => ['Hello', phrase ?? 'um,', 'everyone.'],
    ScriptLanguage.fr => ['Bonjour', phrase ?? 'euh,', 'tous.'],
    ScriptLanguage.ar => ['مرحبا', phrase ?? 'إيه،', 'بالجميع.'],
  };
  final filler = text[1].split(' ');
  return WordTranscript(
    language: language,
    duration: const Duration(seconds: 4),
    words: [
      SpokenWord(
        text: text[0],
        start: const Duration(milliseconds: 200),
        end: const Duration(milliseconds: 500),
        confidence: neighbourConfidence,
      ),
      for (var i = 0; i < filler.length; i++)
        SpokenWord(
          text: filler[i],
          start: Duration(milliseconds: 1100 + i * 200),
          end: Duration(milliseconds: 1250 + i * 200),
          confidence: confidence,
        ),
      SpokenWord(
        text: text[2],
        start: const Duration(milliseconds: 2000),
        end: const Duration(milliseconds: 2300),
        confidence: neighbourConfidence,
      ),
    ],
  );
}

List<SourceRange> fillerQuiet(WordTranscript words) => [
  SourceRange(start: words.words.first.end, end: words.words[1].start),
  SourceRange(
    start: words.words[words.words.length - 2].end,
    end: words.words.last.start,
  ),
];

ScriptDocument fillerScript(WordTranscript words, {bool notes = false}) =>
    ScriptDocument.create(
      language: words.language,
      text: '${words.words.first.text} ${words.words.last.text}',
    ).copyWith(recordingAid: notes ? RecordingAid.notes : RecordingAid.script);

CleanPlan fillerPlan(
  WordTranscript words, {
  ScriptDocument? snapshot,
  bool notes = false,
  bool screen = false,
  List<SourceRange>? quiet,
}) {
  final doc = snapshot ?? fillerScript(words, notes: notes);
  final alignment = doc.usesNotes ? null : alignTranscript(doc, words);
  final evidence = quiet ?? fillerQuiet(words);
  return withFillerReview(
    base: planQuietCut(
      takeId: 'generated',
      transcript: words,
      quiet: evidence,
      snapshot: doc,
      alignment: alignment,
      screenContext: screen,
    ),
    transcript: words,
    quiet: evidence,
    snapshot: doc,
    alignment: alignment,
    screenContext: screen,
  );
}

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'possible filler starts kept; choosing it moves only remaining words $language',
      () {
        final words = fillerFixture(language);
        final plan = fillerPlan(words),
            change = fillerPlan(words).changes.single;
        expect(change.kind, CutChangeKind.filler);
        expect(change.enabled, isFalse);
        expect(change.text, words.words[1].text);
        expect(plan.fillersReviewed, isTrue);
        expect(speechOnCleanCut(words, plan).toJson(), words.toJson());
        final removed = plan.withEnabled(change.id, true);
        final moved = speechOnCleanCut(words, removed);
        expect(moved.words.map((w) => w.text), [
          words.words.first.text,
          words.words.last.text,
        ]);
        expect(
          moved.words.last.start,
          words.words.last.start - change.range.duration,
        );
        expect(moved.duration, words.duration - change.range.duration);
        expect(
          () => speechOnCut(words, removed.asCutPlan()),
          throwsFormatException,
        );
        expect(
          speechOnCleanCut(words, removed.restoreAll()).toJson(),
          words.toJson(),
        );
        expect(words.words, hasLength(3));
        final reload = CleanPlan.fromJson(
          jsonDecode(jsonEncode(removed.toJson())) as Map<String, Object?>,
        );
        expect(speechOnCleanCut(words, reload).toJson(), moved.toJson());
      },
    );
    test('Notes stay unscored and fillers stay optional $language', () {
      final words = fillerFixture(language);
      expect(fillerPlan(words, notes: true).changes.single.enabled, isFalse);
      expect(fillerPlan(words, screen: true).changes, isEmpty);
    });
    test(
      'intentional script filler and absent alignment stay intact $language',
      () {
        final words = fillerFixture(language);
        final intentional = ScriptDocument.create(
          language: language,
          text: words.words.map((w) => w.text).join(' '),
        );
        expect(
          fillerPlan(
            words,
            snapshot: intentional,
          ).changes.where((c) => c.kind == CutChangeKind.filler),
          isEmpty,
        );
        final base = CleanPlan(
          takeId: 'generated',
          language: language,
          sourceDuration: words.duration,
          changes: [],
        );
        expect(
          withFillerReview(
            base: base,
            transcript: words,
            quiet: fillerQuiet(words),
            snapshot: fillerScript(words),
          ).changes,
          isEmpty,
        );
        expect(
          withFillerReview(
            base: base,
            transcript: words,
            quiet: fillerQuiet(words),
          ).changes,
          isEmpty,
        );
      },
    );
    for (final kind in [
      MarkKind.pauseShort,
      MarkKind.pauseLong,
      MarkKind.breath,
    ]) {
      test('accepted $kind protects the entire filler interval $language', () {
        final words = fillerFixture(language);
        final doc = fillerScript(words).copyWith(
          marks: [Mark.gap(id: 'gap', kind: kind, after: 0)],
        );
        expect(fillerPlan(words, snapshot: doc).changes, isEmpty);
        expect(
          fillerPlan(
            words,
            snapshot: doc.copyWith(
              marks: [
                Mark.gap(id: 'gap', kind: kind, after: 0, accepted: false),
              ],
            ),
          ).changes.single.kind,
          CutChangeKind.filler,
        );
      });
    }
    test(
      'uncertain words and unmeasured or short silence cannot suggest removal $language',
      () {
        for (final confidence in [null, .59]) {
          final words = fillerFixture(language, confidence: confidence);
          expect(
            fillerPlan(words).changes
                .where((c) => c.kind == CutChangeKind.filler),
            isEmpty,
          );
        }
        final uncertain = fillerFixture(language, neighbourConfidence: null);
        expect(
          fillerPlan(uncertain).changes
              .where((c) => c.kind == CutChangeKind.filler),
          isEmpty,
        );
        final words = fillerFixture(language);
        expect(fillerPlan(words, quiet: []).changes, isEmpty);
        expect(
          fillerPlan(
            words,
            quiet: [
              SourceRange(
                start: const Duration(milliseconds: 800),
                end: const Duration(milliseconds: 879),
              ),
              fillerQuiet(words).last,
            ],
          ).changes.where((c) => c.kind == CutChangeKind.filler),
          isEmpty,
        );
      },
    );
    test(
      'changed wording and malformed phrase cannot silently remove content $language',
      () {
        final words = fillerFixture(language),
            plan = fillerPlan(fillerFixture(language));
        expect(
          () => speechOnCleanCut(words.withWord(1, 'content'), plan),
          throwsFormatException,
        );
        final forged = CleanPlan(
          takeId: 'generated',
          language: language,
          sourceDuration: words.duration,
          changes: [
            CutChange(
              id: 'filler-0',
              kind: CutChangeKind.filler,
              range: SourceRange(
                start: Duration.zero,
                end: const Duration(seconds: 1),
              ),
              spokenIndices: [0],
              text: words.words[0].text,
            ),
          ],
        );
        expect(() => speechOnCleanCut(words, forged), throwsFormatException);
      },
    );
  }
  for (final (language, phrase) in [
    (ScriptLanguage.en, 'you know,'),
    (ScriptLanguage.fr, 'du coup,'),
    (ScriptLanguage.ar, 'إِيه،'),
  ]) {
    test(
      'normalized multiword and Arabic diacritics remain complete $language',
      () {
        final words = fillerFixture(language, phrase: phrase);
        final plan = fillerPlan(words),
            change = fillerPlan(words).changes.single;
        expect(change.spokenIndices.length, phrase.split(' ').length);
        expect(change.text, phrase);
        expect(
          speechOnCleanCut(words, plan.withEnabled(change.id, true)).words,
          hasLength(2),
        );
        expect(
          Lexicon.of(language).fillers.startingWith(words.words[1].bare),
          isNotEmpty,
        );
      },
    );
  }
  test('filler and long quiet changes coexist without overlapping or losing other words', () {
    final original = fillerFixture(ScriptLanguage.en);
    final words = WordTranscript(
      language: original.language,
      duration: original.duration,
      words: [
        ...original.words.take(2),
        SpokenWord(
          text: original.words.last.text,
          start: const Duration(milliseconds: 2200),
          end: const Duration(milliseconds: 2500),
          confidence: .9,
        ),
      ],
    );
    final plan = fillerPlan(words),
        filler = fillerPlan(words).changes
            .firstWhere((c) => c.kind == CutChangeKind.filler);
    expect(
      plan.changes.where((c) => c.kind == CutChangeKind.quiet),
      hasLength(1),
    );
    expect(speechOnCleanCut(words, plan).words, hasLength(3));
    expect(
      speechOnCleanCut(words, plan.withEnabled(filler.id, true)).words,
      hasLength(2),
    );
    expect(speechOnCleanCut(words, plan.restoreAll()).toJson(), words.toJson());
  });
  test('neighbouring proposals stay separate and can both be restored', () {
    final words = WordTranscript(
      language: ScriptLanguage.en,
      duration: const Duration(seconds: 4),
      words: [
        SpokenWord(
          text: 'Hello',
          start: const Duration(milliseconds: 200),
          end: const Duration(milliseconds: 500),
          confidence: .9,
        ),
        SpokenWord(
          text: 'um',
          start: const Duration(milliseconds: 1100),
          end: const Duration(milliseconds: 1250),
          confidence: .9,
        ),
        SpokenWord(
          text: 'uh',
          start: const Duration(milliseconds: 1900),
          end: const Duration(milliseconds: 2050),
          confidence: .9,
        ),
        SpokenWord(
          text: 'everyone.',
          start: const Duration(milliseconds: 2700),
          end: const Duration(seconds: 3),
          confidence: .9,
        ),
      ],
    );
    final quiet = [
      for (var i = 0; i < words.words.length - 1; i++)
        SourceRange(start: words.words[i].end, end: words.words[i + 1].start),
    ];
    var plan = fillerPlan(words, quiet: quiet);
    expect(plan.changes, hasLength(2));
    expect(
      plan.changes.first.range.end,
      lessThan(plan.changes.last.range.start),
    );
    for (final change in plan.changes) {
      plan = plan.withEnabled(change.id, true);
    }
    expect(speechOnCleanCut(words, plan).words.map((w) => w.text), [
      'Hello',
      'everyone.',
    ]);
    expect(speechOnCleanCut(words, plan.restoreAll()).toJson(), words.toJson());
  });
  test('malformed filler provenance and unknown kinds are rejected', () {
    final plan = fillerPlan(fillerFixture(ScriptLanguage.en));
    final json = jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>;
    (json['changes'] as List).first['kind'] = 'retake';
    expect(() => CleanPlan.fromJson(json), throwsFormatException);
    expect(
      () => CutChange(
        id: 'filler-1',
        kind: CutChangeKind.filler,
        range: plan.changes.single.range,
        text: 'um',
        spokenIndices: [1, 3],
      ),
      throwsFormatException,
    );
    expect(
      () => CutChange(
        id: 'quiet-1',
        kind: CutChangeKind.filler,
        range: plan.changes.single.range,
        text: 'um',
        spokenIndices: [1],
      ),
      throwsFormatException,
    );
  });
  test('legacy quiet choices stay unchanged when filler review is added', () {
    final words = fillerFixture(ScriptLanguage.en);
    final base = CleanPlan(
      takeId: 'generated',
      language: words.language,
      sourceDuration: words.duration,
      changes: [
        CutChange(
          id: 'quiet-0',
          range: SourceRange(
            start: const Duration(milliseconds: 2900),
            end: const Duration(milliseconds: 3700),
          ),
          enabled: false,
        ),
      ],
    );
    final plan = withFillerReview(
      base: base,
      transcript: words,
      quiet: fillerQuiet(words),
      snapshot: fillerScript(words, notes: true),
    );
    expect(plan.changes.last.toJson(), base.changes.single.toJson());
    expect(plan.changes.first.kind, CutChangeKind.filler);
    expect(plan.asCutPlan().duration, words.duration);
    expect(CleanPlan.fromJson(base.toJson()).fillersReviewed, isFalse);
    expect(
      () => plan.changes.first.spokenIndices.add(5),
      throwsUnsupportedError,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/render/screen_zooms.dart';
import 'package:spawnalpha/src/transcription/pointing_phrases.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

import '../render/screen_zooms_test.dart' show event, span;

const policy = ZoomPolicy(
  window: Duration(milliseconds: 1300),
  distance: .3,
  lead: Duration(milliseconds: 300),
  hold: Duration(milliseconds: 1400),
  factor: 1.8,
  maximum: 2.4,
  typingMinimum: 3,
  smallTarget: .12,
  pointWindow: Duration(milliseconds: 650),
);

ScriptDocument pointScript(ScriptLanguage language, {bool multi = false}) =>
    ScriptDocument.create(
      language: language,
      text: multi
          ? switch (language) {
              ScriptLanguage.en => 'Press this button now.',
              ScriptLanguage.fr => 'Appuyez ce bouton maintenant.',
              ScriptLanguage.ar => 'اضغط هذا الزر الآن.',
            }
          : switch (language) {
              ScriptLanguage.en => 'Click HERE now.',
              ScriptLanguage.fr => 'Cliquez ICI maintenant.',
              ScriptLanguage.ar => 'اضغط هُنَا الآن.',
            },
    );
WordTranscript speech(ScriptDocument script, {bool twice = false}) =>
    WordTranscript(
      language: script.language,
      duration: const Duration(seconds: 5),
      words: [
        for (var i = 0; i < script.tokens.length * (twice ? 2 : 1); ++i)
          SpokenWord(
            text: script.tokens[i % script.tokens.length].text,
            start: Duration(
              milliseconds:
                  200 +
                  (i % script.tokens.length) * 300 +
                  (i ~/ script.tokens.length) * 2000,
            ),
            end: Duration(
              milliseconds:
                  350 +
                  (i % script.tokens.length) * 300 +
                  (i ~/ script.tokens.length) * 2000,
            ),
            confidence: .9,
          ),
      ],
    );

List<SourceRange> phrases(
  ScriptDocument script,
  WordTranscript words, {
  bool aligned = true,
}) => pointingPhrases(
  source: words,
  snapshot: script,
  aligned: aligned,
  maximumSpan: policy.window,
);
ScreenZooms targets(
  ScriptDocument script,
  WordTranscript words,
  List<int> clicks, {
  List<SourceRange>? ranges,
}) {
  final planner = ScreenZoomPlanner(policy, pointing: phrases(script, words));
  for (final ms in clicks) {
    planner.add(event('click', ms));
  }
  return planner.finish(
    CutPlan(
      takeId: 'generated',
      language: script.language,
      sourceDuration: words.duration,
      ranges: ranges ?? [span(0, 5000)],
    ),
  );
}

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'all pointing lexicon phrases keep natural language forms $language',
      () {
        final texts = switch (language) {
          ScriptLanguage.en => ['HERE!', 'this button', 'THIS BUTTON'],
          ScriptLanguage.fr => ['ICI!', 'ce bouton', 'cette option'],
          ScriptLanguage.ar => ['هُنَا!', 'وهنا', 'هذا الزر', 'هذه الخانة'],
        };
        for (final text in texts) {
          final script = ScriptDocument.create(language: language, text: text);
          expect(phrases(script, speech(script)), hasLength(1));
        }
      },
    );
    test(
      'normalized spoken pointing phrase allows one visible click $language',
      () {
        final script = pointScript(language),
            words = speech(pointScript(language));
        final found = phrases(script, words);
        expect(found, hasLength(1));
        expect(found.single.start, words.words[1].start);
        expect(found.single.end, words.words[1].end);
        expect(() => found.clear(), throwsUnsupportedError);
        final zoom = targets(script, words, [600]);
        expect(zoom.count, 1);
        expect(zoom.steps.first.time, const Duration(milliseconds: 300));
        expect(targets(script, words, [2000]).count, 0);
        final hidden = ScreenZoomPlanner(policy, pointing: found)
          ..add(event('click', 600, visible: false));
        expect(
          hidden
              .finish(
                CutPlan(
                  takeId: 'generated',
                  language: language,
                  sourceDuration: words.duration,
                  ranges: [span(0, 5000)],
                ),
              )
              .count,
          0,
        );
      },
    );
    test(
      'Notes, absent alignment and uncertain/unsaid words never supply points $language',
      () {
        final script = pointScript(language),
            words = speech(pointScript(language));
        expect(
          phrases(script.copyWith(recordingAid: RecordingAid.notes), words),
          isEmpty,
        );
        expect(phrases(script, words, aligned: false), isEmpty);
        final uncertain = WordTranscript(
          language: language,
          duration: words.duration,
          words: [
            for (final (i, w) in words.words.indexed)
              SpokenWord(
                text: w.text,
                start: w.start,
                end: w.end,
                confidence: i == 1 ? .2 : .9,
              ),
          ],
        );
        expect(phrases(script, uncertain), isEmpty);
        final absent = WordTranscript(
          language: language,
          duration: words.duration,
          words: [words.words.first, words.words.last],
        );
        expect(phrases(script, absent), isEmpty);
        final changed = uncertain.withWord(1, switch (language) {
          ScriptLanguage.en => 'later',
          ScriptLanguage.fr => 'demain',
          ScriptLanguage.ar => 'غدا',
        });
        expect(phrases(script, changed), isEmpty);
        final corrected = changed.withWord(1, words.words[1].text);
        expect(
          phrases(script, corrected),
          isEmpty,
        ); // Restored recognition remains uncertain.
        final fixed = WordTranscript(
          language: language,
          duration: words.duration,
          words: [
            words.words.first,
            SpokenWord(
              text: words.words[1].text,
              recognizedText: changed.words[1].text,
              start: words.words[1].start,
              end: words.words[1].end,
              confidence: .2,
            ),
            words.words.last,
          ],
        );
        expect(phrases(script, fixed), hasLength(1));
      },
    );
    test('multiword points need complete reliable contiguous speech $language', () {
      final script = pointScript(language, multi: true),
          words = speech(pointScript(language, multi: true));
      expect(
        phrases(script, words).single.duration,
        const Duration(milliseconds: 450),
      );
      final uncertain = WordTranscript(
        language: language,
        duration: words.duration,
        words: [
          for (final (i, w) in words.words.indexed)
            SpokenWord(
              text: w.text,
              start: w.start,
              end: w.end,
              confidence: i == 2 ? .1 : .9,
            ),
        ],
      );
      expect(phrases(script, uncertain), isEmpty);
      final interrupted = WordTranscript(
        language: language,
        duration: words.duration,
        words: [
          words.words[0],
          words.words[1],
          SpokenWord(
            text: '123',
            start: const Duration(milliseconds: 700),
            end: const Duration(milliseconds: 750),
            confidence: .9,
          ),
          ...words.words.skip(2),
        ],
      );
      expect(phrases(script, interrupted), isEmpty);
      final brokenSentence = script.withText(
        '${script.tokens[0].text} ${script.tokens[1].text}. ${script.tokens[2].text} ${script.tokens[3].text}',
      );
      expect(phrases(brokenSentence, words), isEmpty);
    });
    test(
      'only complete retained source phrases can boost clicks after cuts $language',
      () {
        final script = pointScript(language),
            words = speech(pointScript(language), twice: true);
        final cut = targets(
          script,
          words,
          [600, 2600],
          ranges: [span(2000, 4000), span(0, 1500)],
        );
        expect(cut.count, 2);
        expect(cut.steps.where((s) => s.factor > 1).map((s) => s.time), [
          const Duration(milliseconds: 300),
          const Duration(milliseconds: 2300),
        ]);
        expect(
          targets(script, words, [600], ranges: [span(550, 2000)]).count,
          0,
        );
        // A discarded phrase removes its bonus, never ordinary click evidence.
        expect(
          targets(script, words, [600, 700], ranges: [span(550, 2000)]).count,
          1,
        );
      },
    );
  }
  test('phrase and proximity bounds reject malformed policy without changing speech', () {
    final script = pointScript(ScriptLanguage.en),
        words = speech(pointScript(ScriptLanguage.en));
    expect(
      () => pointingPhrases(
        source: words,
        snapshot: script,
        aligned: true,
        maximumSpan: Duration.zero,
      ),
      throwsFormatException,
    );
    expect(
      () => ScreenZoomPlanner(
        policy,
        pointing: [span(1000, 1200), span(500, 700)],
      ),
      throwsFormatException,
    );
    final slow = WordTranscript(
      language: words.language,
      duration: words.duration,
      words: [
        for (final (i, w) in speech(
          pointScript(words.language, multi: true),
        ).words.indexed)
          SpokenWord(
            text: w.text,
            start: Duration(milliseconds: i * 1000),
            end: Duration(milliseconds: i * 1000 + 500),
            confidence: .9,
          ),
      ],
    );
    expect(phrases(pointScript(words.language, multi: true), slow), isEmpty);
  });
}

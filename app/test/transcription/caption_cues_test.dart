import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/caption_cues.dart';
import 'package:spawnalpha/src/transcription/captions.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

ScriptDocument cueScript(ScriptLanguage language) =>
    ScriptDocument.create(
      language: language,
      text: switch (language) {
        ScriptLanguage.en => 'We launch today.',
        ScriptLanguage.fr => 'Nous lançons demain.',
        ScriptLanguage.ar => 'نحن نبدأ الآن.',
      },
    ).copyWith(
      marks: [
        const Mark(id: 'stress', kind: MarkKind.stress, start: 1, end: 1),
        const Mark(id: 'slow', kind: MarkKind.slower, start: 2, end: 2),
        const Mark.gap(id: 'gap', kind: MarkKind.breath, after: 0),
      ],
    );
WordTranscript cueSpeech(ScriptDocument script, {bool twice = false}) =>
    WordTranscript(
      language: script.language,
      duration: const Duration(seconds: 4),
      words: [
        for (var i = 0; i < (twice ? 6 : 3); i++)
          SpokenWord(
            text: script.tokens[i % 3].text,
            start: Duration(milliseconds: 200 + i * 400),
            end: Duration(milliseconds: 400 + i * 400),
            confidence: .9,
          ),
      ],
    );
CutPlan whole(WordTranscript speech) => CutPlan(
  takeId: 'generated',
  language: speech.language,
  sourceDuration: speech.duration,
  ranges: [SourceRange(start: Duration.zero, end: speech.duration)],
);

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'accepted frozen cues break actual phrases and isolate Punch stress $language',
      () {
        final script = cueScript(language),
            speech = cueSpeech(cueScript(language));
        final cues = captionCuesOnCut(
          source: speech,
          kept: speech,
          plan: whole(speech),
          snapshot: script,
          aligned: true,
        );
        expect(cues.map((c) => c.stress), [false, true, false]);
        expect(cues.map((c) => c.pace), [
          CaptionPace.normal,
          CaptionPace.normal,
          CaptionPace.slower,
        ]);
        final phrases = captionsFromSpeech(speech, cues: cues);
        expect(phrases.map((p) => p.words.length), [1, 2]);
        final punch = captionsFromSpeech(speech, cues: cues, punch: true);
        expect(punch.map((p) => p.words.length), [1, 1, 1]);
        expect(
          punch.map((c) => c.text).join(' '),
          speech.words.map((w) => w.text).join(' '),
        );
        expect(() => cues.clear(), throwsUnsupportedError);
      },
    );
    test(
      'Notes, null alignment and unaccepted cues stay unscored $language',
      () {
        final script = cueScript(language),
            speech = cueSpeech(cueScript(language));
        for (final snapshot in [
          script.copyWith(recordingAid: RecordingAid.notes),
          script.copyWith(
            marks: [for (final m in script.marks) m.copyWith(accepted: false)],
          ),
        ]) {
          final cues = captionCuesOnCut(
            source: speech,
            kept: speech,
            plan: whole(speech),
            snapshot: snapshot,
            aligned: true,
          );
          expect(
            cues.every(
              (c) =>
                  !c.stress &&
                  !c.energy &&
                  !c.breakAfter &&
                  c.pace == CaptionPace.normal,
            ),
            isTrue,
          );
        }
        final cues = captionCuesOnCut(
          source: speech,
          kept: speech,
          plan: whole(speech),
          snapshot: script,
        );
        expect(cues.every((c) => !c.stress && !c.breakAfter), isTrue);
      },
    );
    test(
      'discarding/reordering attempts keeps original cue identity $language',
      () {
        final script = cueScript(language),
            spoken = cueSpeech(cueScript(language), twice: true);
        final source = WordTranscript(
          language: language,
          duration: spoken.duration,
          words: [
            for (final (i, w) in spoken.words.indexed)
              SpokenWord(
                text: w.text,
                start: w.start,
                end: w.end,
                confidence: i == 1 ? .1 : .9,
              ),
          ],
        );
        for (final reorder in [false, true]) {
          final plan = CutPlan(
            takeId: 'generated',
            language: language,
            sourceDuration: source.duration,
            ranges: [
              SourceRange(
                start: const Duration(milliseconds: 1300),
                end: const Duration(seconds: 3),
              ),
              if (reorder)
                SourceRange(
                  start: Duration.zero,
                  end: const Duration(milliseconds: 1300),
                ),
            ],
          );
          final kept = WordTranscript(
            language: language,
            duration: plan.duration,
            words: [
              for (final w in source.words.skip(3))
                SpokenWord(
                  text: w.text,
                  start: w.start - const Duration(milliseconds: 1300),
                  end: w.end - const Duration(milliseconds: 1300),
                ),
              if (reorder)
                for (final w in source.words.take(3))
                  SpokenWord(
                    text: w.text,
                    start: w.start + const Duration(milliseconds: 1700),
                    end: w.end + const Duration(milliseconds: 1700),
                  ),
            ],
          );
          final cues = captionCuesOnCut(
            source: source,
            kept: kept,
            plan: plan,
            snapshot: script,
            aligned: true,
          );
          expect(
            cues.map((c) => c.stress),
            reorder
                ? [false, true, false, false, false, false]
                : [false, true, false],
          );
          expect(kept.words.first.start, const Duration(milliseconds: 100));
        }
      },
    );
    test(
      'changed and uncertain words get no borrowed emphasis; corrections keep truth $language',
      () {
        final script = cueScript(language),
            spoken = cueSpeech(cueScript(language));
        for (final corrected in [false, true]) {
          final word = spoken.words[1];
          final source = WordTranscript(
            language: language,
            duration: spoken.duration,
            words: [
              spoken.words.first,
              SpokenWord(
                text: corrected ? word.text : 'Different',
                start: word.start,
                end: word.end,
                confidence: .1,
                recognizedText: corrected ? 'Different' : null,
              ),
              spoken.words.last,
            ],
          );
          final cues = captionCuesOnCut(
            source: source,
            kept: source,
            plan: whole(source),
            snapshot: script,
            aligned: true,
          );
          expect(cues[1].stress, corrected);
          expect(
            captionsFromSpeech(source, cues: cues).map((c) => c.text).join(' '),
            source.words.map((w) => w.text).join(' '),
          );
        }
      },
    );
    test(
      'caption source/time mismatches are rejected rather than assigned cues $language',
      () {
        final script = cueScript(language),
            speech = cueSpeech(cueScript(language));
        final wrong = WordTranscript(
          language: language,
          duration: speech.duration,
          words: [
            for (final w in speech.words)
              SpokenWord(
                text: w.text,
                start: w.start + const Duration(microseconds: 1),
                end: w.end,
              ),
          ],
        );
        expect(
          () => captionCuesOnCut(
            source: speech,
            kept: wrong,
            plan: whole(speech),
            snapshot: script,
            aligned: true,
          ),
          throwsFormatException,
        );
        expect(
          () => captionsFromSpeech(speech, cues: []),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'Arabic kashida preserves diacritics and does not stretch non-joining text',
    () {
      expect(captionKashida('بِكُمْ'), 'بِ\u0640\u0640\u0640كُمْ');
      expect(captionKashida('نبدأ'), 'ن\u0640\u0640\u0640بدأ');
      for (final text in ['Hello', 'Bonjour', '2026', 'آآ', 'بء']) {
        expect(captionKashida(text), text);
      }
      final original = Caption(
        'بِكُمْ اليوم.',
        Duration.zero,
        const Duration(seconds: 1),
        words: [
          const CaptionWord(
            0,
            6,
            Duration.zero,
            Duration(milliseconds: 500),
            cue: CaptionCue(stress: true),
          ),
          const CaptionWord(
            7,
            6,
            Duration(milliseconds: 500),
            Duration(seconds: 1),
          ),
        ],
      );
      final display = captionDisplay(original, rtl: true);
      expect(display.text, 'بِ\u0640\u0640\u0640كُمْ اليوم.');
      expect(display.words.map((w) => w.offset), [0, 10]);
      expect(subtitleText([original]), isNot(contains('\u0640')));
      expect(identical(captionDisplay(original, rtl: false), original), isTrue);
    },
  );
  test(
    'Punch keeps at most three whole words without changing subtitle spelling',
    () {
      final script = ScriptDocument.create(
        text: 'One two three four five six seven eight nine ten.',
      );
      final speech = WordTranscript(
        language: ScriptLanguage.en,
        duration: const Duration(seconds: 5),
        words: [
          for (final (i, t) in script.tokens.indexed)
            SpokenWord(
              text: t.text,
              start: Duration(milliseconds: i * 300),
              end: Duration(milliseconds: 200 + i * 300),
            ),
        ],
      );
      expect(
        captionsFromSpeech(speech, punch: true).map((c) => c.words.length),
        [3, 3, 3, 1],
      );
      expect(
        captionsFromSpeech(speech, punch: true).map((c) => c.text).join(' '),
        script.text,
      );
    },
  );
}

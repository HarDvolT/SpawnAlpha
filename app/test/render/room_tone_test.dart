import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/render/room_tone.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

SourceRange range(int a, int b) => SourceRange(
  start: Duration(milliseconds: a),
  end: Duration(milliseconds: b),
);
CutPlan plan(ScriptLanguage language, [List<SourceRange>? ranges]) => CutPlan(
  takeId: 'generated',
  language: language,
  sourceDuration: const Duration(seconds: 4),
  ranges: ranges ?? [range(0, 1400), range(2800, 4000)],
);
WordTranscript words(
  ScriptLanguage language, {
  double? confidence = .9,
  int start = 1000,
}) => WordTranscript(
  language: language,
  duration: const Duration(seconds: 4),
  words: [
    SpokenWord(
      text: switch (language) {
        ScriptLanguage.en => 'Hello',
        ScriptLanguage.fr => 'Bonjour',
        ScriptLanguage.ar => 'مرحبا',
      },
      start: Duration(milliseconds: start),
      end: Duration(milliseconds: start + 200),
      confidence: confidence,
    ),
  ],
);
void main() {
  for (final language in ScriptLanguage.values) {
    test('only retained measured quiet supplies room tone $language', () {
      final tone = roomToneOnCut(plan(language), words(language), [
        range(0, 900),
      ])!;
      expect(tone.toJson(), {'startUs': 0, 'endUs': 100000});
      expect(RoomTone.fromJson(tone.toJson()).toJson(), tone.toJson());
      expect(roomToneOnCut(plan(language), words(language), []), isNull);
      expect(
        roomToneOnCut(plan(language), words(language), [range(1500, 2500)]),
        isNull,
      );
    });
    test(
      'word margins, uncertainty and corrections protect room tone $language',
      () {
        expect(
          roomToneOnCut(plan(language), words(language, start: 50), [
            range(0, 900),
          ])!.range.start,
          const Duration(milliseconds: 350),
        );
        expect(
          roomToneOnCut(plan(language), words(language, confidence: null), [
            range(0, 900),
          ]),
          isNull,
        );
        expect(
          roomToneOnCut(plan(language), words(language, confidence: .2), [
            range(0, 900),
          ]),
          isNull,
        );
        final corrected = words(language, start: 50).withWord(0, 'Test');
        expect(
          roomToneOnCut(plan(language), corrected, [
            range(0, 900),
          ])!.range.start,
          const Duration(milliseconds: 350),
        );
      },
    );
    test(
      'reorder, duplicate and fractional continuous splits stay safe $language',
      () {
        final reordered = plan(language, [
          range(2800, 4000),
          range(0, 50),
          range(50, 1400),
          range(2800, 4000),
        ]);
        expect(
          roomToneOnCut(reordered, words(language), [
            range(0, 900),
          ])!.range.start,
          Duration.zero,
        );
        final hole = plan(language, [
          range(0, 50),
          range(80, 1400),
          range(2800, 4000),
        ]);
        expect(
          roomToneOnCut(hole, words(language), [range(0, 900)])!.range.start,
          const Duration(milliseconds: 80),
        );
        expect(
          () => RoomTone(range(0, 100)).validateClock(hole),
          throwsFormatException,
        );
      },
    );
    test('continuous and short exports do not request room tone $language', () {
      expect(
        roomToneOnCut(
          plan(language, [range(0, 2000), range(2000, 4000)]),
          words(language),
          [range(0, 900)],
        ),
        isNull,
      );
      expect(
        roomToneOnCut(
          plan(language, [range(0, 100), range(2800, 2900)]),
          words(language),
          [range(0, 900)],
        ),
        isNull,
      );
    });
  }
  test('room tone rejects malformed metadata and evidence', () {
    for (final json in [
      true,
      {'startUs': 0, 'endUs': 79000},
      {'startUs': 0, 'endUs': 251000},
      {'startUs': -1, 'endUs': 100000},
      {'startUs': '0', 'endUs': 100000},
      {'startUs': 0, 'endUs': 100000, 'text': 'private'},
    ]) {
      expect(() => RoomTone.fromJson(json), throwsFormatException);
    }
    expect(
      () => roomToneOnCut(plan(ScriptLanguage.en), words(ScriptLanguage.en), [
        range(500, 900),
        range(0, 400),
      ]),
      throwsFormatException,
    );
    expect(
      () => roomToneOnCut(plan(ScriptLanguage.en), words(ScriptLanguage.en), [
        range(0, 4100),
      ]),
      throwsFormatException,
    );
    expect(
      () => RoomTone(range(1500, 1600)).validateClock(plan(ScriptLanguage.en)),
      throwsFormatException,
    );
  });
}

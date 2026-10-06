import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';

void main() {
  test('only discontinuous internal ranges have sound joins', () {
    SourceRange span(int start, int end) => SourceRange(
      start: Duration(seconds: start),
      end: Duration(seconds: end),
    );
    CutPlan plan(List<SourceRange> ranges) => CutPlan(
      takeId: 'generated',
      language: ScriptLanguage.en,
      sourceDuration: const Duration(seconds: 4),
      ranges: ranges,
    );
    expect(plan([span(1, 3)]).hasJoins, isFalse);
    expect(plan([span(0, 2), span(2, 4)]).hasJoins, isFalse);
    expect(plan([span(0, 1), span(3, 4)]).hasJoins, isTrue);
    expect(plan([span(3, 4), span(0, 1)]).hasJoins, isTrue);
  });
  List<SourceRange> ranges() => [
    SourceRange(
      start: const Duration(seconds: 1),
      end: const Duration(seconds: 2),
    ),
    SourceRange(
      start: const Duration(seconds: 3),
      end: const Duration(seconds: 4),
    ),
  ];
  for (final language in ScriptLanguage.values) {
    test(
      'portable $language cut matches native spike times and round-trips',
      () {
        final plan = CutPlan(
          takeId: 'generated-1',
          language: language,
          sourceDuration: const Duration(seconds: 4),
          ranges: ranges(),
        );
        expect(plan.duration, const Duration(seconds: 2));
        expect(plan.sourceTime(Duration.zero), const Duration(seconds: 1));
        expect(
          plan.sourceTime(const Duration(microseconds: 999999)),
          const Duration(microseconds: 1999999),
        );
        expect(
          plan.sourceTime(const Duration(seconds: 1)),
          const Duration(seconds: 3),
        );
        expect(plan.sourceTime(const Duration(seconds: 2)), isNull);
        expect(plan.sourceTime(const Duration(microseconds: -1)), isNull);
        final saved = CutPlan.fromJson(
          Map<String, Object?>.from(
            jsonDecode(jsonEncode(plan.toJson())) as Map,
          ),
        );
        expect(saved.language, language);
        expect(saved.toJson(), plan.toJson());
      },
    );
  }
  test('retakes can be reordered; range lists remain immutable snapshots', () {
    final input = ranges().reversed.toList();
    final plan = CutPlan(
      takeId: 'generated',
      language: ScriptLanguage.en,
      sourceDuration: const Duration(seconds: 4),
      ranges: input,
    );
    input.clear();
    expect(plan.sourceTime(Duration.zero), const Duration(seconds: 3));
    expect(
      plan.sourceTime(const Duration(seconds: 1)),
      const Duration(seconds: 1),
    );
    expect(() => plan.ranges.clear(), throwsUnsupportedError);
  });
  test(
    'invalid source intervals, versions, languages and private paths fail',
    () {
      final valid = CutPlan(
        takeId: 'generated',
        language: ScriptLanguage.en,
        sourceDuration: const Duration(seconds: 4),
        ranges: ranges(),
      ).toJson();
      for (final malformed in [
        {...valid, 'version': 2},
        {...valid, 'language': 'unknown'},
        {...valid, 'takeId': '../private.mp4'},
        {...valid, 'sourceDurationUs': 1000},
        {...valid, 'sourceDurationUs': -1},
        {...valid, 'ranges': []},
        {
          ...valid,
          'ranges': [
            {'startUs': 10, 'endUs': 10},
          ],
        },
        {
          ...valid,
          'ranges': [
            {'startUs': -1, 'endUs': 20},
          ],
        },
        {
          ...valid,
          'ranges': [
            {'startUs': 0.1, 'endUs': 20},
          ],
        },
        {...valid, 'path': 'private'},
        {...valid, 'sourceDurationUs': double.infinity},
      ]) {
        expect(() => CutPlan.fromJson(malformed), throwsFormatException);
      }
    },
  );
}

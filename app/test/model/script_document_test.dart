import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/mark_remapper.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/token.dart';

Mark stress(int start, [int? end]) => Mark(id: 's$start', kind: MarkKind.stress, start: start, end: end ?? start);

Mark pause(int after, [MarkKind kind = MarkKind.pauseShort, bool accepted = true]) =>
    Mark.gap(id: 'p$after${kind.id}', kind: kind, after: after, accepted: accepted);

void main() {
  group('alignTokens', () {
    test('follows words through an insertion', () {
      final map = alignTokens(tokenize('one two three four'), tokenize('one two and a half three four'));
      expect(map, [0, 1, 5, 6]);
    });

    test('ignores punctuation changes and reports removed words', () {
      final map = alignTokens(tokenize('we ship fast today'), tokenize('We ship, today!'));
      expect(map, [0, 1, null, 2]);
    });

    test('aligns an edit in the middle with repeated words', () {
      final map = alignTokens(tokenize('a b a b a'), tokenize('a b X a b a'));
      expect(map, [0, 1, 3, 4, 5]);
    });
  });

  group('remapMarks', () {
    test('drops a gap mark whose word is gone and shrinks spans', () {
      final map = alignTokens(tokenize('one two three four five'), tokenize('one three four five'));
      final marks = remapMarks([pause(1), stress(1, 3), pause(2)], map);
      expect(marks.map((m) => (m.kind, m.start, m.end)), [
        (MarkKind.stress, 1, 2),
        (MarkKind.pauseShort, 1, 1),
      ]);
    });
  });

  group('normalizeMarks', () {
    test('keeps one gap mark per position, accepted before stronger', () {
      final marks = normalizeMarks([
        pause(0, MarkKind.breath),
        pause(0, MarkKind.pauseLong),
        pause(1, MarkKind.pauseShort),
        pause(1, MarkKind.pauseLong, false),
        pause(3), // after the last word
      ], 4);
      expect(marks.map((m) => (m.kind, m.end)), [
        (MarkKind.pauseLong, 0),
        (MarkKind.pauseShort, 1),
      ]);
    });

    test('trims overlapping spans of the same family', () {
      final marks = normalizeMarks([
        const Mark(id: 'a', kind: MarkKind.slower, start: 0, end: 4, accepted: false),
        const Mark(id: 'b', kind: MarkKind.faster, start: 3, end: 8),
        const Mark(id: 'c', kind: MarkKind.energy, start: 0, end: 8),
      ], 10);
      expect(marks.map((m) => (m.id, m.start, m.end)), [
        ('a', 0, 2),
        ('c', 0, 8),
        ('b', 3, 8),
      ]);
    });
  });

  group('ScriptDocument', () {
    ScriptDocument doc(String text, List<Mark> marks) => ScriptDocument(
          id: 'x',
          title: 'T',
          text: text,
          language: ScriptLanguage.en,
          style: CoachingStyle.presentation,
          marks: marks,
        );

    test('withText moves marks with their words', () {
      final d = doc('Sales grew forty percent. Thanks.', [stress(2, 3), pause(3, MarkKind.pauseLong)]);
      final edited = d.withText('This year sales grew forty percent. Thanks.');
      expect(edited.marks.map((m) => (m.kind, m.start, m.end)), [
        (MarkKind.stress, 4, 5),
        (MarkKind.pauseLong, 5, 5),
      ]);
    });

    test('applySuggestion rewrites the text and keeps marks', () {
      final d = doc('We work hard in order to win.', [stress(6)]).copyWith(suggestions: [
        const Suggestion(
          id: 'g',
          kind: SuggestionKind.tighten,
          start: 3,
          end: 5,
          original: 'in order to',
          replacement: 'to',
        ),
      ]);
      final applied = d.applySuggestion(d.suggestions.single);
      expect(applied.text, 'We work hard to win.');
      expect(applied.suggestions, isEmpty);
      expect(applied.marks.single.start, 4);
    });

    test('a suggestion goes stale when its words change', () {
      final d = doc('Basically we win.', []).copyWith(suggestions: [
        const Suggestion(
          id: 'g',
          kind: SuggestionKind.tighten,
          start: 0,
          end: 1,
          original: 'Basically we',
          replacement: 'We',
        ),
      ]);
      expect(d.withText('Basically we win big.').suggestions, hasLength(1));
      expect(d.withText('Honestly we win.').suggestions, isEmpty);
    });

    test('round-trips through JSON', () {
      final d = doc('One two three.', [pause(0, MarkKind.breath, false), stress(1)]).copyWith(
        takes: [Take(path: '/tmp/a.mp4', recordedAt: DateTime.utc(2026, 9, 30), duration: const Duration(seconds: 5))],
      );
      final restored = ScriptDocument.fromJson(
        jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>,
      );
      expect(restored.text, d.text);
      expect(restored.marks, d.marks);
      expect(restored.takes.single.duration, const Duration(seconds: 5));
      expect(restored.style, CoachingStyle.presentation);
    });

    test('drops invalid marks when loading', () {
      final restored = ScriptDocument.fromJson({
        'text': 'a b',
        'marks': [
          {'kind': 'stress', 'start': 0, 'end': 0},
          {'kind': 'nope', 'start': 0, 'end': 0},
          {'kind': 'stress', 'start': 5, 'end': 6},
        ],
      });
      expect(restored.marks, hasLength(1));
    });
  });
}

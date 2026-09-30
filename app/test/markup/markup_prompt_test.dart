import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/markup/markup_engine.dart';
import 'package:spawnalpha/src/markup/markup_prompt.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';

void main() {
  final script = ScriptDocument.create(
    text: 'Click Save and wait. Then close the app.',
    language: ScriptLanguage.en,
    style: CoachingStyle.tutorial,
  );

  group('extractJson', () {
    test('drops thinking, fences and chatter around the object', () {
      expect(MarkupPrompt.extractJson('<think>hmm {no}</think>\nHere you go:\n```json\n{"a": 1}\n```\nDone.'),
          '{"a": 1}');
      expect(MarkupPrompt.extractJson('Result: {"a": {"b": 2}} hope that helps'), '{"a": {"b": 2}}');
    });
  });

  group('parseReply', () {
    test('accepts the loose shapes smaller models write', () {
      final result = MarkupPrompt.parseReply(
        '{"marks": ['
        '{"kind": "Emphasis", "start": "0", "end": 0, "text": "Click"},'
        '{"kind": "long-pause", "start": 3.0, "text": "wait."},'
        '{"kind": "slow down", "start": 1, "end": 1},'
        '{"kind": "wink", "start": 1, "end": 1}'
        ']}',
        script,
      );
      expect(result.marks.map((m) => (m.kind, m.start, m.end)), [
        (MarkKind.stress, 0, 0),
        (MarkKind.slower, 1, 1),
        (MarkKind.pauseLong, 3, 3),
      ]);
      expect(result.suggestions, isEmpty);
    });

    test('names the model when the reply is unreadable', () {
      expect(
        () => MarkupPrompt.parseReply('I cannot help with that.', script, source: 'Mistral'),
        throwsA(isA<MarkupException>().having((e) => e.message, 'message', startsWith('Mistral'))),
      );
    });

    test('finds a suggestion by its text when the indices are off', () {
      final result = MarkupPrompt.parseReply(
        '{"marks": [], "suggestions": [{"kind": "tighten", "start": 0, "end": 1, '
        '"original": "Then close the app.", "replacement": "Close the app.", "note": ""}]}',
        script,
      );
      final s = result.suggestions.single;
      expect((s.start, s.end, s.replacement, s.note), (4, 7, 'Close the app.', null));
    });
  });

  test('the system prompt spells out the JSON only when asked', () {
    expect(MarkupPrompt.system(CoachingStyle.tutorial, ScriptLanguage.fr), isNot(contains('single JSON object')));
    final withSchema = MarkupPrompt.system(CoachingStyle.tutorial, ScriptLanguage.fr, includeSchema: true);
    expect(withSchema, contains('single JSON object'));
    expect(withSchema, contains('French'));
  });
}

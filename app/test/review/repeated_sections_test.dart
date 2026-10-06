import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/review/repeated_sections.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

ScriptDocument repeatedScript(ScriptLanguage language) => ScriptDocument.create(
  language: language,
  text: switch (language) {
    ScriptLanguage.en => 'We launch today with confidence.',
    ScriptLanguage.fr => 'Nous lançons demain avec confiance.',
    ScriptLanguage.ar => 'نحن نبدأ الآن بكل ثقة.',
  },
);

WordTranscript repeatedSpeech(
  ScriptDocument script, {
  bool partial = false,
  int attempts = 2,
  double? confidence = .9,
  String? inserted,
}) {
  final text = script.tokens.map((t) => t.text).toList();
  final words = <String>[];
  for (var i = 0; i < attempts; i++) {
    final said = partial && i == 0 ? text.take(3).toList() : text.toList();
    if (inserted != null && i == 0) said.insert(1, inserted);
    words.addAll(said);
  }
  return WordTranscript(
    language: script.language,
    duration: Duration(seconds: words.length + 1),
    words: [
      for (final (i, text) in words.indexed)
        SpokenWord(
          text: text,
          start: Duration(milliseconds: i * 500 + 200),
          end: Duration(milliseconds: i * 500 + 600),
          confidence: confidence,
        ),
    ],
  );
}

void main() {
  for (final language in ScriptLanguage.values) {
    final script = repeatedScript(language);
    test(
      'frozen script and every actual attempt retain their clock $language',
      () {
        final words = repeatedSpeech(script);
        final result = repeatedSections(script, words);
        expect(result, hasLength(1));
        final section = result.single;
        expect(section.language, language);
        expect(section.scriptText, script.text);
        expect(section.scriptWords, 5);
        expect(section.attempts, hasLength(2));
        expect(
          section.attempts.every((a) => a.matched == 5 && a.covered == 5),
          isTrue,
        );
        expect(section.attempts.last.range.start, words.words[5].start);
        expect(section.attempts.last.range.end, words.words.last.end);
        expect(
          section.attempts.last.text,
          words.words.skip(5).map((w) => w.text).join(' '),
        );
        expect(() => result.clear(), throwsUnsupportedError);
        expect(() => section.attempts.clear(), throwsUnsupportedError);
        final fromJson = repeatedSectionsFromJson({
          'script': script.toJson(),
          'words': words.toJson(),
        });
        expect(fromJson.single.attempts.last.text, section.attempts.last.text);
      },
    );
    test('partial attempt has honest coverage and uncertainty $language', () {
      final words = repeatedSpeech(script, partial: true, confidence: null);
      final section = repeatedSections(script, words).single;
      expect(section.attempts.first.matched, 3);
      expect(section.attempts.first.covered, 3);
      expect(section.attempts.first.uncertain, 3);
      expect(section.attempts.last.covered, 5);
      expect(words.words, hasLength(8));
    });
    test(
      'changed words stay actual rather than being replaced by the script $language',
      () {
        final words = repeatedSpeech(script);
        final changed = words.withWord(0, switch (language) {
          ScriptLanguage.en => 'doubt',
          ScriptLanguage.fr => 'prudence',
          ScriptLanguage.ar => 'حذر',
        });
        final attempts = repeatedSections(script, changed).single.attempts;
        expect(attempts.first.matched, 4);
        expect(attempts.first.changed, 1);
        expect(attempts.first.text, contains(changed.words[0].text));
        expect(attempts.last.changed, 0);
      },
    );
    test('added speech is retained inside the compared section $language', () {
      final filler = switch (language) {
        ScriptLanguage.en => 'um',
        ScriptLanguage.fr => 'euh',
        ScriptLanguage.ar => 'يعني',
      };
      final section = repeatedSections(
        script,
        repeatedSpeech(script, inserted: filler),
      ).single;
      expect(section.attempts.first.added, 1);
      expect(section.attempts.first.text, contains(filler));
      expect(section.attempts.last.added, 0);
    });
    test(
      'different trailing wording remains in the compared source span $language',
      () {
        final words = repeatedSpeech(script);
        final changed = words.withWord(4, switch (language) {
          ScriptLanguage.en => 'doubt',
          ScriptLanguage.fr => 'prudence',
          ScriptLanguage.ar => 'حذر',
        });
        final attempt = repeatedSections(script, changed).single.attempts.first;
        expect(attempt.text, contains(changed.words[4].text));
        expect(attempt.range.end, changed.words[4].end);
        expect(attempt.changed + attempt.added, 1);
        expect(attempt.matched, 4);
      },
    );
    test(
      'ordinary script repetition, Notes and a single echo are not retakes $language',
      () {
        final ordinary = script.withText('${script.text} ${script.text}');
        expect(
          repeatedSections(ordinary, repeatedSpeech(ordinary, attempts: 1)),
          isEmpty,
        );
        expect(
          repeatedSections(
            script.copyWith(recordingAid: RecordingAid.notes),
            repeatedSpeech(script),
          ),
          isEmpty,
        );
        expect(
          repeatedSections(
            script,
            repeatedSpeech(
              script,
              attempts: 1,
              inserted: script.tokens.first.text,
            ),
          ),
          isEmpty,
        );
        expect(
          repeatedSections(
            script,
            WordTranscript(
              language: language,
              duration: const Duration(seconds: 1),
              words: [],
            ),
          ),
          isEmpty,
        );
      },
    );
    test('sections and many attempts stay separate $language', () {
      final two = script.withText('${script.text} ${script.text}');
      final sections = repeatedSections(two, repeatedSpeech(two, attempts: 4));
      expect(sections, hasLength(2));
      expect(sections.every((s) => s.attempts.length == 4), isTrue);
    });
  }
  test('mismatched language and excessive alignment work fail rather than invent comparisons', () {
    final script = repeatedScript(ScriptLanguage.en);
    expect(
      () => repeatedSections(
        script,
        repeatedSpeech(repeatedScript(ScriptLanguage.fr)),
      ),
      throwsFormatException,
    );
    final long = script.withText(List.filled(2000, 'hello').join(' '));
    expect(
      () => repeatedSections(long, repeatedSpeech(long, attempts: 1)),
      throwsFormatException,
    );
  });
}

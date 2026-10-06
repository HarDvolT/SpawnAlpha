import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/script_alignment.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

WordTranscript speech(ScriptLanguage language, String text) => WordTranscript(
  language: language,
  duration: const Duration(minutes: 1),
  words: [
    for (final (i, word) in text.split(' ').indexed)
      SpokenWord(
        text: word,
        start: Duration(milliseconds: i * 500),
        end: Duration(milliseconds: i * 500 + 400),
        confidence: .8,
      ),
  ],
);

void main() {
  const examples = [
    (
      ScriptLanguage.en,
      'We launch today.',
      'we launch today',
      'um',
      'tomorrow',
    ),
    (
      ScriptLanguage.fr,
      'Nous lançons demain.',
      'nous lançons demain',
      'euh',
      'mardi',
    ),
    (ScriptLanguage.ar, 'نحن نبدأ الآن.', 'نحن نبدأ الان', 'يعني', 'غدا'),
  ];
  for (final (language, text, said, filler, changed) in examples) {
    final script = ScriptDocument.create(text: text, language: language);
    test(
      '$language immutable timing round trip and exact normalized alignment',
      () {
        final transcript = speech(language, said);
        final decoded = WordTranscript.fromJson(
          jsonDecode(jsonEncode(transcript.toJson())) as Map<String, Object?>,
        );
        expect(decoded.toJson(), transcript.toJson());
        final result = alignTranscript(script, decoded);
        expect(result.words.map((w) => w.tokenIndex), [0, 1, 2]);
        expect(result.words.every((w) => w.match == WordMatch.exact), isTrue);
        expect(result.missedTokens, isEmpty);
        expect(result.attemptCount, 1);
        expect(() => decoded.words.clear(), throwsUnsupportedError);
        expect(() => result.words.clear(), throwsUnsupportedError);
      },
    );
    test(
      '$language preserves added/changed speech and missing script words',
      () {
        final result = alignTranscript(
          script,
          speech(language, '$filler $said $filler'),
        );
        expect(result.words.map((w) => w.match), [
          WordMatch.added,
          WordMatch.exact,
          WordMatch.exact,
          WordMatch.exact,
          WordMatch.added,
        ]);
        final altered = alignTranscript(
          script,
          speech(language, '${said.split(' ').take(2).join(' ')} $changed'),
        );
        expect(altered.words.last.match, WordMatch.changed);
        expect(altered.transcript.words.last.text, changed);
        final omitted = alignTranscript(
          script,
          speech(language, '${said.split(' ').first} ${said.split(' ').last}'),
        );
        expect(omitted.missedTokens, [1]);
      },
    );
    test(
      '$language anchored restart preserves both attempts and video times',
      () {
        final result = alignTranscript(
          script,
          speech(language, '$said $filler $said'),
        );
        expect(result.words.map((w) => w.tokenIndex), [0, 1, 2, null, 0, 1, 2]);
        expect(result.words.map((w) => w.attempt), [0, 0, 0, 0, 1, 1, 1]);
        expect(result.occurrences(0).length, 2);
        expect(result.attemptCount, 2);
        expect(
          result.transcript.words[result.occurrences(0).last.spokenIndex].start,
          const Duration(seconds: 2),
        );
      },
    );
    test(
      '$language punctuation is unspoken, empty/silent takes are missed',
      () {
        final withPunctuation = ScriptDocument.create(
          language: language,
          text: '— $text',
        );
        final result = alignTranscript(withPunctuation, speech(language, said));
        expect(result.unspokenTokens, [0]);
        expect(result.words.map((w) => w.tokenIndex), [1, 2, 3]);
        final silent = alignTranscript(
          script,
          WordTranscript(
            language: language,
            duration: const Duration(seconds: 4),
            words: [],
          ),
        );
        expect(silent.missedTokens, [0, 1, 2]);
        expect(silent.attemptCount, 0);
        final empty = alignTranscript(
          ScriptDocument.create(language: language),
          speech(language, said),
        );
        expect(empty.words.every((w) => w.match == WordMatch.added), isTrue);
      },
    );
  }
  test('short restarts, ordinary repeated words and partial attempts', () {
    final script = ScriptDocument.create(
      text: 'we launch today with confidence',
    );
    final result = alignTranscript(
      script,
      speech(
        ScriptLanguage.en,
        'we launch today we launch today with confidence',
      ),
    );
    expect(result.words.map((w) => w.tokenIndex), [0, 1, 2, 0, 1, 2, 3, 4]);
    expect(result.attemptCount, 2);
    final ordinary = alignTranscript(
      ScriptDocument.create(text: 'we know we know'),
      speech(ScriptLanguage.en, 'we know we know'),
    );
    expect(ordinary.attemptCount, 1);
    final single = alignTranscript(
      ScriptDocument.create(text: 'we launch today'),
      speech(ScriptLanguage.en, 'we we launch today'),
    );
    expect(single.attemptCount, 1);
    expect(single.words.where((w) => w.match == WordMatch.added).length, 1);
    final tail = alignTranscript(
      ScriptDocument.create(text: 'we launch today'),
      speech(ScriptLanguage.en, 'today we launch today'),
    );
    expect(tail.attemptCount, 1);
    final pair = alignTranscript(
      ScriptDocument.create(text: 'hello world'),
      speech(ScriptLanguage.en, 'hello world hello world'),
    );
    expect(pair.attemptCount, 2);
  });
  test('rejects invalid times, overlap, confidence, schema, language and work size', () {
    SpokenWord word({
      Duration start = Duration.zero,
      Duration end = const Duration(seconds: 1),
      double? confidence,
    }) => SpokenWord(
      text: 'hello',
      start: start,
      end: end,
      confidence: confidence,
    );
    expect(() => word(end: Duration.zero), throwsFormatException);
    expect(
      () => SpokenWord(
        text: 'hello\uD800',
        start: Duration.zero,
        end: const Duration(seconds: 1),
      ),
      throwsFormatException,
    );
    expect(
      () => word(end: const Duration(microseconds: 9007199254740992)),
      throwsFormatException,
    );
    expect(
      () => word(start: const Duration(seconds: -1)),
      throwsFormatException,
    );
    expect(() => word(confidence: double.nan), throwsFormatException);
    expect(() => word(confidence: 1.1), throwsFormatException);
    expect(
      () => WordTranscript(
        language: ScriptLanguage.en,
        duration: const Duration(seconds: 2),
        words: [word(), word()],
      ),
      throwsFormatException,
    );
    expect(
      () => WordTranscript(
        language: ScriptLanguage.en,
        duration: Duration.zero,
        words: [word()],
      ),
      throwsFormatException,
    );
    final json = speech(ScriptLanguage.en, 'hello').toJson();
    for (final bad in [
      {...json, 'version': 2},
      {...json, 'language': 'xx'},
      {...json, 'durationUs': 1.5},
      {
        ...json,
        'words': [null],
      },
      {
        ...json,
        'words': [
          {'text': 'hello there', 'startUs': 0, 'endUs': 1},
        ],
      },
    ]) {
      expect(() => WordTranscript.fromJson(bad), throwsFormatException);
    }
    expect(
      () => alignTranscript(
        ScriptDocument.create(),
        speech(ScriptLanguage.fr, 'bonjour'),
      ),
      throwsFormatException,
    );
    expect(
      () => alignTranscript(
        ScriptDocument.create(text: 'hello'),
        speech(ScriptLanguage.en, 'hello'),
        maxCells: 3,
      ),
      throwsFormatException,
    );
  });
}

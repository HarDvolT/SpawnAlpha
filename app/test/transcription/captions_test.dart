import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';
import 'package:spawnalpha/src/transcription/captions.dart';

void main() {
  for (final language in ScriptLanguage.values) {
    final text = switch (language) {
      ScriptLanguage.en => 'Hello everyone.',
      ScriptLanguage.fr => 'Bonjour à tous.',
      ScriptLanguage.ar => 'مرحبا بكم اليوم.',
    };
    test('SRT and VTT keep actual words and times $language', () {
      var position = 1000000;
      final transcript = WordTranscript(
        language: language,
        duration: const Duration(seconds: 4),
        words: [
          for (final word in text.split(' '))
            SpokenWord(
              text: word,
              start: Duration(microseconds: position),
              end: Duration(microseconds: position += 300000),
            ),
        ],
      );
      final captions = captionsFromSpeech(transcript);
      expect(captions.single.text, text);
      expect(subtitleText(captions), contains('00:00:01,000 -->'));
      expect(
        subtitleText(captions, vtt: true),
        startsWith('WEBVTT\n\n00:00:01.000 -->'),
      );
    });
  }
  test('long silence breaks captions and VTT speech is escaped', () {
    final transcript = WordTranscript(
      language: ScriptLanguage.en,
      duration: const Duration(seconds: 4),
      words: [
        SpokenWord(
          text: '<Hello>',
          start: Duration.zero,
          end: const Duration(seconds: 1),
        ),
        SpokenWord(
          text: 'again.',
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 3),
        ),
      ],
    );
    final captions = captionsFromSpeech(transcript);
    expect(captions, hasLength(2));
    expect(subtitleText(captions, vtt: true), contains('&lt;Hello&gt;'));
    expect(captions.last.start, const Duration(seconds: 2));
  });
}

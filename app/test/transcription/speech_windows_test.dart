import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/speech_windows.dart';

Map<String, Object?> speechWindow(
  String text, {
  int offset = 0,
  int from = 0,
  int to = 3000000,
  int length = 3000000,
  int start = 200000,
  int end = 600000,
}) => {
  'offsetUs': offset,
  'keepStartUs': from,
  'keepEndUs': to,
  'durationUs': length,
  'pieces': [
    {
      'bytes': utf8.encode(text),
      'startUs': start,
      'endUs': end,
      'probability': 0.9,
    },
  ],
};

void main() {
  for (final language in ScriptLanguage.values) {
    final text = switch (language) {
      ScriptLanguage.en => 'Hello',
      ScriptLanguage.fr => 'Bonjour',
      ScriptLanguage.ar => 'مرحبا',
    };
    test('complete words survive an overlap seam $language', () {
      final transcript = transcriptFromWindows(
        language,
        const Duration(seconds: 6),
        [
          speechWindow(text, to: 3000000, length: 4000000),
          speechWindow(
            text,
            offset: 2000000,
            from: 3000000,
            to: 6000000,
            length: 4000000,
            start: 1500000,
            end: 1800000,
          ),
        ],
      );
      expect(transcript.words.map((w) => w.text), [text, text]);
      expect(transcript.words.last.start.inMicroseconds, 3500000);
    });
  }
  test('Arabic UTF-8 fragments are joined before decoding', () {
    final bytes = utf8.encode('مرحبا');
    final window = speechWindow('unused');
    window['pieces'] = [
      {
        'bytes': bytes.sublist(0, 1),
        'startUs': 100000,
        'endUs': 200000,
        'probability': 0.9,
      },
      {
        'bytes': bytes.sublist(1),
        'startUs': 200000,
        'endUs': 400000,
        'probability': 0.9,
      },
    ];
    expect(
      transcriptFromWindows(ScriptLanguage.ar, const Duration(seconds: 3), [
        window,
      ]).words.single.text,
      'مرحبا',
    );
  });
  test(
    'incomplete, unordered and overlapping windows fail without invented times',
    () {
      expect(
        () => transcriptFromWindows(
          ScriptLanguage.en,
          const Duration(seconds: 4),
          [speechWindow('Hello')],
        ),
        throwsFormatException,
      );
      expect(
        () => transcriptFromWindows(
          ScriptLanguage.en,
          const Duration(seconds: 3),
          [speechWindow('Hello', from: 1)],
        ),
        throwsFormatException,
      );
      expect(
        () => transcriptFromWindows(
          ScriptLanguage.en,
          const Duration(seconds: 6),
          [
            speechWindow(
              'One',
              to: 3000000,
              length: 4000000,
              start: 2500000,
              end: 3400000,
            ),
            speechWindow(
              'Two',
              offset: 2000000,
              from: 3000000,
              to: 6000000,
              length: 4000000,
              start: 1000000,
              end: 1400000,
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );
  test('silent windows produce no words', () {
    final window = speechWindow('ignored')..['pieces'] = [];
    expect(
      transcriptFromWindows(ScriptLanguage.en, const Duration(seconds: 3), [
        window,
      ]).words,
      isEmpty,
    );
  });
}

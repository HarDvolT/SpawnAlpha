import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/speech_pieces.dart';

SpeechPiece piece(
  List<int> bytes,
  int start,
  int end, [
  double probability = .9,
]) => SpeechPiece(
  bytes: bytes,
  start: Duration(milliseconds: start),
  end: Duration(milliseconds: end),
  probability: probability,
);

void main() {
  for (final (language, first, second) in [
    (ScriptLanguage.en, 'hello', 'world'),
    (ScriptLanguage.fr, 'ça', 'lance'),
    (ScriptLanguage.ar, 'أهلا', 'بالعالم'),
  ]) {
    test(
      '$language joins fragmented UTF-8 and retains timing and punctuation',
      () {
        final bytes = utf8.encode(first);
        final result = transcriptFromPieces(
          language: language,
          duration: const Duration(seconds: 2),
          pieces: [
            piece([32, bytes.first], 100, 150),
            piece(bytes.skip(1).toList(), 150, 400, .7),
            piece(utf8.encode(' $second'), 600, 900),
            piece(utf8.encode(' .'), 900, 900),
          ],
        );
        expect(result.words.map((w) => w.text), [first, '$second.']);
        expect(result.words.first.start, const Duration(milliseconds: 100));
        expect(result.words.first.end, const Duration(milliseconds: 400));
        expect(result.words.first.confidence, .7);
        expect(result.words.last.end, const Duration(milliseconds: 900));
      },
    );
  }
  test(
    'does not invent word times for overlapping or zero-length estimates',
    () {
      for (final pieces in [
        [
          piece(utf8.encode(' hi'), 0, 400),
          piece(utf8.encode(' there'), 300, 500),
        ],
        [piece(utf8.encode(' hi'), 0, 0)],
        [piece(utf8.encode(' hi there'), 0, 400)],
      ]) {
        expect(
          () => transcriptFromPieces(
            language: ScriptLanguage.en,
            duration: const Duration(seconds: 1),
            pieces: pieces,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'rejects invalid UTF-8, control bytes and unsafe times/probabilities',
    () {
      for (final bytes in [
        [255],
        [0],
        [127],
        [0xD8],
      ]) {
        expect(
          () => transcriptFromPieces(
            language: ScriptLanguage.ar,
            duration: const Duration(seconds: 1),
            pieces: [piece(bytes, 0, 400)],
          ),
          throwsFormatException,
        );
      }
      expect(() => piece([300], 0, 1), throwsFormatException);
      expect(() => piece([65], 0, 1, double.nan), throwsFormatException);
      expect(() => piece([65], -1, 1), throwsFormatException);
      expect(() => piece([65], 2, 1), throwsFormatException);
      expect(
        () => transcriptFromPieces(
          language: ScriptLanguage.en,
          duration: const Duration(seconds: 1),
          pieces: [
            piece([65], 0, 2000),
          ],
        ),
        throwsFormatException,
      );
    },
  );
}

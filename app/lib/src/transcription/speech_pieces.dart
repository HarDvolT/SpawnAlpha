import 'dart:convert';

import '../model/script_language.dart';
import '../model/token.dart';
import 'word_timing.dart';

/// A UTF-8 tokenizer fragment. A fragment can end inside an Arabic character;
/// decoding each fragment separately would corrupt the recognised text.
class SpeechPiece {
  SpeechPiece({
    required List<int> bytes,
    required this.start,
    required this.end,
    required this.probability,
  }) : bytes = List.unmodifiable(bytes) {
    if (bytes.isEmpty ||
        bytes.length > 4096 ||
        bytes.any((byte) => byte < 0 || byte > 255) ||
        start.isNegative ||
        end < start ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1) {
      throw const FormatException('Invalid speech fragment');
    }
  }
  final List<int> bytes;
  final Duration start, end;
  final double probability;
}

/// Joins bytes before Unicode decoding and preserves the original take clock.
/// It never distributes a segment's duration evenly across invented words.
/// Invalid/overlapping estimates need a recognizer retry/review, not silent repair.
WordTranscript transcriptFromPieces({
  required ScriptLanguage language,
  required Duration duration,
  required List<SpeechPiece> pieces,
}) {
  if (pieces.length > 100000) {
    throw const FormatException('Too many speech fragments');
  }
  final words = <SpokenWord>[];
  final buffer = <int>[];
  Duration? start;
  var end = Duration.zero, probability = 1.0;
  void finishWord() {
    if (buffer.isEmpty) return;
    String text;
    try {
      text = utf8.decode(buffer);
    } on FormatException {
      throw const FormatException('Invalid speech encoding');
    }
    if (normalizeWord(text).isNotEmpty) {
      words.add(
        SpokenWord(
          text: text,
          start: start!,
          end: end,
          confidence: probability,
        ),
      );
    } else if (words.isNotEmpty) {
      // Punctuation has no independent spoken timing, but remains in captions.
      final previous = words.removeLast();
      words.add(
        SpokenWord(
          text: '${previous.text}$text',
          start: previous.start,
          end: previous.end,
          confidence: previous.confidence,
        ),
      );
    }
    buffer.clear();
    start = null;
    end = Duration.zero;
    probability = 1;
  }

  for (final piece in pieces) {
    if (piece.end > duration) {
      throw const FormatException('Invalid speech fragment time');
    }
    for (final byte in piece.bytes) {
      if (byte == 32 || byte == 9 || byte == 10 || byte == 13) {
        finishWord();
      } else {
        if (byte < 32 || byte == 127 || buffer.length >= 4096) {
          throw const FormatException('Invalid speech word');
        }
        buffer.add(byte);
        if (start == null || piece.start < start!) start = piece.start;
        if (piece.end > end) end = piece.end;
        if (piece.probability < probability) probability = piece.probability;
      }
    }
  }
  finishWord();
  return WordTranscript(language: language, duration: duration, words: words);
}

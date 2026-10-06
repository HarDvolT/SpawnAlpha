import 'dart:convert';

import '../model/script_language.dart';
import '../model/token.dart';

/// A recognizer's word and its estimated half-open range on the take's clock.
/// Text is personal data: persist locally, never include it in diagnostics.
class SpokenWord {
  SpokenWord({
    required this.text,
    required this.start,
    required this.end,
    this.confidence,
  }) {
    if (text.trim() != text ||
        text.isEmpty ||
        text.length > 1024 ||
        RegExp(r'\s').hasMatch(text) ||
        normalizeWord(text).isEmpty ||
        start.isNegative ||
        end.inMicroseconds > 9007199254740991 ||
        utf8.decode(utf8.encode(text)) != text ||
        end <= start ||
        (confidence != null &&
            (!confidence!.isFinite || confidence! < 0 || confidence! > 1))) {
      throw const FormatException('Invalid spoken word');
    }
  }

  final String text;
  final Duration start, end;
  final double? confidence;
  String get bare => normalizeWord(text);

  Map<String, Object?> toJson() => {
    'text': text,
    'startUs': start.inMicroseconds,
    'endUs': end.inMicroseconds,
    'confidence': ?confidence,
  };

  factory SpokenWord.fromJson(Map<String, Object?> json) {
    final text = json['text'], start = json['startUs'], end = json['endUs'];
    final confidence = json['confidence'];
    if (text is! String ||
        start is! int ||
        end is! int ||
        (confidence != null && confidence is! num)) {
      throw const FormatException('Invalid spoken word');
    }
    return SpokenWord(
      text: text,
      start: Duration(microseconds: start),
      end: Duration(microseconds: end),
      confidence: (confidence as num?)?.toDouble(),
    );
  }
}

/// Immutable recognition output. Word times are estimates, not forced script
/// times. Changed/added speech must survive into captions and human review.
class WordTranscript {
  WordTranscript({
    required this.language,
    required this.duration,
    required List<SpokenWord> words,
  }) : words = List.unmodifiable(words) {
    if (duration.isNegative ||
        duration.inMicroseconds > 9007199254740991 ||
        words.length > 100000) {
      throw const FormatException('Invalid transcript');
    }
    var previous = Duration.zero;
    for (final word in words) {
      if (word.start < previous || word.end > duration) {
        throw const FormatException('Invalid word timing');
      }
      previous = word.end;
    }
  }

  final ScriptLanguage language;
  final Duration duration;
  final List<SpokenWord> words;

  Map<String, Object?> toJson() => {
    'version': 1,
    'language': language.name,
    'durationUs': duration.inMicroseconds,
    'words': [for (final word in words) word.toJson()],
  };

  factory WordTranscript.fromJson(Map<String, Object?> json) {
    final language = ScriptLanguage.values
        .where((l) => l.name == json['language'])
        .firstOrNull;
    final duration = json['durationUs'], words = json['words'];
    if (json['version'] != 1 ||
        language == null ||
        duration is! int ||
        words is! List ||
        words.length > 100000) {
      throw const FormatException('Invalid transcript');
    }
    return WordTranscript(
      language: language,
      duration: Duration(microseconds: duration),
      words: [
        for (final word in words)
          if (word is Map<String, Object?>)
            SpokenWord.fromJson(word)
          else
            throw const FormatException('Invalid spoken word'),
      ],
    );
  }
}

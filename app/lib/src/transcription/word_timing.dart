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
    this.recognizedText,
  }) {
    if (!_validWordText(text) ||
        start.isNegative ||
        end.inMicroseconds > 9007199254740991 ||
        end <= start ||
        (recognizedText != null && !_validWordText(recognizedText!)) ||
        (confidence != null &&
            (!confidence!.isFinite || confidence! < 0 || confidence! > 1))) {
      throw const FormatException('Invalid spoken word');
    }
  }

  final String text;
  final Duration start, end;
  final double? confidence;

  /// Original spelling retained only when the owner corrects recognition.
  final String? recognizedText;
  bool get corrected => recognizedText != null;
  String get bare => normalizeWord(text);
  SpokenWord withText(String value) {
    final original = recognizedText ?? text;
    return SpokenWord(
      text: value,
      start: start,
      end: end,
      confidence: confidence,
      recognizedText: value == original ? null : original,
    );
  }

  Map<String, Object?> toJson() => {
    'text': text,
    'startUs': start.inMicroseconds,
    'endUs': end.inMicroseconds,
    'confidence': ?confidence,
    'recognizedText': ?recognizedText,
  };

  factory SpokenWord.fromJson(Map<String, Object?> json) {
    final text = json['text'], start = json['startUs'], end = json['endUs'];
    final confidence = json['confidence'];
    if (text is! String ||
        start is! int ||
        end is! int ||
        (confidence != null && confidence is! num) ||
        (json['recognizedText'] != null && json['recognizedText'] is! String)) {
      throw const FormatException('Invalid spoken word');
    }
    return SpokenWord(
      text: text,
      start: Duration(microseconds: start),
      end: Duration(microseconds: end),
      confidence: (confidence as num?)?.toDouble(),
      recognizedText: json['recognizedText'] as String?,
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
  WordTranscript withWord(int index, String text) {
    if (index < 0 || index >= words.length) {
      throw const FormatException('Unknown spoken word');
    }
    return WordTranscript(
      language: language,
      duration: duration,
      words: [
        for (var i = 0; i < words.length; i++)
          i == index ? words[i].withText(text) : words[i],
      ],
    );
  }

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

bool _validWordText(String text) =>
    text.trim() == text &&
    text.isNotEmpty &&
    text.length <= 1024 &&
    !RegExp(r'\s').hasMatch(text) &&
    normalizeWord(text).isNotEmpty &&
    utf8.decode(utf8.encode(text)) == text;

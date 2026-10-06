import '../model/script_language.dart';
import '../model/cut_plan.dart';
import 'speech_pieces.dart';
import 'word_timing.dart';

/// Assemble complete Unicode words within each overlap window, then select
/// words by their estimated midpoint. Never split UTF-8 pieces at a seam.
WordTranscript transcriptFromWindows(
  ScriptLanguage language,
  Duration duration,
  List<Object?> windows,
) {
  final words = <SpokenWord>[];
  var previousEnd = 0, count = 0;
  if (duration <= Duration.zero ||
      duration > const Duration(hours: 24) ||
      windows.length > 3324) {
    throw const FormatException('Speech output exceeds capacity');
  }
  for (final item in windows) {
    if (item is! Map) throw const FormatException('Invalid speech window');
    final offset = item['offsetUs'],
        start = item['keepStartUs'],
        end = item['keepEndUs'],
        length = item['durationUs'],
        pieces = item['pieces'];
    if (offset is! int ||
        start is! int ||
        end is! int ||
        length is! int ||
        pieces is! List ||
        offset < 0 ||
        offset > start ||
        start != previousEnd ||
        end <= start ||
        end > duration.inMicroseconds ||
        length < 0 ||
        length > 30000000 ||
        offset + length > duration.inMicroseconds) {
      throw const FormatException('Invalid speech window');
    }
    count += pieces.length;
    if (count > 100000) {
      throw const FormatException('Speech output exceeds capacity');
    }
    final transcript = transcriptFromPieces(
      language: language,
      duration: Duration(microseconds: length),
      pieces: [for (final raw in pieces) _piece(raw)],
    );
    for (final word in transcript.words) {
      final midpoint =
          offset + (word.start.inMicroseconds + word.end.inMicroseconds) ~/ 2;
      if (midpoint >= start && midpoint < end) {
        words.add(
          SpokenWord(
            text: word.text,
            start: Duration(microseconds: offset + word.start.inMicroseconds),
            end: Duration(microseconds: offset + word.end.inMicroseconds),
            confidence: word.confidence,
          ),
        );
      }
    }
    previousEnd = end;
  }
  if (previousEnd != duration.inMicroseconds) {
    throw const FormatException('Incomplete speech windows');
  }
  // Conflicting estimates need review, rather than shifting or dropping words.
  return WordTranscript(language: language, duration: duration, words: words);
}

List<SourceRange> quietFromWindows(Duration duration, List<Object?> windows) {
  final ranges = <SourceRange>[];
  for (final value in windows) {
    if (value is! Map) throw const FormatException('Invalid quiet window');
    final quiet = value['quiet'];
    if (quiet == null) {
      continue; // Older/fake recognizers have no audio evidence.
    }
    if (quiet is! List || quiet.length > 100000) {
      throw const FormatException('Invalid quiet intervals');
    }
    for (final item in quiet) {
      if (item is! Map ||
          item['startUs'] is! int ||
          item['endUs'] is! int ||
          value['keepStartUs'] is! int ||
          value['keepEndUs'] is! int) {
        throw const FormatException('Invalid quiet interval');
      }
      final start = item['startUs'] as int, end = item['endUs'] as int;
      if (start < (value['keepStartUs'] as int) ||
          end > (value['keepEndUs'] as int) ||
          start < 0 ||
          end <= start ||
          end > duration.inMicroseconds ||
          (ranges.isNotEmpty && start < ranges.last.end.inMicroseconds) ||
          ranges.length >= 100000) {
        throw const FormatException('Invalid quiet interval');
      }
      if (ranges.isNotEmpty && ranges.last.end.inMicroseconds == start) {
        final previous = ranges.removeLast();
        ranges.add(
          SourceRange(
            start: previous.start,
            end: Duration(microseconds: end),
          ),
        );
      } else {
        ranges.add(
          SourceRange(
            start: Duration(microseconds: start),
            end: Duration(microseconds: end),
          ),
        );
      }
    }
  }
  return List.unmodifiable(ranges);
}

SpeechPiece _piece(Object? value) {
  if (value is! Map ||
      value['bytes'] is! List ||
      value['startUs'] is! int ||
      value['endUs'] is! int ||
      value['probability'] is! num) {
    throw const FormatException('Invalid speech fragment');
  }
  final bytes = value['bytes'] as List;
  if (bytes.any((b) => b is! int)) {
    throw const FormatException('Invalid speech bytes');
  }
  return SpeechPiece(
    bytes: bytes.cast<int>(),
    start: Duration(microseconds: value['startUs'] as int),
    end: Duration(microseconds: value['endUs'] as int),
    probability: (value['probability'] as num).toDouble(),
  );
}

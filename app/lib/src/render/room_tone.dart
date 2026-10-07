import '../cut/quiet_evidence.dart';
import '../model/cut_plan.dart';
import '../transcription/word_timing.dart';

List<SourceRange> _union(Iterable<SourceRange> ranges) {
  final sorted = ranges.toList()..sort((a, b) => a.start.compareTo(b.start));
  final merged = <SourceRange>[];
  for (final range in sorted) {
    if (merged.isEmpty || merged.last.end < range.start) {
      merged.add(range);
    } else if (merged.last.end < range.end) {
      merged[merged.length - 1] = SourceRange(
        start: merged.last.start,
        end: range.end,
      );
    }
  }
  return merged;
}

/// One bounded quiet sample on the source clock, with no paths or word text.
class RoomTone {
  RoomTone(this.range) {
    if (range.duration < const Duration(milliseconds: 80) ||
        range.duration > const Duration(milliseconds: 250)) {
      throw const FormatException('Invalid room tone');
    }
  }
  final SourceRange range;
  Map<String, Object?> toJson() => range.toJson();
  factory RoomTone.fromJson(Object? json) {
    if (json is! Map ||
        json.length != 2 ||
        json['startUs'] is! int ||
        json['endUs'] is! int) {
      throw const FormatException('Invalid room tone');
    }
    try {
      return RoomTone(
        SourceRange(
          start: Duration(microseconds: json['startUs'] as int),
          end: Duration(microseconds: json['endUs'] as int),
        ),
      );
    } on ArgumentError {
      throw const FormatException('Invalid room tone');
    }
  }
  void validateClock(CutPlan plan) {
    if (!plan.hasJoins ||
        plan.duration < const Duration(milliseconds: 400) ||
        !_union(
          plan.ranges,
        ).any((kept) => range.start >= kept.start && range.end <= kept.end)) {
      throw const FormatException('Room tone is not retained');
    }
  }
}

/// Only measured quiet in retained source spans is eligible. All recognized
/// words are protected, including discarded words and one-second uncertainty
/// margins. Sorted interval unions keep reordered/duplicated plans bounded.
RoomTone? roomToneOnCut(
  CutPlan plan,
  WordTranscript words,
  List<SourceRange> quiet, {
  Duration sample = const Duration(milliseconds: 100),
}) {
  if (words.duration != plan.sourceDuration ||
      sample < const Duration(milliseconds: 80) ||
      sample > const Duration(milliseconds: 250) ||
      quiet.length > 100000) {
    throw const FormatException('Invalid room-tone evidence');
  }
  var previous = Duration.zero;
  for (final range in quiet) {
    if (range.start < previous || range.end > words.duration) {
      throw const FormatException('Invalid room-tone evidence');
    }
    previous = range.end;
  }
  if (!plan.hasJoins || plan.duration < const Duration(milliseconds: 400)) {
    return null;
  }
  final kept = _union(plan.ranges);
  final guards = _union(
    words.words.map((word) {
      final start = word.start - wordSafetyMargin(word),
          end = word.end + wordSafetyMargin(word);
      return SourceRange(
        start: start < Duration.zero ? Duration.zero : start,
        end: end > words.duration ? words.duration : end,
      );
    }),
  );
  var q = 0, k = 0, g = 0;
  while (q < quiet.length && k < kept.length) {
    final start = quiet[q].start > kept[k].start
        ? quiet[q].start
        : kept[k].start;
    final end = quiet[q].end < kept[k].end ? quiet[q].end : kept[k].end;
    var cursor = start;
    while (g < guards.length && guards[g].end <= cursor) {
      ++g;
    }
    var guard = g;
    while (cursor + sample <= end) {
      if (guard == guards.length || guards[guard].start >= cursor + sample) {
        final result = RoomTone(
          SourceRange(start: cursor, end: cursor + sample),
        );
        result.validateClock(plan);
        return result;
      }
      if (guards[guard].end > cursor) cursor = guards[guard].end;
      ++guard;
    }
    if (quiet[q].end <= kept[k].end) {
      ++q;
    } else {
      ++k;
    }
  }
  return null;
}

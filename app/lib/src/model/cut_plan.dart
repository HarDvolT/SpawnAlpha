import 'script_language.dart';

const _maxTimeUs = 1 << 53;

/// A half-open source interval. Source files remain separate from the portable
/// plan and are resolved locally from takeId by the recording store.
class SourceRange {
  SourceRange({required this.start, required this.end}) {
    if (start.isNegative || end <= start || end.inMicroseconds > _maxTimeUs) {
      throw ArgumentError('Invalid source range');
    }
  }
  final Duration start, end;
  Duration get duration => end - start;
  Map<String, Object?> toJson() => {
    'startUs': start.inMicroseconds,
    'endUs': end.inMicroseconds,
  };
}

/// Minimal renderer-independent EDL foundation. Ranges are in output order;
/// retake selection may reorder or reuse source spans. There is no destructive
/// source editing and no codec, file path, device or platform information here.
/// Caption/cursor/zoom tracks will extend this after real word alignment.
class CutPlan {
  CutPlan({
    required this.takeId,
    required this.language,
    required this.sourceDuration,
    required List<SourceRange> ranges,
  }) : ranges = List.unmodifiable(ranges) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(takeId) ||
        sourceDuration <= Duration.zero ||
        sourceDuration.inMicroseconds > _maxTimeUs ||
        ranges.isEmpty ||
        ranges.any((range) => range.end > sourceDuration) ||
        duration.inMicroseconds > _maxTimeUs) {
      throw ArgumentError('Invalid cut plan');
    }
  }
  final String takeId;
  final ScriptLanguage language;
  final Duration sourceDuration;
  final List<SourceRange> ranges;
  Duration get duration =>
      ranges.fold(Duration.zero, (sum, range) => sum + range.duration);

  Duration? sourceTime(Duration outputTime) {
    if (outputTime.isNegative) return null;
    var remaining = outputTime;
    for (final range in ranges) {
      if (remaining < range.duration) return range.start + remaining;
      remaining -= range.duration;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'takeId': takeId,
    'language': language.name,
    'sourceDurationUs': sourceDuration.inMicroseconds,
    'ranges': ranges.map((range) => range.toJson()).toList(),
  };
  factory CutPlan.fromJson(Map<String, Object?> json) {
    int integer(Object? value) {
      if (value is! int || value < 0 || value > _maxTimeUs) {
        throw const FormatException('Invalid cut time');
      }
      return value;
    }

    final language = ScriptLanguage.values
        .where((l) => l.name == json['language'])
        .firstOrNull;
    final id = json['takeId'];
    final items = json['ranges'];
    if (json.length != 5 ||
        json['version'] != 1 ||
        language == null ||
        id is! String ||
        items is! List) {
      throw const FormatException('Invalid cut plan');
    }
    try {
      return CutPlan(
        takeId: id,
        language: language,
        sourceDuration: Duration(
          microseconds: integer(json['sourceDurationUs']),
        ),
        ranges: items.map((item) {
          if (item is! Map || item.length != 2) {
            throw const FormatException('Invalid cut range');
          }
          return SourceRange(
            start: Duration(microseconds: integer(item['startUs'])),
            end: Duration(microseconds: integer(item['endUs'])),
          );
        }).toList(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid cut plan');
    }
  }
}

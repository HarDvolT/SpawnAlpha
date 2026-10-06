import '../model/cut_plan.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../transcription/script_alignment.dart';
import '../transcription/word_timing.dart';

class CutChange {
  CutChange({required this.id, required this.range, this.enabled = true}) {
    if (!RegExp(r'^quiet-[0-9]+$').hasMatch(id)) {
      throw const FormatException('Invalid cut change');
    }
  }
  final String id;
  final SourceRange range;
  final bool enabled;
  CutChange withEnabled(bool value) =>
      CutChange(id: id, range: range, enabled: value);
  Map<String, Object?> toJson() => {
    'id': id,
    'range': range.toJson(),
    'enabled': enabled,
  };
}

/// Every removal is reversible. The portable EDL never includes a media path.
class CleanPlan {
  CleanPlan({
    required this.takeId,
    required this.language,
    required this.sourceDuration,
    required List<CutChange> changes,
    this.notice,
  }) : changes = List.unmodifiable(changes) {
    if (changes.length > 10000) {
      throw const FormatException('Too many cut changes');
    }
    var previous = Duration.zero;
    final ids = <String>{};
    for (final change in changes) {
      if (!ids.add(change.id) ||
          change.range.start < previous ||
          change.range.end > sourceDuration) {
        throw const FormatException('Invalid cut changes');
      }
      previous = change.range.end;
    }
    asCutPlan(); // Also validates duration/id/language and a nonempty output.
  }
  final String takeId;
  final ScriptLanguage language;
  final Duration sourceDuration;
  final List<CutChange> changes;
  final String? notice;
  CleanPlan withEnabled(String id, bool enabled) {
    if (!changes.any((c) => c.id == id)) {
      throw const FormatException('Unknown cut change');
    }
    return CleanPlan(
      takeId: takeId,
      language: language,
      sourceDuration: sourceDuration,
      changes: [
        for (final c in changes) c.id == id ? c.withEnabled(enabled) : c,
      ],
      notice: notice,
    );
  }

  CleanPlan restoreAll() => CleanPlan(
    takeId: takeId,
    language: language,
    sourceDuration: sourceDuration,
    changes: [for (final c in changes) c.withEnabled(false)],
    notice: notice,
  );
  CutPlan asCutPlan() {
    final ranges = <SourceRange>[];
    var start = Duration.zero;
    for (final c in changes.where((c) => c.enabled)) {
      if (c.range.start > start) {
        ranges.add(SourceRange(start: start, end: c.range.start));
      }
      start = c.range.end;
    }
    if (start < sourceDuration) {
      ranges.add(SourceRange(start: start, end: sourceDuration));
    }
    return CutPlan(
      takeId: takeId,
      language: language,
      sourceDuration: sourceDuration,
      ranges: ranges,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'takeId': takeId,
    'language': language.name,
    'sourceDurationUs': sourceDuration.inMicroseconds,
    'changes': changes.map((c) => c.toJson()).toList(),
    'notice': ?notice,
  };
  factory CleanPlan.fromJson(Map<String, Object?> value) {
    final items = value['changes'],
        language = ScriptLanguage.values
            .where((l) => l.name == value['language'])
            .firstOrNull;
    if (value['version'] != 1 ||
        value['takeId'] is! String ||
        value['sourceDurationUs'] is! int ||
        language == null ||
        items is! List ||
        items.length > 10000 ||
        (value['notice'] != null && value['notice'] is! String)) {
      throw const FormatException('Invalid clean plan');
    }
    try {
      return CleanPlan(
        takeId: value['takeId']! as String,
        language: language,
        sourceDuration: Duration(
          microseconds: value['sourceDurationUs']! as int,
        ),
        notice: value['notice'] as String?,
        changes: [
          for (final item in items)
            if (item is Map &&
                item['id'] is String &&
                item['enabled'] is bool &&
                item['range'] is Map &&
                (item['range'] as Map)['startUs'] is int &&
                (item['range'] as Map)['endUs'] is int)
              CutChange(
                id: item['id'] as String,
                enabled: item['enabled'] as bool,
                range: SourceRange(
                  start: Duration(
                    microseconds: (item['range'] as Map)['startUs'] as int,
                  ),
                  end: Duration(
                    microseconds: (item['range'] as Map)['endUs'] as int,
                  ),
                ),
              )
            else
              throw const FormatException('Invalid cut change'),
        ],
      );
    } on ArgumentError {
      throw const FormatException('Invalid clean plan');
    }
  }
}

/// Measured quiet audio only. Word estimates never serve as silence evidence.
/// Protect words, low-confidence neighbourhoods, marked gaps and breaths.
CleanPlan planQuietCut({
  required String takeId,
  required WordTranscript transcript,
  required List<SourceRange> quiet,
  ScriptDocument? snapshot,
  ScriptAlignment? alignment,
  bool screenContext = false,
}) {
  CleanPlan original(String notice) => CleanPlan(
    takeId: takeId,
    language: transcript.language,
    sourceDuration: transcript.duration,
    changes: [],
    notice: notice,
  );
  if (screenContext) {
    return original(
      'Screen context is kept. Automatic tightening needs activity review.',
    );
  }
  if (transcript.words.isEmpty) {
    return original('No speech found. The original is kept.');
  }
  if (snapshot == null || (!snapshot.usesNotes && alignment == null)) {
    return original('No usable frozen script alignment. The original is kept.');
  }
  if (snapshot.language != transcript.language) {
    throw const FormatException('Cut language mismatch');
  }
  final protected = <SourceRange>[];
  void protect(Duration start, Duration end) {
    start = start < Duration.zero ? Duration.zero : start;
    end = end > transcript.duration ? transcript.duration : end;
    if (end > start) protected.add(SourceRange(start: start, end: end));
  }

  for (final word in transcript.words) {
    final padding = word.confidence == null || word.confidence! < .6
        ? const Duration(seconds: 1)
        : const Duration(milliseconds: 100);
    protect(word.start - padding, word.end + padding);
  }
  if (alignment != null && !snapshot.usesNotes) {
    final after = <int>{};
    for (final mark in snapshot.marks.where(
      (m) => m.accepted && m.kind.isGap,
    )) {
      final token = snapshot.tokens
          .where((t) => t.isWord && t.index <= mark.end)
          .lastOrNull;
      if (token != null) after.add(token.index);
    }
    for (var i = 0; i < alignment.words.length; i++) {
      final word = alignment.words[i];
      if (!after.contains(word.tokenIndex)) continue;
      var end = transcript.duration;
      for (var next = i + 1; next < alignment.words.length; next++) {
        final following = alignment.words[next];
        if (following.attempt != word.attempt ||
            (following.tokenIndex != null &&
                following.tokenIndex! > word.tokenIndex!)) {
          end = transcript.words[following.spokenIndex].start;
          break;
        }
      }
      protect(transcript.words[word.spokenIndex].end, end);
    }
  }
  protected.sort((a, b) => a.start.compareTo(b.start));
  final merged = <SourceRange>[];
  for (final range in protected) {
    if (merged.isNotEmpty && range.start <= merged.last.end) {
      final previous = merged.removeLast();
      merged.add(
        SourceRange(
          start: previous.start,
          end: range.end > previous.end ? range.end : previous.end,
        ),
      );
    } else {
      merged.add(range);
    }
  }
  var previous = Duration.zero, protection = 0;
  final changes = <CutChange>[];
  void removeQuiet(Duration start, Duration end) {
    if (end - start <= const Duration(milliseconds: 700)) return;
    changes.add(
      CutChange(
        id: 'quiet-${changes.length}',
        range: SourceRange(
          start: start + const Duration(milliseconds: 125),
          end: end - const Duration(milliseconds: 125),
        ),
      ),
    );
  }

  for (final range in quiet) {
    if (range.start < previous || range.end > transcript.duration) {
      throw const FormatException('Invalid quiet evidence');
    }
    previous = range.end;
    var start = range.start;
    while (protection < merged.length && merged[protection].end <= start) {
      protection++;
    }
    for (
      var i = protection;
      i < merged.length && merged[i].start < range.end;
      i++
    ) {
      if (merged[i].start > start) removeQuiet(start, merged[i].start);
      if (merged[i].end > start) start = merged[i].end;
      if (start >= range.end) break;
    }
    if (start < range.end) removeQuiet(start, range.end);
    if (changes.length > 10000) {
      return original(
        'This long take needs review in smaller sections. The original is kept.',
      );
    }
  }
  return CleanPlan(
    takeId: takeId,
    language: transcript.language,
    sourceDuration: transcript.duration,
    changes: changes,
    notice: quiet.isEmpty
        ? 'No measured quiet gaps. The original is kept.'
        : null,
  );
}

/// Every spoken word must fit wholly in one kept interval. Never trim a word
/// to fit a plan or substitute script spelling when moving caption times.
WordTranscript speechOnCut(WordTranscript source, CutPlan plan) {
  if (source.duration != plan.sourceDuration ||
      source.language != plan.language) {
    throw const FormatException('Cut transcript mismatch');
  }
  final words = <SpokenWord>[];
  var rangeIndex = 0, output = Duration.zero;
  for (final word in source.words) {
    while (rangeIndex < plan.ranges.length &&
        plan.ranges[rangeIndex].end <= word.start) {
      output += plan.ranges[rangeIndex++].duration;
    }
    if (rangeIndex >= plan.ranges.length ||
        word.start < plan.ranges[rangeIndex].start ||
        word.end > plan.ranges[rangeIndex].end) {
      throw const FormatException('A cut would remove spoken words');
    }
    final range = plan.ranges[rangeIndex];
    words.add(
      SpokenWord(
        text: word.text,
        start: output + word.start - range.start,
        end: output + word.end - range.start,
        confidence: word.confidence,
        recognizedText: word.recognizedText,
      ),
    );
  }
  return WordTranscript(
    language: source.language,
    duration: plan.duration,
    words: words,
  );
}

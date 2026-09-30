import 'dart:math';

/// Where a mark sits relative to the words.
enum MarkPlacement {
  /// Between two words, after the word at `Mark.end`.
  gap,

  /// Over a run of words, from `Mark.start` to `Mark.end` inclusive.
  span,
}

/// The delivery cues the markup can add to a script.
enum MarkKind {
  pauseShort('pause_short', 'Short pause', MarkPlacement.gap),
  pauseLong('pause_long', 'Long pause', MarkPlacement.gap),
  breath('breath', 'Breathe', MarkPlacement.gap),
  stress('stress', 'Stress', MarkPlacement.span),
  slower('slower', 'Slow down', MarkPlacement.span),
  faster('faster', 'Speed up', MarkPlacement.span),
  energy('energy', 'Lift energy', MarkPlacement.span);

  const MarkKind(this.id, this.label, this.placement);

  /// The stable name used in JSON and in the cloud markup schema.
  final String id;
  final String label;
  final MarkPlacement placement;

  bool get isGap => placement == MarkPlacement.gap;
  bool get isPace => this == slower || this == faster;

  /// Spans of the same family may not overlap: a word can't be both
  /// slower and faster.
  String get family => isPace ? 'pace' : id;

  /// Kinds a mark of this kind can be switched to in the editor without
  /// changing where it sits.
  List<MarkKind> get alternatives => switch (this) {
        pauseShort || pauseLong || breath => const [pauseShort, pauseLong, breath],
        slower || faster => const [slower, faster],
        stress => const [stress, energy],
        energy => const [energy, stress],
      };

  /// When two gap marks land between the same words, the stronger wins.
  int get gapStrength => switch (this) {
        pauseLong => 3,
        pauseShort => 2,
        breath => 1,
        _ => 0,
      };

  static MarkKind? fromId(String? id) {
    for (final k in MarkKind.values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// Who created a mark.
enum MarkOrigin {
  /// The on-device rule-based markup.
  local,

  /// A cloud model.
  cloud,

  /// The user, in the editor.
  user;

  static MarkOrigin fromName(String? name) =>
      MarkOrigin.values.firstWhere((o) => o.name == name, orElse: () => MarkOrigin.user);
}

/// One delivery cue, anchored to token indices rather than to the text, so
/// the prompter can render it and the review can check it.
class Mark {
  const Mark({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    this.origin = MarkOrigin.user,
    this.accepted = true,
    this.note,
  }) : assert(start <= end);

  /// A gap mark after token [after].
  const Mark.gap({
    required this.id,
    required this.kind,
    required int after,
    this.origin = MarkOrigin.user,
    this.accepted = true,
    this.note,
  })  : start = after,
        end = after;

  final String id;
  final MarkKind kind;

  /// First and last token covered. Gap marks have start == end and sit
  /// after that token.
  final int start;
  final int end;

  final MarkOrigin origin;

  /// Marks proposed by the markup start unaccepted; the user reviews them.
  final bool accepted;

  /// A short reason for the mark, shown in the editor.
  final String? note;

  bool covers(int token) => token >= start && token <= end;

  Mark copyWith({MarkKind? kind, int? start, int? end, bool? accepted, String? note}) => Mark(
        id: id,
        kind: kind ?? this.kind,
        start: start ?? this.start,
        end: end ?? this.end,
        origin: origin,
        accepted: accepted ?? this.accepted,
        note: note ?? this.note,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.id,
        'start': start,
        'end': end,
        'origin': origin.name,
        'accepted': accepted,
        if (note != null) 'note': note,
      };

  /// Returns null when the JSON does not describe a valid mark.
  static Mark? fromJson(Map<String, Object?> json) {
    final kind = MarkKind.fromId(json['kind'] as String?);
    final start = json['start'];
    final end = json['end'];
    if (kind == null || start is! int || end is! int || start < 0 || end < start) return null;
    return Mark(
      id: json['id'] as String? ?? newId(),
      kind: kind,
      start: start,
      end: kind.isGap ? start : end,
      origin: MarkOrigin.fromName(json['origin'] as String?),
      accepted: json['accepted'] as bool? ?? true,
      note: json['note'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Mark &&
      other.id == id &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.origin == origin &&
      other.accepted == accepted &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, kind, start, end, origin, accepted, note);

  @override
  String toString() => 'Mark(${kind.id} $start..$end${accepted ? '' : ' pending'})';
}

final _random = Random();

/// A short random id for marks, suggestions and scripts.
String newId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes(
    List.generate(12, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
  );
}

/// Cleans a list of marks for [tokenCount] tokens and sorts it.
///
/// - Drops marks out of range, and gap marks after the last word.
/// - Keeps one gap mark between two words: an accepted one over a pending
///   one, then the stronger (long pause, short pause, breath).
/// - Stops spans of the same family (stress, energy, pace) from
///   overlapping. Accepted spans claim their words first, then the rest in
///   list order; a span that collides is cut down to the longest run of
///   free words, or dropped.
List<Mark> normalizeMarks(List<Mark> marks, int tokenCount) {
  final ordered = [...marks.where((m) => m.accepted), ...marks.where((m) => !m.accepted)];
  final gaps = <int, Mark>{};
  final occupied = <String, List<bool>>{};
  final spans = <Mark>[];
  for (final m in ordered) {
    if (m.start < 0 || m.end >= tokenCount || m.start > m.end) continue;
    if (m.kind.isGap) {
      if (m.end >= tokenCount - 1) continue;
      final existing = gaps[m.end];
      if (existing == null ||
          (existing.accepted == m.accepted && m.kind.gapStrength > existing.kind.gapStrength)) {
        gaps[m.end] = m;
      }
      continue;
    }

    final taken = occupied.putIfAbsent(m.kind.family, () => List.filled(tokenCount, false));
    var bestStart = -1;
    var bestLength = 0;
    var runStart = -1;
    for (var i = m.start; i <= m.end + 1; i++) {
      final free = i <= m.end && !taken[i];
      if (free) {
        if (runStart < 0) runStart = i;
      } else if (runStart >= 0) {
        if (i - runStart > bestLength) {
          bestLength = i - runStart;
          bestStart = runStart;
        }
        runStart = -1;
      }
    }
    if (bestLength == 0) continue;
    final fitted = bestStart == m.start && bestLength == m.end - m.start + 1
        ? m
        : m.copyWith(start: bestStart, end: bestStart + bestLength - 1);
    for (var i = fitted.start; i <= fitted.end; i++) {
      taken[i] = true;
    }
    spans.add(fitted);
  }

  return [...gaps.values, ...spans]..sort((a, b) => a.start != b.start
      ? a.start.compareTo(b.start)
      : a.kind.index.compareTo(b.kind.index));
}

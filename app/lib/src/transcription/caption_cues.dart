import '../model/cut_plan.dart';
import '../model/mark.dart';
import '../model/script_document.dart';
import 'script_alignment.dart';
import 'word_timing.dart';

enum CaptionPace { normal, slower, faster }

class CaptionCue {
  const CaptionCue({
    this.stress = false,
    this.energy = false,
    this.pace = CaptionPace.normal,
    this.breakAfter = false,
  });
  final bool stress, energy, breakAfter;
  final CaptionPace pace;
}

/// Retain original word identity through a cut, including reordered attempts.
/// Never re-align shortened speech and attach a discarded attempt's cues.
List<CaptionCue> captionCuesOnCut({
  required WordTranscript source,
  required WordTranscript kept,
  required CutPlan plan,
  ScriptDocument? snapshot,
  bool aligned = false,
}) {
  if (source.duration != plan.sourceDuration ||
      kept.duration != plan.duration ||
      source.language != kept.language ||
      source.language != plan.language) {
    throw const FormatException('Caption source mismatch');
  }
  final cues = List<CaptionCue>.filled(source.words.length, const CaptionCue());
  if (aligned &&
      snapshot != null &&
      !snapshot.usesNotes &&
      snapshot.marks.isNotEmpty) {
    final alignment = alignTranscript(snapshot, source);
    final tokens = List<CaptionCue>.filled(
      snapshot.tokens.length,
      const CaptionCue(),
    );
    for (final mark in snapshot.marks.where((m) => m.accepted)) {
      if (mark.end >= tokens.length || mark.start < 0) {
        throw const FormatException('Invalid caption cue');
      }
      if (mark.kind.isGap) {
        var owner = mark.end;
        while (owner >= 0 && !snapshot.tokens[owner].isWord) {
          owner--;
        }
        if (owner < 0) continue;
        final old = tokens[owner];
        tokens[owner] = CaptionCue(
          stress: old.stress,
          energy: old.energy,
          pace: old.pace,
          breakAfter: true,
        );
      } else {
        for (var i = mark.start; i <= mark.end; i++) {
          final old = tokens[i];
          tokens[i] = CaptionCue(
            stress: old.stress || mark.kind == MarkKind.stress,
            energy: old.energy || mark.kind == MarkKind.energy,
            pace: mark.kind == MarkKind.slower
                ? CaptionPace.slower
                : mark.kind == MarkKind.faster
                ? CaptionPace.faster
                : old.pace,
            breakAfter: old.breakAfter,
          );
        }
      }
    }
    for (final word in alignment.words) {
      if (word.tokenIndex == null) continue;
      final cue = tokens[word.tokenIndex!],
          spoken = source.words[word.spokenIndex];
      final reliable =
          word.match == WordMatch.exact &&
          (spoken.corrected || (spoken.confidence ?? 0) >= .6);
      cues[word.spokenIndex] = CaptionCue(
        stress: reliable && cue.stress,
        energy: reliable && cue.energy,
        pace: reliable ? cue.pace : CaptionPace.normal,
        breakAfter: cue.breakAfter,
      );
    }
  }
  final result = <CaptionCue>[];
  var output = Duration.zero;
  for (final range in plan.ranges) {
    var lo = 0, hi = source.words.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (source.words[mid].end <= range.start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (
      var i = lo;
      i < source.words.length && source.words[i].start < range.end;
      i++
    ) {
      final word = source.words[i];
      if (word.start < range.start ||
          word.end > range.end ||
          result.length >= kept.words.length) {
        throw const FormatException('Caption cut splits a word');
      }
      final timed = kept.words[result.length];
      if (timed.text != word.text ||
          timed.start != output + word.start - range.start ||
          timed.end != output + word.end - range.start) {
        throw const FormatException('Caption word identity changed');
      }
      result.add(cues[i]);
    }
    output += range.duration;
  }
  if (result.length != kept.words.length) {
    throw const FormatException('Incomplete caption words');
  }
  return List.unmodifiable(result);
}

/// Decorative Arabic elongation; ASR spelling/subtitle text stay untouched.
String captionKashida(String text) {
  const dual = 'بتثجحخسشصضطظعغفقكلمنهيئ';
  for (var i = 0; i < text.length - 1; i++) {
    if (!dual.contains(text[i])) continue;
    var next = i + 1;
    while (next < text.length &&
        ((text.codeUnitAt(next) >= 0x064b && text.codeUnitAt(next) <= 0x065f) ||
            text.codeUnitAt(next) == 0x0670)) {
      next++;
    }
    if (next < text.length &&
        RegExp(r'[\u0622-\u063a\u0641-\u064a]').hasMatch(text[next])) {
      return '${text.substring(0, next)}\u0640\u0640\u0640${text.substring(next)}';
    }
  }
  return text;
}

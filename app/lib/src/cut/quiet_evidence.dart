import '../model/cut_plan.dart';
import '../transcription/word_timing.dart';

Duration wordSafetyMargin(SpokenWord word) =>
    word.confidence == null || word.confidence! < .6
    ? const Duration(seconds: 1)
    : const Duration(milliseconds: 100);

/// A midpoint within at least 80ms of measured quiet, clipped by word guards.
Duration? quietBoundary(
  List<SourceRange> quiet,
  Duration lower,
  Duration upper, {
  required bool latest,
}) {
  if (upper <= lower) return null;
  var lo = 0, hi = quiet.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (quiet[mid].end <= lower) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  Duration? boundary;
  for (var i = lo; i < quiet.length && quiet[i].start < upper; i++) {
    final start = quiet[i].start > lower ? quiet[i].start : lower;
    final end = quiet[i].end < upper ? quiet[i].end : upper;
    if (end - start < const Duration(milliseconds: 80)) continue;
    boundary =
        start + Duration(microseconds: (end - start).inMicroseconds ~/ 2);
    if (!latest) break;
  }
  return boundary;
}

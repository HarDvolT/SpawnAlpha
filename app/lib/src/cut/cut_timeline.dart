import '../model/cut_plan.dart';
import 'clean_plan.dart';

class CutTimelineSpan {
  const CutTimelineSpan(this.range, {required this.removed});
  final SourceRange range;
  final bool removed;
}

/// Source-clock coverage, including overlapping quiet/filler/retake removals.
/// The timeline never invents new cut boundaries or changes the EDL.
List<CutTimelineSpan> cutTimeline(CleanPlan plan) {
  final result = <CutTimelineSpan>[];
  var start = Duration.zero;
  for (final kept in plan.asCutPlan().ranges) {
    if (start < kept.start) {
      result.add(
        CutTimelineSpan(
          SourceRange(start: start, end: kept.start),
          removed: true,
        ),
      );
    }
    result.add(CutTimelineSpan(kept, removed: false));
    start = kept.end;
  }
  if (start < plan.sourceDuration) {
    result.add(
      CutTimelineSpan(
        SourceRange(start: start, end: plan.sourceDuration),
        removed: true,
      ),
    );
  }
  return List.unmodifiable(result);
}

CutTimelineSpan timelineAt(List<CutTimelineSpan> spans, Duration time) {
  if (spans.isEmpty || time.isNegative || time > spans.last.range.end) {
    throw ArgumentError('Time outside source timeline');
  }
  var lower = 0, upper = spans.length;
  while (lower < upper) {
    final middle = (lower + upper) ~/ 2;
    if (spans[middle].range.end <= time) {
      lower = middle + 1;
    } else {
      upper = middle;
    }
  }
  return spans[lower == spans.length ? lower - 1 : lower];
}

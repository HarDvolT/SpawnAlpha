import '../model/cut_plan.dart';
import '../recording/activity_trace.dart';

const maxCursorSteps = 100000;
const cursorObservationGap = Duration(milliseconds: 250);
const _maximumClock = Duration(hours: 24);

enum CursorShape { arrow, text, hand, hidden }

/// An observed pointer state, held only until the next observation or cut.
/// Hidden states deliberately carry no private coordinates.
class CursorStep {
  CursorStep({
    required this.start,
    required this.end,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.shape,
    this.snap = false,
    this.reset = false,
  }) {
    if (start.isNegative ||
        end <= start ||
        end > _maximumClock ||
        end - start > cursorObservationGap ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x >= 1 ||
        y < 0 ||
        y >= 1 ||
        width < 1 ||
        width > 100000 ||
        height < 1 ||
        height > 100000 ||
        shape == CursorShape.hidden && (x != 0 || y != 0 || snap)) {
      throw const FormatException('Invalid cursor step');
    }
  }
  final Duration start, end;
  final double x, y;
  final int width, height;
  final CursorShape shape;
  final bool snap, reset;
  Map<String, Object?> toJson() => {
    'startUs': start.inMicroseconds,
    'endUs': end.inMicroseconds,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'shape': shape.name,
    'snap': snap,
    'reset': reset,
  };
  factory CursorStep.fromJson(Map<String, Object?> json) {
    final shape = CursorShape.values
        .where((s) => s.name == json['shape'])
        .firstOrNull;
    if (json.length != 9 ||
        shape == null ||
        json['startUs'] is! int ||
        json['endUs'] is! int ||
        json['x'] is! num ||
        json['y'] is! num ||
        json['width'] is! int ||
        json['height'] is! int ||
        json['snap'] is! bool ||
        json['reset'] is! bool) {
      throw const FormatException('Invalid cursor step');
    }
    return CursorStep(
      start: Duration(microseconds: json['startUs']! as int),
      end: Duration(microseconds: json['endUs']! as int),
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      width: json['width']! as int,
      height: json['height']! as int,
      shape: shape,
      snap: json['snap']! as bool,
      reset: json['reset']! as bool,
    );
  }
}

class ScreenCursor {
  ScreenCursor(this.duration, List<CursorStep> steps)
    : steps = List.unmodifiable(steps) {
    if (duration <= Duration.zero ||
        duration > _maximumClock ||
        steps.isEmpty ||
        steps.length > maxCursorSteps ||
        steps.isNotEmpty && !steps.first.reset) {
      throw const FormatException('Invalid cursor track');
    }
    var end = Duration.zero;
    for (final step in steps) {
      if (step.start < end || step.end > duration) {
        throw const FormatException('Invalid cursor track clock');
      }
      end = step.end;
    }
  }
  final Duration duration;
  final List<CursorStep> steps;

  void validateClock(CutPlan plan) {
    if (duration != plan.duration || plan.ranges.length > 20001) {
      throw const FormatException('Invalid cursor cut');
    }
    var index = 0, clock = Duration.zero;
    for (final range in _continuousRanges(plan)) {
      final end = clock + range.duration;
      var first = true;
      var previousEnd = clock;
      while (index < steps.length && steps[index].start < end) {
        final step = steps[index++];
        if (step.start < clock ||
            step.end > end ||
            step.reset != first ||
            step.start - previousEnd > cursorObservationGap) {
          throw const FormatException('Cursor crosses a source cut');
        }
        first = false;
        previousEnd = step.end;
      }
      if (first || end - previousEnd > cursorObservationGap) {
        throw const FormatException('Incomplete retained cursor clock');
      }
      clock = end;
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'durationUs': duration.inMicroseconds,
    'steps': steps.map((s) => s.toJson()).toList(),
  };
  factory ScreenCursor.fromJson(Map<String, Object?> json) {
    if (json.length != 3 ||
        json['version'] != 1 ||
        json['durationUs'] is! int ||
        json['steps'] is! List ||
        (json['steps']! as List).length > maxCursorSteps) {
      throw const FormatException('Invalid cursor track');
    }
    return ScreenCursor(
      Duration(microseconds: json['durationUs']! as int),
      (json['steps']! as List)
          .map((s) => CursorStep.fromJson(Map<String, Object?>.from(s as Map)))
          .toList(),
    );
  }
}

List<SourceRange> _continuousRanges(CutPlan plan) {
  final ranges = <SourceRange>[];
  for (final range in plan.ranges) {
    if (ranges.isNotEmpty && ranges.last.end == range.start) {
      final old = ranges.removeLast();
      ranges.add(SourceRange(start: old.start, end: range.end));
    } else {
      ranges.add(range);
    }
  }
  return ranges;
}

class _Observation {
  const _Observation(this.event, this.shape, this.snap, this.shapeTimeUs);
  final ActivityEvent event;
  final CursorShape shape;
  final bool snap;
  final int shapeTimeUs;
}

/// Bounded source evidence, without key timing, focus rectangles or labels.
/// Clicks anchor an already observed shape; unknown shapes are never guessed.
class ScreenCursorPlanner {
  final _observations = <_Observation>[];
  int _previous = -1;
  ActivityEvent? _lastCursor;
  bool _finished = false;
  void add(ActivityEvent event) {
    if (_finished || event.timeUs < _previous) {
      throw const FormatException('Unordered cursor activity');
    }
    _previous = event.timeUs;
    if (event.type != 'cursor' && event.type != 'click') return;
    CursorShape shape;
    final snap = event.type == 'click';
    if (snap) {
      if (!event.visible) return;
      final old = _lastCursor;
      if (old == null ||
          !old.visible ||
          old.width != event.width ||
          old.height != event.height ||
          event.timeUs - old.timeUs > cursorObservationGap.inMicroseconds) {
        return; // A click has no shape; wait for a retained cursor observation.
      }
      shape = CursorShape.values.where((s) => s.name == old.detail).first;
    } else {
      if (_lastCursor != null &&
          event.timeUs - _lastCursor!.timeUs >
              cursorObservationGap.inMicroseconds) {
        throw const FormatException('Cursor activity gap');
      }
      _lastCursor = event;
      final known = CursorShape.values
          .where((s) => s.name == event.detail)
          .firstOrNull;
      if (event.visible && known == null) {
        throw const FormatException('Unsupported cursor shape');
      }
      shape = event.visible ? known! : CursorShape.hidden;
    }
    // Equal-time sampling cannot erase a known click anchor. Hidden and resized
    // observations still win and cannot retain a stale visible coordinate.
    var observed = event,
        shapeTimeUs = snap ? _lastCursor!.timeUs : event.timeUs;
    var anchor = snap;
    if (_observations.isNotEmpty &&
        _observations.last.event.timeUs == event.timeUs) {
      final old = _observations.removeLast();
      anchor =
          event.visible &&
          old.event.width == event.width &&
          old.event.height == event.height &&
          (old.snap || snap);
      if (anchor && old.snap && !snap) {
        observed = old.event;
        shapeTimeUs = event.timeUs;
      }
    }
    if (_observations.length >= maxCursorSteps) {
      throw const FormatException('Too many cursor observations');
    }
    _observations.add(_Observation(observed, shape, anchor, shapeTimeUs));
  }

  ScreenCursor finish(CutPlan plan) {
    if (_finished) throw const FormatException('Cursor activity already used');
    _finished = true;
    if (plan.sourceDuration > _maximumClock ||
        plan.duration > _maximumClock ||
        plan.ranges.length > 20001 ||
        _lastCursor == null ||
        _observations.first.event.timeUs >
            cursorObservationGap.inMicroseconds ||
        plan.sourceDuration.inMicroseconds - _lastCursor!.timeUs < 0 ||
        plan.sourceDuration.inMicroseconds - _lastCursor!.timeUs >
            cursorObservationGap.inMicroseconds) {
      throw const FormatException('Incomplete cursor activity');
    }
    final output = <CursorStep>[];
    var clock = Duration.zero;
    for (final range in _continuousRanges(plan)) {
      var low = 0, high = _observations.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (_observations[mid].event.timeUs < range.start.inMicroseconds) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      var first = true;
      for (var i = low; i < _observations.length; ++i) {
        final observation = _observations[i], event = observation.event;
        final time = Duration(microseconds: event.timeUs);
        if (time >= range.end) break;
        if (observation.shapeTimeUs < range.start.inMicroseconds) continue;
        final next = i + 1 < _observations.length
            ? Duration(microseconds: _observations[i + 1].event.timeUs)
            : plan.sourceDuration;
        final end = next < range.end ? next : range.end;
        output.add(
          CursorStep(
            start: clock + time - range.start,
            end: clock + end - range.start,
            x: event.visible ? event.x / event.width : 0,
            y: event.visible ? event.y / event.height : 0,
            width: event.width,
            height: event.height,
            shape: observation.shape,
            snap: observation.snap,
            reset: first,
          ),
        );
        first = false;
        if (output.length > maxCursorSteps) {
          throw const FormatException('Too many retained cursor observations');
        }
      }
      if (first) throw const FormatException('No retained cursor observation');
      clock += range.duration;
    }
    return ScreenCursor(plan.duration, output)..validateClock(plan);
  }
}

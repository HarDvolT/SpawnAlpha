import 'dart:math' as math;

import '../model/cut_plan.dart';
import '../recording/activity_trace.dart';

/// Text-free pointer protection, expressed on the retained video clock.
class CameraTarget {
  CameraTarget({
    required this.start,
    required this.end,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    if (start.isNegative ||
        end <= start ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        width < 1 ||
        width > 100000 ||
        height < 1 ||
        height > 100000) {
      throw const FormatException('Invalid camera target');
    }
  }
  final Duration start, end;
  final double x, y;
  final int width, height;
  Map<String, Object?> toJson() => {
    'startUs': start.inMicroseconds,
    'endUs': end.inMicroseconds,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
  factory CameraTarget.fromJson(Map<String, Object?> json) {
    if (json.length != 6 ||
        json['startUs'] is! int ||
        json['endUs'] is! int ||
        json['x'] is! num ||
        json['y'] is! num ||
        json['width'] is! int ||
        json['height'] is! int) {
      throw const FormatException('Invalid camera target');
    }
    return CameraTarget(
      start: Duration(microseconds: json['startUs']! as int),
      end: Duration(microseconds: json['endUs']! as int),
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      width: json['width']! as int,
      height: json['height']! as int,
    );
  }
}

class CameraTargets {
  CameraTargets(List<CameraTarget> targets)
    : targets = List.unmodifiable(targets) {
    if (targets.length > 20000) {
      throw const FormatException('Too many camera targets');
    }
    var end = Duration.zero;
    for (final target in targets) {
      if (target.start < end) {
        throw const FormatException('Overlapping camera targets');
      }
      end = target.end;
    }
  }
  final List<CameraTarget> targets;
  void validateClock(CutPlan plan) {
    if (targets.any((t) => t.end > plan.duration)) {
      throw const FormatException('Invalid camera target clock');
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'targets': targets.map((t) => t.toJson()).toList(),
  };
  factory CameraTargets.fromJson(Map<String, Object?> json) {
    if (json.length != 2 ||
        json['version'] != 1 ||
        json['targets'] is! List ||
        (json['targets']! as List).length > 20000) {
      throw const FormatException('Invalid camera targets');
    }
    return CameraTargets(
      (json['targets']! as List)
          .map(
            (t) => CameraTarget.fromJson(Map<String, Object?>.from(t as Map)),
          )
          .toList(),
    );
  }
}

class CameraTargetPlanner {
  CameraTargetPlanner(this.hold, this.distance) {
    if (hold <= Duration.zero ||
        hold > const Duration(seconds: 2) ||
        !distance.isFinite ||
        distance <= 0 ||
        distance > .1) {
      throw const FormatException('Invalid camera target policy');
    }
  }
  final Duration hold;
  final double distance;
  final _targets = <CameraTarget>[];
  int _previous = -1;
  bool _finished = false;
  void add(ActivityEvent event) {
    if (_finished || event.timeUs < _previous) {
      throw const FormatException('Unordered camera activity');
    }
    _previous = event.timeUs;
    if (event.type != 'cursor' && event.type != 'click') return;
    final time = Duration(microseconds: event.timeUs);
    final old = _targets.isEmpty ? null : _targets.last;
    if (old != null && old.end > time) {
      _targets.removeLast();
      if (event.visible &&
          old.width == event.width &&
          old.height == event.height &&
          math.max(
                (old.x - event.x / event.width).abs(),
                (old.y - event.y / event.height).abs(),
              ) <=
              distance) {
        _targets.add(
          CameraTarget(
            start: old.start,
            end: time + hold,
            x: old.x,
            y: old.y,
            width: old.width,
            height: old.height,
          ),
        );
        return;
      }
      if (time > old.start) {
        _targets.add(
          CameraTarget(
            start: old.start,
            end: time,
            x: old.x,
            y: old.y,
            width: old.width,
            height: old.height,
          ),
        );
      }
    }
    if (!event.visible) return;
    if (_targets.length >= 20000) {
      throw const FormatException('Too many camera targets');
    }
    _targets.add(
      CameraTarget(
        start: time,
        end: time + hold,
        x: event.x / event.width,
        y: event.y / event.height,
        width: event.width,
        height: event.height,
      ),
    );
  }

  CameraTargets finish(CutPlan plan) {
    if (_finished) throw const FormatException('Camera activity already used');
    _finished = true;
    final ranges = <SourceRange>[], output = <CameraTarget>[];
    for (final range in plan.ranges) {
      if (ranges.isNotEmpty && ranges.last.end == range.start) {
        final old = ranges.removeLast();
        ranges.add(SourceRange(start: old.start, end: range.end));
      } else {
        ranges.add(range);
      }
    }
    var clock = Duration.zero;
    for (final range in ranges) {
      var low = 0, high = _targets.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (_targets[mid].end <= range.start) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      for (
        var i = low;
        i < _targets.length && _targets[i].start < range.end;
        ++i
      ) {
        final t = _targets[i];
        output.add(
          CameraTarget(
            start:
                clock +
                (t.start > range.start ? t.start : range.start) -
                range.start,
            end: clock + (t.end < range.end ? t.end : range.end) - range.start,
            x: t.x,
            y: t.y,
            width: t.width,
            height: t.height,
          ),
        );
        if (output.length > 20000) {
          throw const FormatException('Too many retained camera targets');
        }
      }
      clock += range.duration;
    }
    return CameraTargets(output);
  }
}

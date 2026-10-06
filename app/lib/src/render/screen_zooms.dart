import 'dart:math' as math;

import '../model/cut_plan.dart';
import '../recording/activity_trace.dart';

class ZoomPolicy {
  const ZoomPolicy({
    required this.window,
    required this.distance,
    required this.lead,
    required this.hold,
    required this.factor,
    required this.maximum,
    required this.typingMinimum,
    required this.smallTarget,
    this.pointWindow = Duration.zero,
  });
  final Duration window, lead, hold, pointWindow;
  final double distance, factor, maximum, smallTarget;
  final int typingMinimum;
}

/// A target on the output clock, retaining source dimensions through resize.
class ZoomStep {
  ZoomStep({
    required this.time,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.factor,
  }) {
    if (time.isNegative ||
        !x.isFinite ||
        !y.isFinite ||
        !factor.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        width < 1 ||
        width > 100000 ||
        height < 1 ||
        height > 100000 ||
        factor < 1 ||
        factor > 3) {
      throw const FormatException('Invalid screen zoom');
    }
  }
  final Duration time;
  final double x, y, factor;
  final int width, height;
  Map<String, Object?> toJson() => {
    'timeUs': time.inMicroseconds,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'factor': factor,
  };
  factory ZoomStep.fromJson(Map<String, Object?> json) {
    if (json.length != 6 ||
        json['timeUs'] is! int ||
        json['x'] is! num ||
        json['y'] is! num ||
        json['factor'] is! num ||
        json['width'] is! int ||
        json['height'] is! int) {
      throw const FormatException('Invalid screen zoom');
    }
    return ZoomStep(
      time: Duration(microseconds: json['timeUs']! as int),
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      width: json['width']! as int,
      height: json['height']! as int,
      factor: (json['factor']! as num).toDouble(),
    );
  }
}

class ScreenZooms {
  ScreenZooms(this.count, List<ZoomStep> steps)
    : steps = List.unmodifiable(steps) {
    if (count < 0 ||
        count > 10000 ||
        steps.length > 20000 ||
        (count == 0) != steps.isEmpty ||
        steps.where((s) => s.factor > 1).length != count ||
        (steps.isNotEmpty && steps.last.factor != 1)) {
      throw const FormatException('Too many screen zooms');
    }
    var previous = Duration.zero;
    for (final step in steps) {
      if (step.time < previous) {
        throw const FormatException('Unordered screen zooms');
      }
      previous = step.time;
    }
  }
  final int count;
  final List<ZoomStep> steps;
  Map<String, Object?> toJson() => {
    'version': 1,
    'count': count,
    'steps': steps.map((s) => s.toJson()).toList(),
  };
  factory ScreenZooms.fromJson(Map<String, Object?> json) {
    if (json.length != 3 ||
        json['version'] != 1 ||
        json['count'] is! int ||
        json['steps'] is! List) {
      throw const FormatException('Invalid screen zooms');
    }
    final list = json['steps']! as List;
    if (list.length > 20000) {
      throw const FormatException('Too many screen zooms');
    }
    return ScreenZooms(
      json['count']! as int,
      list
          .map((s) => ZoomStep.fromJson(Map<String, Object?>.from(s as Map)))
          .toList(),
    );
  }
}

class _Target {
  const _Target(
    this.timeUs,
    this.x,
    this.y,
    this.width,
    this.height,
    this.small, {
    int? startUs,
    this.evidence = 1,
    this.pointing,
  }) : startUs = startUs ?? timeUs;
  final int timeUs, startUs, width, height, evidence;
  final SourceRange? pointing;
  final double x, y;
  final bool small;
}

/// Streaming evidence collector. Cursor paths and anonymous key events are not
/// retained; only bounded spatial click/shortcut/typing-burst targets survive.
class ScreenZoomPlanner {
  ScreenZoomPlanner(this.policy, {List<SourceRange> pointing = const []})
    : _pointing = List.unmodifiable(pointing) {
    if (policy.window <= Duration.zero ||
        policy.window > const Duration(seconds: 5) ||
        policy.lead.isNegative ||
        policy.hold <= Duration.zero ||
        policy.pointWindow.isNegative ||
        policy.pointWindow > const Duration(seconds: 5) ||
        !policy.distance.isFinite ||
        policy.distance <= 0 ||
        policy.distance > 1 ||
        policy.factor < 1 ||
        policy.maximum < policy.factor ||
        policy.maximum > 3 ||
        !policy.factor.isFinite ||
        !policy.maximum.isFinite ||
        policy.typingMinimum < 2 ||
        policy.typingMinimum > 10 ||
        !policy.smallTarget.isFinite ||
        policy.smallTarget <= 0 ||
        policy.smallTarget > 1) {
      throw const FormatException('Invalid screen zoom policy');
    }
    if (pointing.length > 100000) {
      throw const FormatException('Too many pointing phrases');
    }
    var previous = Duration.zero;
    for (final phrase in pointing) {
      if (phrase.start < previous) {
        throw const FormatException('Unordered pointing phrases');
      }
      previous = phrase.end;
    }
  }
  final ZoomPolicy policy;
  final List<SourceRange> _pointing;
  int _pointVisits = 0;
  final _targets = <_Target>[];
  ActivityEvent? _cursor, _focus;
  int _previous = -1, _keys = 0, _keyTime = -1, _keyStart = -1;
  _Target? _keyTarget;
  _Target? _keyAnchor;
  bool _finished = false;

  bool _recent(ActivityEvent? old, ActivityEvent now) =>
      old != null &&
      now.timeUs - old.timeUs <= policy.window.inMicroseconds &&
      old.width == now.width &&
      old.height == now.height;
  _Target? _target(ActivityEvent event, {bool click = false}) {
    final focus =
        _recent(_focus, event) &&
            _focus!.rectWidth > 0 &&
            _focus!.rectHeight > 0
        ? _focus
        : null;
    if (click) {
      if (!event.visible) return null;
      final inFocus =
          focus != null &&
          event.x >= focus.x &&
          event.y >= focus.y &&
          event.x < focus.x + focus.rectWidth &&
          event.y < focus.y + focus.rectHeight;
      return _Target(
        event.timeUs,
        event.x / event.width,
        event.y / event.height,
        event.width,
        event.height,
        inFocus &&
            math.max(
                  focus.rectWidth / focus.width,
                  focus.rectHeight / focus.height,
                ) <=
                policy.smallTarget,
      );
    }
    if (focus != null) {
      return _Target(
        event.timeUs,
        (focus.x + focus.rectWidth / 2) / focus.width,
        (focus.y + focus.rectHeight / 2) / focus.height,
        focus.width,
        focus.height,
        math.max(
              focus.rectWidth / focus.width,
              focus.rectHeight / focus.height,
            ) <=
            policy.smallTarget,
      );
    }
    if (_recent(_cursor, event) && _cursor!.visible) {
      final cursor = _cursor!;
      return _Target(
        event.timeUs,
        cursor.x / cursor.width,
        cursor.y / cursor.height,
        cursor.width,
        cursor.height,
        false,
      );
    }
    return null;
  }

  bool _near(_Target a, _Target b) =>
      a.width == b.width &&
      a.height == b.height &&
      math.max((a.x - b.x).abs(), (a.y - b.y).abs()) <= policy.distance;
  void _add(_Target? target) {
    if (target == null) return;
    if (_targets.length >= 100000) {
      throw const FormatException('Too much screen activity');
    }
    _targets.add(target);
  }

  _Target? _pointed(_Target? target) {
    if (target == null || policy.pointWindow == Duration.zero) return target;
    final window = policy.pointWindow.inMicroseconds;
    var low = 0, high = _pointing.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_pointing[mid].end.inMicroseconds < target.timeUs - window) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    // Choose the closest phrase; ties retain the earlier source interval.
    SourceRange? chosen;
    var distance = window + 1;
    for (
      var i = low;
      i < _pointing.length &&
          _pointing[i].start.inMicroseconds <= target.timeUs + window;
      ++i
    ) {
      if (++_pointVisits > 1000000) {
        throw const FormatException('Too much pointing evidence');
      }
      final phrase = _pointing[i];
      final delta = math.max(
        0,
        math.max(
          phrase.start.inMicroseconds - target.timeUs,
          target.timeUs - phrase.end.inMicroseconds,
        ),
      );
      if (delta < distance) {
        chosen = phrase;
        distance = delta;
      }
    }
    if (chosen == null) return target;
    return _Target(
      target.timeUs,
      target.x,
      target.y,
      target.width,
      target.height,
      target.small,
      pointing: chosen,
    );
  }

  void _finishKeys() {
    if (_keys >= policy.typingMinimum) {
      final target = _keyTarget!;
      _add(
        _Target(
          target.timeUs,
          target.x,
          target.y,
          target.width,
          target.height,
          target.small,
          startUs: _keyStart,
          evidence: _keys,
        ),
      );
    }
    _keys = 0;
    _keyTarget = null;
    _keyAnchor = null;
  }

  void add(ActivityEvent event) {
    if (_finished || event.timeUs < _previous) {
      throw const FormatException('Unordered screen activity');
    }
    _previous = event.timeUs;
    if (_keys > 0 &&
        (event.timeUs - _keyTime > policy.window.inMicroseconds ||
            event.timeUs - _keyStart > policy.window.inMicroseconds ||
            (event.type != 'cursor' &&
                event.type != 'focus' &&
                event.type != 'key'))) {
      _finishKeys();
    }
    switch (event.type) {
      case 'cursor':
        _cursor = event;
      case 'focus':
        _focus = event;
      case 'click':
        _add(_pointed(_target(event, click: true)));
      case 'shortcut':
        _add(_target(event));
      case 'key':
        final target = _target(event);
        if (target == null ||
            (_keyAnchor != null && !_near(_keyAnchor!, target))) {
          _finishKeys();
        }
        if (target != null) {
          if (_keys == 0) {
            _keyStart = event.timeUs;
            _keyAnchor = target;
          }
          _keys++;
          _keyTarget = target;
          _keyTime = event.timeUs;
        }
    }
  }

  ScreenZooms finish(CutPlan plan) {
    if (_finished) throw const FormatException('Screen activity already used');
    _finishKeys();
    _finished = true;
    // A typing burst is timestamped at its last key, so sort after combining.
    _targets.sort((a, b) => a.timeUs.compareTo(b.timeUs));
    final steps = <ZoomStep>[];
    var output = Duration.zero, count = 0, visited = 0;
    final ranges = <SourceRange>[];
    for (final range in plan.ranges) {
      if (ranges.isNotEmpty && ranges.last.end == range.start) {
        final previous = ranges.removeLast();
        ranges.add(SourceRange(start: previous.start, end: range.end));
      } else {
        ranges.add(range);
      }
    }
    for (final range in ranges) {
      var lo = 0, hi = _targets.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (_targets[mid].timeUs < range.start.inMicroseconds) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      var group = <_Target>[];
      void commit() {
        if (group.fold<int>(
              0,
              (sum, target) =>
                  sum +
                  target.evidence +
                  (target.pointing != null &&
                          target.pointing!.start >= range.start &&
                          target.pointing!.end <= range.end
                      ? 1
                      : 0),
            ) <
            2) {
          group.clear();
          return;
        }
        if (++count > 10000) {
          throw const FormatException('Too many screen zooms');
        }
        final first = group.first, last = group.last;
        final enter =
            output +
            Duration(
              microseconds: math.max(
                0,
                group.map((t) => t.startUs).reduce(math.min) -
                    range.start.inMicroseconds -
                    policy.lead.inMicroseconds,
              ),
            );
        final exit =
            output +
            Duration(
              microseconds: math.min(
                range.duration.inMicroseconds,
                last.timeUs -
                    range.start.inMicroseconds +
                    policy.hold.inMicroseconds,
              ),
            );
        if (steps.isNotEmpty &&
            steps.last.factor == 1 &&
            steps.last.time >= enter &&
            steps.last.time > output) {
          steps.removeLast();
        }
        final x = group.fold<double>(0, (sum, t) => sum + t.x) / group.length;
        final y = group.fold<double>(0, (sum, t) => sum + t.y) / group.length;
        final factor = group.any((t) => t.small)
            ? policy.maximum
            : policy.factor;
        steps.add(
          ZoomStep(
            time: enter,
            x: x,
            y: y,
            width: first.width,
            height: first.height,
            factor: factor,
          ),
        );
        steps.add(
          ZoomStep(
            time: exit,
            x: x,
            y: y,
            width: first.width,
            height: first.height,
            factor: 1,
          ),
        );
        group.clear();
      }

      for (
        var i = lo;
        i < _targets.length && _targets[i].timeUs < range.end.inMicroseconds;
        i++
      ) {
        if (++visited > 250000) {
          throw const FormatException('Too much reused screen activity');
        }
        final target = _targets[i];
        if (target.startUs < range.start.inMicroseconds) continue;
        if (group.isNotEmpty &&
            (target.timeUs - group.first.timeUs >
                    policy.window.inMicroseconds ||
                !_near(group.first, target))) {
          commit();
        }
        group.add(target);
      }
      commit();
      output += range.duration;
    }
    return ScreenZooms(count, steps);
  }
}

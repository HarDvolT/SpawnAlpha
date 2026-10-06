import 'dart:math' as math;

import '../model/cut_plan.dart';
import '../recording/activity_trace.dart';

class ClickPulse {
  ClickPulse({
    required this.start,
    required this.end,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    if (start.isNegative ||
        end <= start ||
        end - start > const Duration(seconds: 1) ||
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
      throw const FormatException('Invalid click pulse');
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
  factory ClickPulse.fromJson(Map<String, Object?> json) {
    if (json.length != 6 ||
        json['startUs'] is! int ||
        json['endUs'] is! int ||
        json['x'] is! num ||
        json['y'] is! num ||
        json['width'] is! int ||
        json['height'] is! int) {
      throw const FormatException('Invalid click pulse');
    }
    return ClickPulse(
      start: Duration(microseconds: json['startUs']! as int),
      end: Duration(microseconds: json['endUs']! as int),
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      width: json['width']! as int,
      height: json['height']! as int,
    );
  }
}

class ScreenClicks {
  ScreenClicks(List<ClickPulse> pulses) : pulses = List.unmodifiable(pulses) {
    if (pulses.length > 20000) {
      throw const FormatException('Too many click pulses');
    }
    var previous = Duration.zero;
    for (final pulse in pulses) {
      if (pulse.start < previous) {
        throw const FormatException('Unordered click pulses');
      }
      previous = pulse.start;
    }
  }
  final List<ClickPulse> pulses;
  int get count => pulses.length;
  Map<String, Object?> toJson() => {
    'version': 1,
    'pulses': pulses.map((p) => p.toJson()).toList(),
  };
  factory ScreenClicks.fromJson(Map<String, Object?> json) {
    if (json.length != 2 ||
        json['version'] != 1 ||
        json['pulses'] is! List ||
        (json['pulses']! as List).length > 20000) {
      throw const FormatException('Invalid click pulses');
    }
    return ScreenClicks(
      (json['pulses']! as List)
          .map((p) => ClickPulse.fromJson(Map<String, Object?>.from(p as Map)))
          .toList(),
    );
  }
}

class ScreenClickPlanner {
  ScreenClickPlanner(this.lifetime) {
    if (lifetime <= Duration.zero || lifetime > const Duration(seconds: 1)) {
      throw const FormatException('Invalid click lifetime');
    }
  }
  final Duration lifetime;
  final _clicks = <ActivityEvent>[];
  int _previous = -1;
  bool _finished = false;
  void add(ActivityEvent event) {
    if (_finished || event.timeUs < _previous) {
      throw const FormatException('Unordered click activity');
    }
    _previous = event.timeUs;
    if (event.type != 'click' || !event.visible) return;
    if (_clicks.length >= 20000) {
      throw const FormatException('Too many click pulses');
    }
    _clicks.add(event);
  }

  ScreenClicks finish(CutPlan plan) {
    if (_finished) throw const FormatException('Click activity already used');
    _finished = true;
    var output = Duration.zero, visited = 0;
    final pulses = <ClickPulse>[], ranges = <SourceRange>[];
    for (final range in plan.ranges) {
      if (ranges.isNotEmpty && ranges.last.end == range.start) {
        final old = ranges.removeLast();
        ranges.add(SourceRange(start: old.start, end: range.end));
      } else {
        ranges.add(range);
      }
    }
    for (final range in ranges) {
      var low = 0, high = _clicks.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (_clicks[mid].timeUs < range.start.inMicroseconds) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      for (
        var i = low;
        i < _clicks.length && _clicks[i].timeUs < range.end.inMicroseconds;
        ++i
      ) {
        if (++visited > 250000) {
          throw const FormatException('Too much reused click activity');
        }
        final event = _clicks[i];
        final start =
            output + Duration(microseconds: event.timeUs) - range.start;
        pulses.add(
          ClickPulse(
            start: start,
            end:
                output +
                Duration(
                  microseconds: math.min(
                    range.duration.inMicroseconds,
                    event.timeUs -
                        range.start.inMicroseconds +
                        lifetime.inMicroseconds,
                  ),
                ),
            x: event.x / event.width,
            y: event.y / event.height,
            width: event.width,
            height: event.height,
          ),
        );
        if (pulses.length > 20000) {
          throw const FormatException('Too many click pulses');
        }
      }
      output += range.duration;
    }
    return ScreenClicks(pulses);
  }
}

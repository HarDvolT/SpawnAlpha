import '../model/cut_plan.dart';
import '../recording/activity_trace.dart';

/// Only previously disclosed, allowlisted modifier labels can become text.
class ShortcutBadge {
  ShortcutBadge({required this.start, required this.end, required this.label}) {
    if (start.isNegative ||
        end <= start ||
        end - start > const Duration(seconds: 2) ||
        !activityShortcuts.contains(label)) {
      throw const FormatException('Invalid shortcut badge');
    }
  }
  final Duration start, end;
  final String label;
  Map<String, Object?> toJson() => {
    'startUs': start.inMicroseconds,
    'endUs': end.inMicroseconds,
    'label': label,
  };
  factory ShortcutBadge.fromJson(Map<String, Object?> json) {
    if (json.length != 3 ||
        json['startUs'] is! int ||
        json['endUs'] is! int ||
        json['label'] is! String) {
      throw const FormatException('Invalid shortcut badge');
    }
    return ShortcutBadge(
      start: Duration(microseconds: json['startUs']! as int),
      end: Duration(microseconds: json['endUs']! as int),
      label: json['label']! as String,
    );
  }
}

class ScreenShortcuts {
  ScreenShortcuts(List<ShortcutBadge> badges)
    : badges = List.unmodifiable(badges) {
    if (badges.length > 20000) {
      throw const FormatException('Too many shortcuts');
    }
    var previous = Duration.zero;
    for (final badge in badges) {
      if (badge.start < previous) {
        throw const FormatException('Overlapping shortcuts');
      }
      previous = badge.end;
    }
  }
  final List<ShortcutBadge> badges;
  int get count => badges.length;
  Map<String, Object?> toJson() => {
    'version': 1,
    'badges': badges.map((b) => b.toJson()).toList(),
  };
  factory ScreenShortcuts.fromJson(Map<String, Object?> json) {
    if (json.length != 2 ||
        json['version'] != 1 ||
        json['badges'] is! List ||
        (json['badges']! as List).length > 20000) {
      throw const FormatException('Invalid shortcuts');
    }
    return ScreenShortcuts(
      (json['badges']! as List)
          .map(
            (b) => ShortcutBadge.fromJson(Map<String, Object?>.from(b as Map)),
          )
          .toList(),
    );
  }
}

class ScreenShortcutPlanner {
  ScreenShortcutPlanner(this.lifetime) {
    if (lifetime <= Duration.zero || lifetime > const Duration(seconds: 2)) {
      throw const FormatException('Invalid shortcut lifetime');
    }
  }
  final Duration lifetime;
  final _events = <ActivityEvent>[];
  int _previous = -1;
  bool _finished = false;
  void add(ActivityEvent event) {
    if (_finished || event.timeUs < _previous) {
      throw const FormatException('Unordered shortcut activity');
    }
    _previous = event.timeUs;
    if (event.type != 'shortcut') return;
    if (_events.length >= 20000) {
      throw const FormatException('Too many shortcuts');
    }
    _events.add(event);
  }

  ScreenShortcuts finish(CutPlan plan) {
    if (_finished) {
      throw const FormatException('Shortcut activity already used');
    }
    _finished = true;
    final ranges = <SourceRange>[], badges = <ShortcutBadge>[];
    for (final range in plan.ranges) {
      if (ranges.isNotEmpty && ranges.last.end == range.start) {
        final old = ranges.removeLast();
        ranges.add(SourceRange(start: old.start, end: range.end));
      } else {
        ranges.add(range);
      }
    }
    var output = Duration.zero, visited = 0;
    for (final range in ranges) {
      var low = 0, high = _events.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (_events[mid].timeUs < range.start.inMicroseconds) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      for (
        var i = low;
        i < _events.length && _events[i].timeUs < range.end.inMicroseconds;
        ++i
      ) {
        if (++visited > 250000) {
          throw const FormatException('Too much reused shortcut activity');
        }
        final event = _events[i];
        final start =
            output + Duration(microseconds: event.timeUs) - range.start;
        var end = start + lifetime;
        if (end > output + range.duration) end = output + range.duration;
        if (badges.isNotEmpty && badges.last.end > start) {
          final old = badges.removeLast();
          if (old.start < start) {
            badges.add(
              ShortcutBadge(start: old.start, end: start, label: old.label),
            );
          }
        }
        badges.add(ShortcutBadge(start: start, end: end, label: event.detail!));
        if (badges.length > 20000) {
          throw const FormatException('Too many shortcuts');
        }
      }
      output += range.duration;
    }
    return ScreenShortcuts(badges);
  }
}

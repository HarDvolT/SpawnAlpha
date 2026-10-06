import 'dart:convert';
import 'dart:io';

const activityShortcuts = {
  'Ctrl+A',
  'Ctrl+C',
  'Ctrl+S',
  'Ctrl+V',
  'Ctrl+X',
  'Ctrl+Y',
  'Ctrl+Z',
  'Ctrl+Shift+A',
  'Ctrl+Shift+C',
  'Ctrl+Shift+S',
  'Ctrl+Shift+V',
  'Ctrl+Shift+X',
  'Ctrl+Shift+Y',
  'Ctrl+Shift+Z',
};

/// Versioned, anonymous activity. Parsing rejects unknown payloads and never
/// logs decoder errors. Streaming keeps a long recording's memory bounded.
class ActivityEvent {
  ActivityEvent._(
    this.type,
    this.timeUs,
    this.width,
    this.height,
    this.x,
    this.y,
    this.rectWidth,
    this.rectHeight,
    this.visible,
    this.detail,
    this.count,
  );
  final String type;
  final int timeUs, width, height, x, y, rectWidth, rectHeight, count;
  final bool visible;
  final String? detail;

  factory ActivityEvent.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (!const {'cursor', 'click', 'key', 'shortcut', 'focus'}.contains(type)) {
      throw const FormatException('Invalid activity type');
    }
    final fields = {'type', 'timeUs', 'width', 'height'};
    switch (type) {
      case 'cursor' || 'click':
        fields.addAll({'x', 'y', 'visible', 'detail'});
      case 'key':
        fields.add('count');
      case 'shortcut':
        fields.add('detail');
      case 'focus':
        fields.addAll({'x', 'y', 'rectWidth', 'rectHeight'});
    }
    if (json.length != fields.length || !json.keys.every(fields.contains)) {
      throw const FormatException('Invalid activity fields');
    }
    int integer(String name, {int min = 0, int max = 1 << 53}) {
      final value = json[name];
      if (value is! int || value < min || value > max) {
        throw const FormatException('Invalid activity number');
      }
      return value;
    }

    final width = integer('width', min: 1, max: 100000);
    final height = integer('height', min: 1, max: 100000);
    final position = type == 'cursor' || type == 'click' || type == 'focus';
    final x = position ? integer('x', max: width - 1) : 0;
    final y = position ? integer('y', max: height - 1) : 0;
    final rw = type == 'focus' ? integer('rectWidth', max: width - x) : 0;
    final rh = type == 'focus' ? integer('rectHeight', max: height - y) : 0;
    if (position && type != 'focus' && json['visible'] is! bool) {
      throw const FormatException('Invalid activity visibility');
    }
    final detail = json['detail'];
    if (type == 'cursor' &&
            !const {'arrow', 'text', 'hand', 'other'}.contains(detail) ||
        type == 'click' &&
            !const {'left', 'right', 'middle', 'extra'}.contains(detail) ||
        type == 'shortcut' && !activityShortcuts.contains(detail)) {
      throw const FormatException('Invalid activity detail');
    }
    return ActivityEvent._(
      type as String,
      integer('timeUs'),
      width,
      height,
      x,
      y,
      rw,
      rh,
      json['visible'] != false,
      detail as String?,
      type == 'key' ? integer('count', min: 1, max: 1) : 0,
    );
  }
}

class ActivitySummary {
  const ActivitySummary(this.events, this.complete, this.durationUs);
  final int events, durationUs;
  final bool complete;
  Map<String, Object?> toJson() => {
    'events': events,
    'complete': complete,
    'durationUs': durationUs,
  };
}

// Writers always terminate rows with a newline. Ignore only an unfinished final
// row after a crash, never a malformed full row. Bound each row before decoding.
Stream<Map<String, Object?>> activityRows(File file) async* {
  var pending = '';
  await for (final chunk in utf8.decoder.bind(file.openRead())) {
    final parts = chunk.split('\n');
    for (var index = 0; index < parts.length; ++index) {
      pending += parts[index];
      if (pending.length > 1024) {
        throw const FormatException('Activity row too large');
      }
      if (index == parts.length - 1) break;
      final json = jsonDecode(pending);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Invalid activity row');
      }
      yield Map<String, Object?>.from(json);
      pending = '';
    }
  }
}

Future<ActivitySummary> inspectActivity(File file, {Duration? limit}) async {
  var header = false, ended = false, count = 0, previous = -1, duration = 0;
  var usable = 0;
  var complete = false;
  await for (final row in activityRows(file)) {
    if (!header) {
      if (row.length != 4 ||
          row['type'] != 'header' ||
          row['version'] != 1 ||
          row['coordinates'] != 'sourcePixels' ||
          row['keys'] != 'timingOnly') {
        throw const FormatException('Invalid activity header');
      }
      header = true;
      continue;
    }
    if (ended) throw const FormatException('Activity after end');
    if (row['type'] == 'end') {
      final time = row['timeUs'];
      if (row.length != 4 ||
          row['events'] != count ||
          row['complete'] is! bool ||
          time is! int ||
          time < previous ||
          time < 0 ||
          time > 1 << 53) {
        throw const FormatException('Invalid activity end');
      }
      ended = true;
      complete = row['complete'] as bool;
      duration = time;
    } else {
      final event = ActivityEvent.fromJson(row);
      if (event.timeUs < previous) {
        throw const FormatException('Activity time went backwards');
      }
      previous = event.timeUs;
      ++count;
      if (limit == null || event.timeUs < limit.inMicroseconds) ++usable;
      duration = previous;
    }
  }
  if (!header) throw const FormatException('Missing activity header');
  return ActivitySummary(
    usable,
    complete && (limit == null || duration <= limit.inMicroseconds),
    limit == null ? duration : duration.clamp(0, limit.inMicroseconds),
  );
}

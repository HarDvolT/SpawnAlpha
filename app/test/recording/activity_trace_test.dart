import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/activity_trace.dart';

const activityHeader = {
  'type': 'header',
  'version': 1,
  'coordinates': 'sourcePixels',
  'keys': 'timingOnly',
};
String generatedActivity({bool complete = true}) =>
    '${[
      activityHeader,
      {'type': 'cursor', 'timeUs': 0, 'width': 640, 'height': 360, 'x': 120, 'y': 100, 'visible': true, 'detail': 'arrow'},
      {'type': 'key', 'timeUs': 100, 'width': 640, 'height': 360, 'count': 1},
      {'type': 'shortcut', 'timeUs': 200, 'width': 640, 'height': 360, 'detail': 'Ctrl+S'},
      if (complete) {'type': 'end', 'timeUs': 3000000, 'events': 3, 'complete': true},
    ].map(jsonEncode).join('\n')}\n';

void main() {
  test(
    'a surviving video fragment limits activity without rewriting the sidecar',
    () async {
      await Directory('build/activity-test').create(recursive: true);
      final dir = await Directory('build/activity-test').createTemp('limited-');
      final file = File('${dir.path}/trace.jsonl');
      try {
        final original = generatedActivity();
        await file.writeAsString(original);
        final result = await inspectActivity(
          file,
          limit: const Duration(microseconds: 150),
        );
        expect(result.events, 2);
        expect(result.durationUs, 150);
        expect(result.complete, isFalse);
        expect(await file.readAsString(), original);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  late Directory dir;
  late File file;
  setUp(() async {
    await Directory('build/activity-test').create(recursive: true);
    dir = await Directory('build/activity-test').createTemp('trace-');
    file = File('${dir.path}/activity.jsonl');
  });
  tearDown(() async => dir.delete(recursive: true));
  test('container rounding keeps complete activity; a shorter sparse take does not', () async {
    await file.writeAsString(generatedActivity());
    final rounded = await inspectActivity(
      file,
      limit: const Duration(microseconds: 2999999),
    );
    expect(rounded.complete, isTrue);
    expect(rounded.durationUs, 2999999);
    final truncated = await inspectActivity(
      file,
      limit: const Duration(seconds: 1),
    );
    expect(truncated.complete, isFalse);
  });
  test('streaming valid anonymous records and complete footer', () async {
    await file.writeAsString(generatedActivity());
    final result = await inspectActivity(file);
    expect(result.events, 3);
    expect(result.complete, isTrue);
    expect(result.durationUs, 3000000);
  });
  test(
    'crash keeps full records and ignores only the truncated last row',
    () async {
      await file.writeAsString(
        '${generatedActivity(complete: false)}{"type":"key","ti',
      );
      final result = await inspectActivity(file);
      expect(result.events, 3);
      expect(result.complete, isFalse);
      expect(result.durationUs, 200);
    },
  );
  test('unknown/private key identities, text and shortcuts are rejected', () {
    const key = {
      'type': 'key',
      'timeUs': 0,
      'width': 640,
      'height': 360,
      'count': 1,
    };
    for (final private in ['text', 'key', 'scanCode', 'title', 'deviceId']) {
      expect(
        () => ActivityEvent.fromJson({...key, private: 'private'}),
        throwsFormatException,
      );
    }
    for (final chord in [
      'S',
      'AltGr+A',
      'Ctrl+Alt+A',
      'Ctrl+P',
      'typed text',
    ]) {
      expect(
        () => ActivityEvent.fromJson({
          'type': 'shortcut',
          'timeUs': 0,
          'width': 640,
          'height': 360,
          'detail': chord,
        }),
        throwsFormatException,
      );
    }
  });
  test('bounds, cursor shapes and named shortcuts are checked', () {
    const cursor = {
      'type': 'cursor',
      'timeUs': 0,
      'width': 640,
      'height': 360,
      'x': 0,
      'y': 0,
      'visible': false,
      'detail': 'other',
    };
    expect(ActivityEvent.fromJson(cursor).visible, isFalse);
    for (final invalid in [
      {...cursor, 'x': 640},
      {...cursor, 'width': 0},
      {...cursor, 'detail': 'private cursor'},
      {...cursor, 'timeUs': -1},
    ]) {
      expect(() => ActivityEvent.fromJson(invalid), throwsFormatException);
    }
    for (final chord in activityShortcuts) {
      expect(
        ActivityEvent.fromJson({
          'type': 'shortcut',
          'timeUs': 0,
          'width': 640,
          'height': 360,
          'detail': chord,
        }).detail,
        chord,
      );
    }
  });
  test(
    'malformed full rows and backwards times fail instead of hiding corruption',
    () async {
      for (final contents in [
        '${jsonEncode(activityHeader)}\ninvalid\n',
        generatedActivity().replaceFirst('"timeUs":200', '"timeUs":50'),
        generatedActivity().replaceFirst('"events":3', '"events":2'),
        '${generatedActivity()}${jsonEncode(activityHeader)}\n',
        '[]\n',
        '${'x' * 1025}\n',
      ]) {
        await file.writeAsString(contents);
        await expectLater(inspectActivity(file), throwsFormatException);
      }
    },
  );
  test('long trace inspection has no event-list memory growth', () async {
    final sink = file.openWrite();
    sink.writeln(jsonEncode(activityHeader));
    for (var index = 0; index < 100000; ++index) {
      sink.writeln(
        jsonEncode({
          'type': 'key',
          'timeUs': index,
          'width': 640,
          'height': 360,
          'count': 1,
        }),
      );
    }
    sink.writeln(
      jsonEncode({
        'type': 'end',
        'timeUs': 100000,
        'events': 100000,
        'complete': true,
      }),
    );
    await sink.close();
    expect((await inspectActivity(file)).events, 100000);
  });
}

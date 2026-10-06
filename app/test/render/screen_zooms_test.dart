import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/activity_trace.dart';
import 'package:spawnalpha/src/render/screen_zooms.dart';
import 'package:spawnalpha/src/render/screen_zoom_loader.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';

const policy = ZoomPolicy(
  window: Duration(milliseconds: 1300),
  distance: .3,
  lead: Duration(milliseconds: 300),
  hold: Duration(milliseconds: 1400),
  factor: 1.8,
  maximum: 2.4,
  typingMinimum: 3,
  smallTarget: .12,
);

ActivityEvent event(
  String type,
  int ms, {
  int x = 800,
  int y = 500,
  int width = 1000,
  int height = 1000,
  bool visible = true,
}) => ActivityEvent.fromJson({
  'type': type,
  'timeUs': ms * 1000,
  'width': width,
  'height': height,
  if (type == 'click' || type == 'cursor') ...{
    'x': x,
    'y': y,
    'visible': visible,
    'detail': type == 'click' ? 'left' : 'arrow',
  },
  if (type == 'focus') ...{'x': x, 'y': y, 'rectWidth': 80, 'rectHeight': 80},
  if (type == 'key') 'count': 1,
  if (type == 'shortcut') 'detail': 'Ctrl+S',
});
SourceRange span(int startMs, int endMs) => SourceRange(
  start: Duration(milliseconds: startMs),
  end: Duration(milliseconds: endMs),
);
CutPlan plan({
  ScriptLanguage language = ScriptLanguage.en,
  List<SourceRange>? ranges,
}) => CutPlan(
  takeId: 'generated',
  language: language,
  sourceDuration: const Duration(seconds: 5),
  ranges: ranges ?? [span(0, 5000)],
);
ScreenZooms zooms(List<ActivityEvent> events, {CutPlan? cut}) {
  final planner = ScreenZoomPlanner(policy);
  for (final event in events) {
    planner.add(event);
  }
  return planner.finish(cut ?? plan());
}

void main() {
  test('clusters and typing bursts cannot chain beyond the time window', () {
    final clicks = zooms([
      event('click', 500),
      event('click', 700),
      event('click', 1900),
    ]);
    expect(clicks.count, 1);
    expect(clicks.steps.last.time, const Duration(milliseconds: 2100));
    final typing = zooms([
      for (final ms in [100, 1100, 2100, 3100]) ...[
        event('cursor', ms),
        event('key', ms + 1),
      ],
    ]);
    expect(typing.count, 0);
  });
  test(
    'typing cannot drift across the screen through chained nearby targets',
    () {
      final result = zooms([
        event('cursor', 100, x: 200),
        event('key', 101),
        event('cursor', 200, x: 400),
        event('key', 201),
        event('cursor', 300, x: 600),
        event('key', 301),
      ]);
      expect(result.count, 0);
    },
  );
  for (final language in ScriptLanguage.values) {
    test('click evidence and lead/hold stay on the output clock $language', () {
      final result = zooms([
        event('click', 500),
        event('click', 700, x: 820),
      ], cut: plan(language: language));
      expect(result.count, 1);
      expect(result.steps.first.time, const Duration(milliseconds: 200));
      expect(result.steps.last.time, const Duration(milliseconds: 2100));
      expect(result.steps.first.x, closeTo(.81, .00001));
      expect(result.steps.first.factor, 1.8);
      expect(result.steps.last.factor, 1);
      expect(ScreenZooms.fromJson(result.toJson()).toJson(), result.toJson());
      expect(() => result.steps.clear(), throwsUnsupportedError);
    });
    test(
      'discarded/reordered ranges keep their own screen evidence $language',
      () {
        final events = [
          event('click', 500, x: 200),
          event('click', 700, x: 200),
          event('click', 2500),
          event('click', 2700),
          event('click', 3500, x: 600),
          event('click', 3700, x: 600),
        ];
        final cut = plan(
          language: language,
          ranges: [span(3000, 5000), span(0, 2000)],
        );
        final result = zooms(events, cut: cut);
        expect(result.count, 2);
        expect(result.steps.where((s) => s.factor > 1).map((s) => s.x), [
          .6,
          .2,
        ]);
        expect(result.steps.map((s) => s.time.inMilliseconds), [
          200,
          2000,
          2200,
          4000,
        ]);
        expect(result.steps.any((s) => s.x == .8), isFalse);
        expect(cut.duration, const Duration(seconds: 4));
      },
    );
  }
  test('a lone, distant, hidden or resized click keeps the whole picture', () {
    for (final events in [
      [event('click', 500)],
      [event('click', 500), event('click', 2000)],
      [event('click', 500, x: 100), event('click', 700, x: 900)],
      [event('click', 500, visible: false), event('click', 700)],
      [event('click', 500), event('click', 700, width: 1200)],
    ]) {
      expect(zooms(events).count, 0);
    }
  });
  test('typing requires a recent position and all its evidence kept', () {
    final events = [
      event('focus', 300, x: 500),
      event('key', 400),
      event('key', 500),
      event('key', 600),
    ];
    final result = zooms(events);
    expect(result.count, 1);
    expect(result.steps.first.factor, 2.4);
    expect(result.steps.first.x, .54);
    expect(result.steps.first.time.inMilliseconds, 100);
    expect(zooms(events, cut: plan(ranges: [span(500, 5000)])).count, 0);
    expect(
      zooms([event('key', 400), event('key', 500), event('key', 600)]).count,
      0,
    );
    expect(
      zooms([
        event('focus', 0),
        event('key', 2000),
        event('key', 2100),
        event('key', 2200),
      ]).count,
      0,
    );
    expect(zooms(events.take(3).toList()).count, 0);
  });
  test('shortcuts use a fresh visible cursor and preserve anonymous input', () {
    expect(
      zooms([
        event('cursor', 300),
        event('shortcut', 500),
        event('shortcut', 700),
      ]).count,
      1,
    );
    expect(
      zooms([
        event('cursor', 300, visible: false),
        event('shortcut', 500),
        event('shortcut', 700),
      ]).count,
      0,
    );
    expect(
      zooms([
        event('cursor', 300),
        event('shortcut', 500, width: 1200),
        event('shortcut', 700, width: 1200),
      ]).count,
      0,
    );
  });
  test(
    'small measured click targets get the maximum; overlapping clusters pan',
    () {
      final small = zooms([
        event('focus', 300, x: 780),
        event('click', 500),
        event('click', 700),
      ]);
      expect(small.steps.first.factor, 2.4);
      final panning = zooms([
        event('click', 500, x: 200),
        event('click', 700, x: 200),
        event('click', 1000),
        event('click', 1200),
      ]);
      expect(panning.count, 2);
      expect(panning.steps.map((s) => s.factor), [1.8, 1.8, 1]);
      expect(panning.steps.map((s) => s.time.inMilliseconds), [200, 700, 2600]);
    },
  );
  test('continuous source splitting preserves the same zoom decisions', () {
    final events = [event('click', 500), event('click', 700)];
    expect(
      zooms(
        events,
        cut: plan(ranges: [span(0, 600), span(600, 5000)]),
      ).toJson(),
      zooms(events).toJson(),
    );
  });
  test(
    'malformed clocks, coordinates, counts and private fields are rejected',
    () {
      final result = zooms([event('click', 500), event('click', 700)]);
      expect(() => ScreenZooms(2, result.steps), throwsFormatException);
      expect(
        () =>
            ZoomStep.fromJson(result.steps.first.toJson()..['x'] = double.nan),
        throwsFormatException,
      );
      expect(
        () => ZoomStep.fromJson(
          result.steps.first.toJson()..['text'] = 'forbidden',
        ),
        throwsFormatException,
      );
      expect(
        () => zooms([event('click', 700), event('click', 500)]),
        throwsFormatException,
      );
      final late = ScreenZooms(1, [
        ZoomStep(
          time: const Duration(seconds: 6),
          x: .5,
          y: .5,
          width: 100,
          height: 100,
          factor: 1.8,
        ),
        ZoomStep(
          time: const Duration(seconds: 7),
          x: .5,
          y: .5,
          width: 100,
          height: 100,
          factor: 1,
        ),
      ]);
      expect(
        () => VideoRenderRequest(
          source: 'generated.mp4',
          output: 'new.mp4',
          plan: plan(),
          format: VideoFormat.landscape,
          screenZooms: late,
        ),
        throwsFormatException,
      );
      final video = VideoExport(
        id: 'generated',
        format: VideoFormat.landscape,
        duration: const Duration(seconds: 5),
        createdAt: DateTime(2026),
        zoomCount: 1,
      );
      expect(VideoExport.fromJson(video.toJson()).zoomCount, 1);
      expect(
        VideoExport.fromJson(video.toJson()..remove('zoomCount')).zoomCount,
        0,
      );
      expect(
        () => VideoExport.fromJson(video.toJson()..['zoomCount'] = -1),
        throwsFormatException,
      );
    },
  );
  test(
    'local sidecar validation fails closed and accepts a crash-truncated tail',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'spawnalpha-screen-zoom-',
      );
      final source = File('${root.path}/generated.mp4'),
          file = File('${root.path}/activity.jsonl');
      await source.writeAsString('generated bytes');
      final rows = [
        {
          'type': 'header',
          'version': 1,
          'coordinates': 'sourcePixels',
          'keys': 'timingOnly',
        },
        for (final ms in [500, 700])
          {
            'type': 'click',
            'timeUs': ms * 1000,
            'width': 1000,
            'height': 1000,
            'x': 800,
            'y': 500,
            'visible': true,
            'detail': 'left',
          },
        {'type': 'end', 'timeUs': 5000000, 'events': 2, 'complete': true},
      ];
      Future<LoadedScreenZooms> load() => loadScreenZooms(
        ScreenZoomJob(source.path, file.path, plan(), policy),
      );
      try {
        await file.writeAsString('${rows.map(jsonEncode).join('\n')}\n');
        expect((await load()).zooms.count, 1);
        expect((await load()).unavailable, isFalse);
        await file.writeAsString(
          '${rows.take(3).map(jsonEncode).join('\n')}\n{"type"',
        );
        expect((await load()).zooms.count, 1);
        await file.writeAsString(
          '${rows.map(jsonEncode).join('\n')}\n${jsonEncode(rows[1])}\n',
        );
        expect((await load()).unavailable, isTrue);
        expect((await load()).zooms.count, 0);
        await file.delete();
        expect((await load()).unavailable, isTrue);
        final other = await Directory('${root.path}/other').create();
        final misplaced = File('${other.path}/activity.jsonl');
        await misplaced.writeAsString('${rows.map(jsonEncode).join('\n')}\n');
        expect(
          (await loadScreenZooms(
            ScreenZoomJob(source.path, misplaced.path, plan(), policy),
          )).unavailable,
          isTrue,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

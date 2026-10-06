import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/screen_clicks.dart';
import 'package:spawnalpha/src/render/screen_zoom_loader.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';

import 'screen_zooms_test.dart' show event, policy, span;
import 'screen_zoom_export_test.dart' show activityFor;

CutPlan cut(ScriptLanguage language, List<SourceRange> ranges) => CutPlan(
  takeId: 'generated',
  language: language,
  sourceDuration: const Duration(seconds: 5),
  ranges: ranges,
);
ScreenClicks clicks(CutPlan plan) =>
    (ScreenClickPlanner(const Duration(milliseconds: 420))
          ..add(event('cursor', 100))
          ..add(event('key', 200))
          ..add(event('click', 500, x: 100))
          ..add(event('click', 800, visible: false))
          ..add(event('click', 2500, x: 800))
          ..add(event('click', 4900, x: 300)))
        .finish(plan);

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'clicks retain their own cut/reorder times and geometry $language',
      () {
        final plan = cut(language, [
          span(2000, 3000),
          span(0, 700),
          span(4500, 5000),
        ]);
        final result = clicks(plan);
        expect(result.count, 3);
        expect(result.pulses.map((p) => p.x), [.8, .1, .3]);
        expect(result.pulses.map((p) => p.start.inMilliseconds), [
          500,
          1500,
          2100,
        ]);
        expect(result.pulses.map((p) => p.end.inMilliseconds), [
          920,
          1700,
          2200,
        ]);
        expect(
          ScreenClicks.fromJson(result.toJson()).toJson(),
          result.toJson(),
        );
        expect(() => result.pulses.clear(), throwsUnsupportedError);
      },
    );
    test('continuous splits preserve ripple lifetime $language', () {
      expect(
        clicks(cut(language, [span(0, 5000)])).toJson(),
        clicks(cut(language, [span(0, 600), span(600, 5000)])).toJson(),
      );
    });
  }
  test('click model/native request/history reject malformed clocks and private payloads', () {
    final pulse = ClickPulse(
      start: const Duration(milliseconds: 500),
      end: const Duration(milliseconds: 920),
      x: .8,
      y: .5,
      width: 640,
      height: 360,
    );
    for (final malformed in [
      {...pulse.toJson(), 'x': double.nan},
      {...pulse.toJson(), 'width': 0},
      {...pulse.toJson(), 'endUs': 1500001},
      {...pulse.toJson(), 'text': 'private'},
    ]) {
      expect(() => ClickPulse.fromJson(malformed), throwsFormatException);
    }
    final result = ScreenClicks([pulse]);
    expect(
      () => ScreenClicks.fromJson({...result.toJson(), 'keys': []}),
      throwsFormatException,
    );
    expect(
      () => ScreenClicks([
        pulse,
        ClickPulse(
          start: Duration.zero,
          end: const Duration(milliseconds: 420),
          x: .8,
          y: .5,
          width: 640,
          height: 360,
        ),
      ]),
      throwsFormatException,
    );
    final request = VideoRenderRequest(
      source: 'generated',
      output: 'fresh',
      plan: cut(ScriptLanguage.en, [span(0, 1000)]),
      format: VideoFormat.portrait,
      screenClicks: result,
    );
    expect(request.toJson()['clickPulses'], [pulse.toJson()]);
    expect((request.toJson()['clickLayout'] as Map)['grow'], 4.4);
    expect(
      () => VideoRenderRequest(
        source: 'generated',
        output: 'fresh',
        plan: cut(ScriptLanguage.en, [span(0, 600)]),
        format: VideoFormat.portrait,
        screenClicks: result,
      ),
      throwsFormatException,
    );
    final video = VideoExport(
      id: 'generated',
      format: VideoFormat.landscape,
      duration: const Duration(seconds: 1),
      createdAt: DateTime(2026),
      clickCount: 1,
    );
    expect(VideoExport.fromJson(video.toJson()).clickCount, 1);
    expect(
      VideoExport.fromJson(video.toJson()..remove('clickCount')).clickCount,
      0,
    );
    expect(
      () => VideoExport.fromJson({...video.toJson(), 'clickCount': true}),
      throwsFormatException,
    );
  });
  test('activity worker can create clicks with zoom off and rejects malformed rows', () async {
    final root = await Directory.systemTemp.createTemp('spawnalpha-clicks-');
    try {
      final source = File('${root.path}/generated.mp4');
      final activity = await activityFor(source);
      final plan = cut(ScriptLanguage.en, [span(0, 5000)]);
      final job = ScreenZoomJob(
        source.path,
        activity.path,
        plan,
        policy,
        autoZoom: false,
        clickDuration: const Duration(milliseconds: 420),
      );
      final result = await loadScreenZooms(job);
      expect(result.zooms.count, 0);
      expect(result.clicks!.count, 2);
      expect(
        result.clicks!.pulses.first.end,
        const Duration(milliseconds: 920),
      );
      await activity.writeAsString(
        '${jsonEncode({'type': 'header', 'version': 1, 'coordinates': 'sourcePixels', 'keys': 'timingOnly'})}\n${jsonEncode({'type': 'key', 'text': 'private'})}\n',
      );
      final invalid = await loadScreenZooms(job);
      expect(invalid.unavailable, isTrue);
      expect(invalid.clicks, isNull);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('click collection and reused output tracks stay bounded', () {
    final planner = ScreenClickPlanner(const Duration(milliseconds: 420));
    for (var i = 0; i < 20000; ++i) {
      planner.add(event('click', 500));
    }
    expect(() => planner.add(event('click', 500)), throwsFormatException);
    final repeated = cut(ScriptLanguage.en, [span(0, 1000), span(0, 1000)]);
    expect(() => planner.finish(repeated), throwsFormatException);
  });
}

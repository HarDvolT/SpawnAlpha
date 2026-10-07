import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/activity_trace.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/screen_shortcuts.dart';
import 'package:spawnalpha/src/render/screen_zoom_loader.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';

import 'export_processor_test.dart' show FakeRenderer;
import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;
import 'screen_zooms_test.dart' show policy, span;

ActivityEvent chord(int ms, [String label = 'Ctrl+C']) =>
    ActivityEvent.fromJson({
      'type': 'shortcut',
      'timeUs': ms * 1000,
      'width': 640,
      'height': 360,
      'detail': label,
    });
CutPlan cut(ScriptLanguage language, List<SourceRange> ranges) => CutPlan(
  takeId: 'generated',
  language: language,
  sourceDuration: const Duration(seconds: 5),
  ranges: ranges,
);
ScreenShortcuts badges(CutPlan plan) =>
    (ScreenShortcutPlanner(const Duration(milliseconds: 1100))
          ..add(chord(500))
          ..add(chord(800, 'Ctrl+V'))
          ..add(chord(2500, 'Ctrl+Shift+Z'))
          ..add(chord(4900, 'Ctrl+S')))
        .finish(plan);
Future<File> activityFor(File source) async {
  final file = File('${source.path}.activity.jsonl');
  await file.writeAsString(
    [
      jsonEncode({
        'type': 'header',
        'version': 1,
        'coordinates': 'sourcePixels',
        'keys': 'timingOnly',
      }),
      jsonEncode({
        'type': 'shortcut',
        'timeUs': 500000,
        'width': 640,
        'height': 360,
        'detail': 'Ctrl+C',
      }),
      jsonEncode({
        'type': 'key',
        'timeUs': 600000,
        'width': 640,
        'height': 360,
        'count': 1,
      }),
      jsonEncode({
        'type': 'end',
        'timeUs': 5000000,
        'events': 2,
        'complete': true,
      }),
      '',
    ].join('\n'),
  );
  return file;
}

void main() {
  for (final language in ScriptLanguage.values) {
    test('shortcut source identity and cut boundaries $language', () {
      final result = badges(
        cut(language, [span(2000, 3000), span(0, 700), span(4500, 5000)]),
      );
      expect(result.badges.map((b) => b.label), [
        'Ctrl+Shift+Z',
        'Ctrl+C',
        'Ctrl+S',
      ]);
      expect(result.badges.map((b) => b.start.inMilliseconds), [
        500,
        1500,
        2100,
      ]);
      expect(result.badges.map((b) => b.end.inMilliseconds), [
        1000,
        1700,
        2200,
      ]);
      expect(
        ScreenShortcuts.fromJson(result.toJson()).toJson(),
        result.toJson(),
      );
      expect(() => result.badges.clear(), throwsUnsupportedError);
    });
    test(
      'continuous splits, latest shortcut and fixed LTR labels $language',
      () {
        final whole = badges(cut(language, [span(0, 5000)]));
        final split = badges(cut(language, [span(0, 600), span(600, 5000)]));
        expect(whole.toJson(), split.toJson());
        expect(whole.badges.first.end.inMilliseconds, 800);
        final request = VideoRenderRequest(
          source: 'generated',
          output: 'fresh',
          plan: cut(language, [span(0, 5000)]),
          format: VideoFormat.portrait,
          screenShortcuts: whole,
        );
        expect(
          request.toJson()['shortcutBadges'],
          whole.badges.map((b) => b.toJson()).toList(),
        );
        expect((request.toJson()['shortcutLayout'] as Map)['fontSize'], 32);
        expect(
          (request.toJson()['shortcutLayout'] as Map).containsKey('rtl'),
          isFalse,
        );
      },
    );
    for (final mode in ['on', 'off', 'unavailable']) {
      test(
        'independent shortcut export and original preservation $language $mode',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'spawnalpha-shortcuts-',
          );
          final library = ScriptLibrary(MemoryScriptStore()),
              inspector = FakeInspector();
          final renderer = FakeRenderer(inspector);
          final store = VideoExportStore(
            Directory('${root.path}/exports'),
            library,
            inspector,
          );
          final job = ExportProcessor(
            renderer,
            store,
            CleanCutStore(Directory('${root.path}/cuts'), library),
            (_) async => null,
          );
          try {
            final source = File('${root.path}/generated.mp4');
            await source.writeAsString('generated media');
            final activity = await activityFor(source),
                original = await activity.readAsString();
            if (mode == 'unavailable') await activity.delete();
            final take = Take(
              path: source.path,
              recordedAt: DateTime(2026),
              duration: const Duration(seconds: 5),
              mode: TakeMode.screen,
              activityPath: activity.path,
            );
            final script = ScriptDocument.create(language: language)
                .copyWith(takes: [take]);
            await library.save(script);
            final video = (await job.export(
              script,
              take,
              VideoFormat.feed,
              autoZoom: false,
              clickHighlights: false,
              showShortcuts: mode != 'off',
            ))!;
            expect(video.shortcutCount, mode == 'on' ? 1 : 0);
            expect(video.zoomCount, 0);
            expect(video.clickCount, 0);
            expect(job.notice != null, mode == 'unavailable');
            final json = jsonDecode(
              await store.file(video, 'json').readAsString(),
            ) as Map;
            if (mode == 'on') {
              expect(
                ScreenShortcuts.fromJson(
                  Map<String, Object?>.from(json['screenShortcuts'] as Map),
                ).badges.single.label,
                'Ctrl+C',
              );
            }
            expect(jsonEncode(json), isNot(contains(source.path)));
            expect(
              (await store.load(library.byId(script.id)!.takes.single))
                  .single
                  .shortcutCount,
              video.shortcutCount,
            );
            expect(await source.readAsString(), 'generated media');
            if (mode != 'unavailable') {
              expect(await activity.readAsString(), original);
            }
          } finally {
            job.dispose();
            library.dispose();
            await root.delete(recursive: true);
          }
        },
      );
    }
  }
  test(
    'same-time latest badge, anonymous plain typing, bounded collection',
    () {
      final planner = ScreenShortcutPlanner(const Duration(milliseconds: 1100));
      planner.add(chord(500));
      planner.add(chord(500, 'Ctrl+V'));
      planner.add(
        ActivityEvent.fromJson({
          'type': 'key',
          'timeUs': 600000,
          'width': 640,
          'height': 360,
          'count': 1,
        }),
      );
      expect(
        planner
            .finish(cut(ScriptLanguage.en, [span(0, 5000)]))
            .badges
            .single
            .label,
        'Ctrl+V',
      );
      expect(() => planner.add(chord(700)), throwsFormatException);
      final bounded = ScreenShortcutPlanner(const Duration(milliseconds: 1100));
      for (var i = 0; i < 20000; ++i) {
        bounded.add(chord(500));
      }
      expect(() => bounded.add(chord(500)), throwsFormatException);
    },
  );
  test(
    'malformed labels/clocks/fields and overlapping history are rejected',
    () {
      final badge = ShortcutBadge(
        start: const Duration(milliseconds: 500),
        end: const Duration(milliseconds: 1600),
        label: 'Ctrl+C',
      );
      for (final label in activityShortcuts) {
        expect(
          ShortcutBadge.fromJson({...badge.toJson(), 'label': label}).label,
          label,
        );
      }
      for (final malformed in [
        {...badge.toJson(), 'label': 'C'},
        {...badge.toJson(), 'label': 'Ctrl+password'},
        {...badge.toJson(), 'label': 'Ctrl+Alt+C'},
        {...badge.toJson(), 'text': 'private'},
        {...badge.toJson(), 'endUs': 500000},
        {...badge.toJson(), 'endUs': 2500001},
      ]) {
        expect(() => ShortcutBadge.fromJson(malformed), throwsFormatException);
      }
      expect(() => ScreenShortcuts([badge, badge]), throwsFormatException);
      expect(
        () => VideoRenderRequest(
          source: 'generated',
          output: 'fresh',
          plan: cut(ScriptLanguage.en, [span(0, 1000)]),
          format: VideoFormat.feed,
          screenShortcuts: ScreenShortcuts([badge]),
        ),
        throwsFormatException,
      );
      final video = VideoExport(
        id: 'generated',
        format: VideoFormat.feed,
        duration: const Duration(seconds: 5),
        createdAt: DateTime(2026),
        shortcutCount: 1,
      );
      expect(VideoExport.fromJson(video.toJson()).shortcutCount, 1);
      expect(
        VideoExport.fromJson(video.toJson()..remove('shortcutCount'))
            .shortcutCount,
        0,
      );
      expect(
        () => VideoExport.fromJson({...video.toJson(), 'shortcutCount': true}),
        throwsFormatException,
      );
    },
  );
  test(
    'recovery validates frozen shortcuts after the activity disappears',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'spawnalpha-shortcut-recover-',
      );
      final disk = FailingStore(), inspector = FakeInspector();
      final library = ScriptLibrary(disk), renderer = FakeRenderer(inspector);
      final store = VideoExportStore(
        Directory('${root.path}/exports'),
        library,
        inspector,
      );
      final job = ExportProcessor(
        renderer,
        store,
        CleanCutStore(Directory('${root.path}/cuts'), library),
        (_) async => null,
      );
      try {
        final source = File('${root.path}/generated.mp4');
        await source.writeAsString('generated');
        final activity = await activityFor(source);
        final take = Take(
          path: source.path,
          recordedAt: DateTime(2026),
          duration: const Duration(seconds: 5),
          mode: TakeMode.screen,
          activityPath: activity.path,
        );
        final script = ScriptDocument.create().copyWith(takes: [take]);
        await library.save(script);
        renderer.deferred = Completer<void>();
        final future = job.export(
          script,
          take,
          VideoFormat.feed,
          autoZoom: false,
          clickHighlights: false,
        );
        await renderer.started.future;
        final expected = renderer.request!.screenShortcuts!.toJson();
        disk.fail = true;
        renderer.deferred!.complete();
        expect(await future, isNull);
        final journal = (await store.pending.list().toList())
            .whereType<File>()
            .single;
        final saved = jsonDecode(await journal.readAsString()) as Map;
        disk.fail = false;
        await activity.delete();
        for (final bad in [
          {'version': 1, 'badges': []},
          {
            'version': 1,
            'badges': [
              {'startUs': 500000, 'endUs': 1600000, 'label': 'private'},
            ],
          },
          {
            'version': 1,
            'badges': [
              {'startUs': 4800000, 'endUs': 5600000, 'label': 'Ctrl+C'},
            ],
          },
        ]) {
          await journal.writeAsString(
            jsonEncode({...saved, 'screenShortcuts': bad}),
          );
          expect(await store.recover(), 0);
        }
        await journal.writeAsString(jsonEncode(saved));
        expect(await store.recover(), 1);
        expect(await store.recover(), 0);
        final video = (await store.load(library.byId(script.id)!.takes.single))
            .single;
        expect(video.shortcutCount, 1);
        expect(
          (jsonDecode(await store.file(video, 'json').readAsString())
              as Map)['screenShortcuts'],
          expected,
        );
      } finally {
        job.dispose();
        library.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test('worker rejects private activity instead of rendering text', () async {
    final root = await Directory.systemTemp.createTemp(
      'spawnalpha-shortcut-worker-',
    );
    try {
      final source = File('${root.path}/generated.mp4'),
          file = await activityFor(File('${root.path}/generated.mp4'));
      final job = ScreenZoomJob(
        source.path,
        file.path,
        cut(ScriptLanguage.en, [span(0, 5000)]),
        policy,
        autoZoom: false,
        shortcutDuration: const Duration(milliseconds: 1100),
      );
      expect((await loadScreenZooms(job)).shortcuts!.count, 1);
      await file.writeAsString(
        (await file.readAsString()).replaceAll('Ctrl+C', 'private'),
      );
      final invalid = await loadScreenZooms(job);
      expect(invalid.unavailable, isTrue);
      expect(invalid.shortcuts, isNull);
    } finally {
      await root.delete(recursive: true);
    }
  });
}

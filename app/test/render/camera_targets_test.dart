import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/camera_targets.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';

import 'screen_zooms_test.dart' show event, span;
import 'screen_zoom_export_test.dart' show activityFor;
import 'export_processor_test.dart' show FakeRenderer;
import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;

CutPlan cut(ScriptLanguage language, List<SourceRange> ranges) => CutPlan(
  takeId: 'generated',
  language: language,
  sourceDuration: const Duration(seconds: 5),
  ranges: ranges,
);
CameraTargets targets(CutPlan plan) =>
    (CameraTargetPlanner(const Duration(milliseconds: 700), .02)
          ..add(event('cursor', 100, x: 800, y: 800))
          ..add(event('cursor', 300, x: 810, y: 810))
          ..add(event('key', 400))
          ..add(event('cursor', 600, visible: false))
          ..add(event('click', 2500, x: 100))
          ..add(event('cursor', 4900, width: 500, height: 500, x: 100, y: 100)))
        .finish(plan);

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'completed camera placement recovers frozen targets without later activity $language',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'spawnalpha-camera-clear-recovery-',
        );
        final disk = FailingStore();
        final savedLibrary = ScriptLibrary(disk), inspector = FakeInspector();
        final renderer = FakeRenderer(inspector);
        final store = VideoExportStore(
          Directory('${root.path}/exports'),
          savedLibrary,
          inspector,
        );
        final job = ExportProcessor(
          renderer,
          store,
          CleanCutStore(Directory('${root.path}/cuts'), savedLibrary),
          (_) async => null,
        );
        try {
          final source = File('${root.path}/generated.mp4');
          await source.writeAsString('generated original');
          final activity = await activityFor(source);
          final take = Take(
            path: source.path,
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 4),
            mode: TakeMode.both,
            cameraPath: '${root.path}/camera.mp4',
            activityPath: activity.path,
          );
          final doc = ScriptDocument.create(
            text: '',
            language: language,
          ).copyWith(takes: [take]);
          await savedLibrary.save(doc);
          renderer.deferred = Completer<void>();
          final result = job.export(doc, take, VideoFormat.feed);
          await renderer.started.future;
          final expected = renderer.request!.cameraTargets!.toJson();
          disk.fail = true;
          renderer.deferred!.complete();
          expect(await result, isNull);
          final journal = (await store.pending.list().toList())
              .whereType<File>()
              .single;
          final encoded =
              jsonDecode(await journal.readAsString()) as Map<String, Object?>;
          final bad = jsonDecode(jsonEncode(encoded)) as Map<String, Object?>;
          (((bad['cameraTargets']! as Map)['targets']! as List).single
                  as Map)['endUs'] =
              5000000;
          await journal.writeAsString(jsonEncode(bad));
          await activity.delete();
          disk.fail = false;
          expect(await store.recover(), 0);
          final private =
              jsonDecode(jsonEncode(encoded)) as Map<String, Object?>;
          (private['cameraTargets']! as Map)['text'] = 'unapproved';
          await journal.writeAsString(jsonEncode(private));
          expect(await store.recover(), 0);
          await journal.writeAsString(jsonEncode(encoded));
          expect(await store.recover(), 1);
          final video = (await store.load(
            savedLibrary.byId(doc.id)!.takes.single,
          )).single;
          expect(video.cameraClear, isTrue);
          final metadata =
              jsonDecode(await store.file(video, 'json').readAsString()) as Map;
          expect(metadata['cameraTargets'], expected);
          expect(jsonEncode(metadata), isNot(contains(source.path)));
          expect(jsonEncode(metadata), isNot(contains(activity.path)));
          expect(await source.readAsString(), 'generated original');
        } finally {
          job.dispose();
          savedLibrary.dispose();
          await root.delete(recursive: true);
        }
      },
    );
    test(
      'camera pointer windows expire, coalesce, retain/reorder and clamp $language',
      () {
        final result = targets(
          cut(language, [span(2000, 3000), span(0, 700), span(4500, 5000)]),
        );
        expect(result.targets.map((t) => t.start.inMilliseconds), [
          500,
          1100,
          2100,
        ]);
        expect(result.targets.map((t) => t.end.inMilliseconds), [
          1000,
          1600,
          2200,
        ]);
        expect(result.targets.map((t) => t.x), [.1, .8, .2]);
        expect(result.targets.map((t) => t.width), [1000, 1000, 500]);
        expect(
          CameraTargets.fromJson(result.toJson()).toJson(),
          result.toJson(),
        );
        expect(() => result.targets.clear(), throwsUnsupportedError);
      },
    );
    test(
      'camera targets keep continuous split clocks and retained partial windows $language',
      () {
        final whole = targets(cut(language, [span(0, 5000)]));
        expect(
          targets(cut(language, [span(0, 400), span(400, 5000)])).toJson(),
          whole.toJson(),
        );
        final part = targets(cut(language, [span(200, 500)]));
        expect(part.targets.single.start, Duration.zero);
        expect(part.targets.single.end, const Duration(milliseconds: 300));
      },
    );
    test(
      'saved Both take can change placement later independently of other effects $language',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'spawnalpha-camera-clear-',
        );
        var library = ScriptLibrary(
          FileScriptStore(Directory('${root.path}/scripts')),
        );
        ExportProcessor? job;
        try {
          final source = File('${root.path}/generated.mp4');
          await source.writeAsString('generated original');
          final activity = await activityFor(source);
          final originalActivity = await activity.readAsString();
          final take = Take(
            path: source.path,
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 4),
            mode: TakeMode.both,
            cameraPath: '${root.path}/generated-camera.mp4',
            activityPath: activity.path,
          );
          await File(take.cameraPath!).writeAsString('generated camera');
          final doc = ScriptDocument.create(
            text: '',
            language: language,
          ).copyWith(takes: [take]);
          await library.save(doc);
          final files = <String, String>{};
          for (final option in ['on', 'off', 'hidden', 'missing']) {
            library.dispose();
            library = ScriptLibrary(
              FileScriptStore(Directory('${root.path}/scripts')),
            );
            await library.load();
            final reopened = library.byId(doc.id)!;
            if (option == 'missing') await activity.delete();
            final renderer = FakeRenderer(FakeInspector());
            final store = VideoExportStore(
              Directory('${root.path}/exports'),
              library,
              renderer.inspector,
            );
            job = ExportProcessor(
              renderer,
              store,
              CleanCutStore(Directory('${root.path}/cuts'), library),
              (_) async => null,
            );
            final video = (await job.export(
              reopened,
              reopened.takes.single,
              VideoFormat.portrait,
              camera: option != 'hidden',
              cameraClear: option != 'off',
              autoZoom: false,
              clickHighlights: false,
              showShortcuts: false,
              cameraPunch: false,
            ))!;
            expect(video.cameraClear, option == 'on');
            expect(renderer.request!.cameraClear, option == 'on');
            expect(renderer.request!.screenZooms!.count, 0);
            expect(renderer.request!.screenClicks, isNull);
            expect(renderer.request!.screenShortcuts, isNull);
            expect(
              renderer.request!.toJson().containsKey('cameraTargets'),
              option == 'on',
            );
            final metadata = jsonDecode(
              await store.file(video, 'json').readAsString(),
            ) as Map<String, Object?>;
            if (option == 'on') {
              expect(
                (metadata['cameraTargets']! as Map)['targets'],
                hasLength(1),
              );
            }
            for (final entry in files.entries) {
              expect(await File(entry.key).readAsString(), entry.value);
            }
            for (final extension in ['mp4', 'json']) {
              final file = store.file(video, extension);
              files[file.path] = await file.readAsString();
            }
            expect(await source.readAsString(), 'generated original');
            expect(
              await File(take.cameraPath!).readAsString(),
              'generated camera',
            );
            if (option != 'missing') {
              expect(await activity.readAsString(), originalActivity);
            }
            job.dispose();
            job = null;
          }
          final store = VideoExportStore(
            Directory('${root.path}/exports'),
            library,
            FakeInspector(),
          );
          expect(
            await store.load(library.byId(doc.id)!.takes.single),
            hasLength(4),
          );
        } finally {
          job?.dispose();
          library.dispose();
          await root.delete(recursive: true);
        }
      },
    );
  }
  test('camera targets reject private payloads, overlap, late clocks and missing camera', () {
    final t = CameraTarget(
      start: Duration.zero,
      end: const Duration(seconds: 1),
      x: .8,
      y: .8,
      width: 640,
      height: 360,
    );
    for (final bad in [
      {...t.toJson(), 'x': double.nan},
      {...t.toJson(), 'height': 0},
      {...t.toJson(), 'endUs': 0},
      {...t.toJson(), 'text': 'private'},
    ]) {
      expect(() => CameraTarget.fromJson(bad), throwsFormatException);
    }
    expect(() => CameraTargets([t, t]), throwsFormatException);
    final track = CameraTargets([t]);
    expect(
      () => track.validateClock(cut(ScriptLanguage.en, [span(0, 500)])),
      throwsFormatException,
    );
    expect(
      () => VideoRenderRequest(
        source: 'generated',
        output: 'new',
        plan: cut(ScriptLanguage.en, [span(0, 5000)]),
        format: VideoFormat.landscape,
        cameraClear: true,
        cameraTargets: track,
      ),
      throwsFormatException,
    );
    expect(
      () => VideoExport(
        id: 'new',
        format: VideoFormat.landscape,
        duration: const Duration(seconds: 5),
        createdAt: DateTime(2026),
        cameraClear: true,
      ),
      throwsArgumentError,
    );
    final legacy = VideoExport(
      id: 'old',
      format: VideoFormat.landscape,
      duration: const Duration(seconds: 5),
      createdAt: DateTime(2026),
    ).toJson()..remove('cameraClear');
    expect(VideoExport.fromJson(legacy).cameraClear, isFalse);
  });
}

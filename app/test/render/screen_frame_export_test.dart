import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';

import 'export_processor_test.dart' show FakeRenderer;
import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;

void main() {
  for (final language in ScriptLanguage.values) {
    for (final mode in TakeMode.values) {
      for (final enabled in [false, true]) {
        test(
          'screen frame without activity $language $mode $enabled',
          () async {
            final root = await Directory.systemTemp.createTemp(
              'spawnalpha-frame-',
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
              await source.writeAsString('generated original');
              final take = Take(
                path: source.path,
                duration: const Duration(seconds: 5),
                mode: mode,
                recordedAt: DateTime(2026),
              );
              final script = ScriptDocument.create(language: language)
                  .copyWith(takes: [take]);
              await library.save(script);
              final video = (await job.export(
                script,
                take,
                VideoFormat.portrait,
                screenFrame: enabled,
              ))!;
              final expected = enabled && mode != TakeMode.camera;
              expect(video.screenFrame, expected);
              expect(renderer.request!.screenFrame, expected);
              expect(renderer.request!.plan.duration, take.duration);
              final json = renderer.request!.toJson();
              if (expected) {
                final frame = json['screenFrame'] as Map;
                expect(frame['inset'], .06);
                expect(frame['radius'], 12);
                expect((frame['shadows'] as List).length, 2);
              } else {
                expect(json.containsKey('screenFrame'), isFalse);
              }
              final portable = jsonDecode(
                await store.file(video, 'json').readAsString(),
              ) as Map;
              expect((portable['video'] as Map)['screenFrame'], expected);
              expect(jsonEncode(portable), isNot(contains(source.path)));
              expect(
                (await store.load(library.byId(script.id)!.takes.single))
                    .single
                    .screenFrame,
                expected,
              );
              expect(await source.readAsString(), 'generated original');
            } finally {
              job.dispose();
              library.dispose();
              await root.delete(recursive: true);
            }
          },
        );
      }
    }
  }
  test('old frame choice compatibility and malformed values', () {
    final video = VideoExport(
      id: 'generated',
      format: VideoFormat.feed,
      duration: const Duration(seconds: 1),
      createdAt: DateTime(2026),
      screenFrame: true,
    );
    expect(VideoExport.fromJson(video.toJson()).screenFrame, isTrue);
    expect(
      VideoExport.fromJson(video.toJson()..remove('screenFrame')).screenFrame,
      isFalse,
    );
    expect(
      () => VideoExport.fromJson({...video.toJson(), 'screenFrame': 'yes'}),
      throwsFormatException,
    );
  });
  test('completed frame choice recovers without re-reading activity', () async {
    final root = await Directory.systemTemp.createTemp(
      'spawnalpha-frame-recover-',
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
      final take = Take(
        path: '${root.path}/generated.mp4',
        duration: const Duration(seconds: 5),
        mode: TakeMode.screen,
        recordedAt: DateTime(2026),
      );
      final script = ScriptDocument.create().copyWith(takes: [take]);
      await library.save(script);
      renderer.deferred = Completer<void>();
      final future = job.export(script, take, VideoFormat.feed);
      await renderer.started.future;
      disk.fail = true;
      renderer.deferred!.complete();
      expect(await future, isNull);
      disk.fail = false;
      expect(await store.recover(), 1);
      expect(await store.recover(), 0);
      expect(
        (await store.load(library.byId(script.id)!.takes.single))
            .single
            .screenFrame,
        isTrue,
      );
    } finally {
      job.dispose();
      library.dispose();
      await root.delete(recursive: true);
    }
  });
}

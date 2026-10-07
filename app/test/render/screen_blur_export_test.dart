import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';

import 'screen_zoom_export_test.dart' show activityFor;
import 'export_processor_test.dart' show FakeRenderer;
import '../storage/screen_take_store_test.dart' show FakeInspector;

void main() {
  for (final language in ScriptLanguage.values) {
    for (final mode in [TakeMode.screen, TakeMode.both, TakeMode.camera]) {
      test(
        'screen blur changes later independently and preserves versions $language $mode',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'spawnalpha-screen-blur-',
          );
          var library = ScriptLibrary(
            FileScriptStore(Directory('${root.path}/scripts')),
          );
          ExportProcessor? job;
          try {
            final source = File('${root.path}/generated.mp4');
            await source.writeAsString('generated original');
            final activity = await activityFor(source);
            final before = await activity.readAsString();
            final take = Take(
              path: source.path,
              duration: const Duration(seconds: 4),
              recordedAt: DateTime(2026),
              mode: mode,
              cameraPath: mode == TakeMode.both
                  ? '${root.path}/camera.mp4'
                  : null,
              activityPath: activity.path,
            );
            final doc = ScriptDocument.create(
              language: language,
              text: '',
            ).copyWith(takes: [take]);
            await library.save(doc);
            final saved = <String, String>{};
            for (final option in ['on', 'off', 'no-zoom']) {
              library.dispose();
              library = ScriptLibrary(
                FileScriptStore(Directory('${root.path}/scripts')),
              );
              await library.load();
              final current = library.byId(doc.id)!;
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
                current,
                current.takes.single,
                VideoFormat.feed,
                motionBlur: option != 'off',
                autoZoom: option != 'no-zoom',
                cameraClear: false,
              ))!;
              final enabled = option == 'on' && mode != TakeMode.camera;
              expect(video.motionBlur, enabled);
              expect(renderer.request!.motionBlur, enabled);
              expect(
                renderer.request!.toJson()['screenBlur'],
                enabled
                    ? {'maximum': 6.0, 'minimum': .5, 'shutterUs': 16000}
                    : null,
              );
              for (final entry in saved.entries) {
                expect(await File(entry.key).readAsString(), entry.value);
              }
              for (final extension in ['mp4', 'json']) {
                final file = store.file(video, extension);
                saved[file.path] = await file.readAsString();
              }
              final metadata = jsonDecode(
                await store.file(video, 'json').readAsString(),
              ) as Map;
              expect((metadata['video'] as Map)['motionBlur'], enabled);
              expect(await source.readAsString(), 'generated original');
              expect(await activity.readAsString(), before);
              expect(video.duration, take.duration);
              // The independent click and frame choices remain enabled on screen modes.
              expect(video.clickCount > 0, mode != TakeMode.camera);
              expect(video.screenFrame, mode != TakeMode.camera);
              job.dispose();
              job = null;
            }
            final history = await VideoExportStore(
              Directory('${root.path}/exports'),
              library,
              FakeInspector(),
            ).load(library.byId(doc.id)!.takes.single);
            expect(history, hasLength(3));
            expect(
              history.where((v) => v.motionBlur).length,
              mode == TakeMode.camera ? 0 : 1,
            );
          } finally {
            job?.dispose();
            library.dispose();
            await root.delete(recursive: true);
          }
        },
      );
    }
  }
  test('screen blur request and history reject missing zooms and malformed choices', () {
    final plan = CutPlan(
      takeId: 'generated',
      language: ScriptLanguage.en,
      sourceDuration: const Duration(seconds: 4),
      ranges: [
        SourceRange(start: Duration.zero, end: const Duration(seconds: 4)),
      ],
    );
    expect(
      () => VideoRenderRequest(
        source: 'generated',
        output: 'new',
        plan: plan,
        format: VideoFormat.landscape,
        motionBlur: true,
      ),
      throwsFormatException,
    );
    final old = VideoExport(
      id: 'generated',
      format: VideoFormat.landscape,
      duration: plan.duration,
      createdAt: DateTime(2026),
    ).toJson()..remove('motionBlur');
    expect(VideoExport.fromJson(old).motionBlur, isFalse);
    expect(
      () => VideoExport.fromJson({...old, 'motionBlur': true}),
      throwsFormatException,
    );
    expect(
      () => VideoExport.fromJson({...old, 'motionBlur': 'yes'}),
      throwsFormatException,
    );
  });
}

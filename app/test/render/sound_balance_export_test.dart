import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
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
      test(
        'saved sound balance can change without changing earlier versions $language $mode',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'spawnalpha-sound-',
          );
          var library = ScriptLibrary(
            FileScriptStore(Directory('${root.path}/scripts')),
          );
          ExportProcessor? job;
          try {
            final source = File('${root.path}/source.mp4');
            await source.writeAsString('unchanged generated sound');
            final take = Take(
              path: source.path,
              recordedAt: DateTime(2026),
              duration: const Duration(seconds: 4),
              mode: mode,
            );
            final document = ScriptDocument.create(language: language)
                .copyWith(takes: [take]);
            await library.save(document);
            final saved = <String, String>{};
            for (final balance in [false, true, false]) {
              library.dispose();
              library = ScriptLibrary(
                FileScriptStore(Directory('${root.path}/scripts')),
              );
              await library.load();
              final inspector = FakeInspector();
              final renderer = FakeRenderer(inspector);
              final store = VideoExportStore(
                Directory('${root.path}/exports'),
                library,
                inspector,
              );
              job = ExportProcessor(
                renderer,
                store,
                CleanCutStore(Directory('${root.path}/cuts'), library),
                (_) async => null,
              );
              final current = library.byId(document.id)!;
              final video = (await job.export(
                current,
                current.takes.single,
                VideoFormat.feed,
                balanceSound: balance,
              ))!;
              expect(video.balanceSound, balance);
              expect(renderer.request!.balanceSound, balance);
              expect(
                renderer.request!.toJson()['soundBalance'],
                balance
                    ? {'target': -14.0, 'ceiling': -2.0, 'maximumBoost': 12.0}
                    : null,
              );
              expect(video.duration, take.duration);
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
              expect((metadata['video'] as Map)['balanceSound'], balance);
              expect(await source.readAsString(), 'unchanged generated sound');
              job.dispose();
              job = null;
            }
            final history = await VideoExportStore(
              Directory('${root.path}/exports'),
              library,
              FakeInspector(),
            ).load(library.byId(document.id)!.takes.single);
            expect(history, hasLength(3));
            expect(history.where((v) => v.balanceSound), hasLength(1));
          } finally {
            job?.dispose();
            library.dispose();
            await root.delete(recursive: true);
          }
        },
      );
    }
  }
  for (final kind in ['silent', 'short', 'disabled', 'recovery']) {
    test('sound balance protects $kind exports', () async {
      final root = await Directory.systemTemp.createTemp('spawnalpha-sound-');
      final disk = FailingStore();
      // A failed final attachment can be retried from the completed local journal.
      final active = ScriptLibrary(disk), inspector = FakeInspector();
      final renderer = FakeRenderer(inspector);
      final store = VideoExportStore(
        Directory('${root.path}/exports'),
        active,
        inspector,
      );
      final job = ExportProcessor(
        renderer,
        store,
        CleanCutStore(Directory('${root.path}/cuts'), active),
        (_) async => null,
      );
      try {
        final take = Take(
          path: '${root.path}/source.mp4',
          recordedAt: DateTime(2026),
          duration: Duration(milliseconds: kind == 'short' ? 399 : 4000),
        );
        inspector.byPath[take.path] = RecordingInfo(
          readable: true,
          hasAudio: kind != 'silent',
          width: 640,
          height: 360,
          duration: take.duration,
        );
        final document = ScriptDocument.create().copyWith(takes: [take]);
        await active.save(document);
        if (kind == 'recovery') disk.fail = true;
        final video = await job.export(
          document,
          take,
          VideoFormat.landscape,
          balanceSound: kind != 'disabled',
        );
        expect(renderer.request!.balanceSound, kind == 'recovery');
        if (kind == 'recovery') {
          expect(video, isNull);
          disk.fail = false;
          expect(await store.recover(), 1);
          expect(
            (await store.load(active.byId(document.id)!.takes.single))
                .single
                .balanceSound,
            isTrue,
          );
        } else {
          expect(video!.balanceSound, isFalse);
        }
        if (kind == 'short' || kind == 'disabled') {
          expect(inspector.inspected.where((p) => p == take.path), isEmpty);
        }
      } finally {
        job.dispose();
        active.dispose();
        await root.delete(recursive: true);
      }
    });
  }
  test(
    'sound history is backward compatible and rejects malformed choices',
    () {
      final video = VideoExport(
        id: 'generated',
        format: VideoFormat.landscape,
        duration: const Duration(seconds: 4),
        createdAt: DateTime(2026),
        balanceSound: true,
      );
      expect(VideoExport.fromJson(video.toJson()).balanceSound, isTrue);
      expect(
        VideoExport.fromJson(video.toJson()..remove('balanceSound'))
            .balanceSound,
        isFalse,
      );
      for (final invalid in ['yes', 1, <String, Object?>{}]) {
        expect(
          () =>
              VideoExport.fromJson(video.toJson()..['balanceSound'] = invalid),
          throwsFormatException,
        );
      }
    },
  );
}

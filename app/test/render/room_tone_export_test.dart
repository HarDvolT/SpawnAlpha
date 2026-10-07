import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';

import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;
import 'export_processor_test.dart' show FakeRenderer;
import 'room_tone_test.dart' show range, words;

void main() {
  for (final language in ScriptLanguage.values) {
    for (final kind in [
      'normal',
      'Notes',
      'missing',
      'disabled',
      'recovery',
      'restored',
    ]) {
      test(
        'room tone preserves saved versions and boundaries $language $kind',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'spawnalpha-room-',
          );
          final disk = FailingStore(), inspector = FakeInspector();
          final library = ScriptLibrary(disk),
              renderer = FakeRenderer(inspector);
          final store = VideoExportStore(
            Directory('${root.path}/exports'),
            library,
            inspector,
          );
          final cuts = CleanCutStore(Directory('${root.path}/cuts'), library);
          final source = File('${root.path}/source.mp4');
          await source.writeAsString('original generated room tone');
          final take = Take(
            path: source.path,
            wordsPath: '${source.path}.words.json',
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 4),
          );
          inspector.byPath[source.path] = RecordingInfo(
            readable: true,
            hasAudio: true,
            width: 640,
            height: 360,
            duration: take.duration,
          );
          final document = ScriptDocument.create(
            language: language,
            recordingAid: kind == 'Notes'
                ? RecordingAid.notes
                : RecordingAid.script,
          ).copyWith(takes: [take]);
          await library.save(document);
          final clean = CleanPlan(
            takeId: 'generated',
            language: language,
            sourceDuration: take.duration,
            changes: [
              CutChange(
                id: 'quiet-0',
                range: range(1400, 2800),
                enabled: kind != 'restored',
              ),
            ],
          );
          await cuts.save(document.id, take, clean);
          final saved = SavedTranscript(
            sourcePath: source.path,
            transcript: words(language),
            snapshot: document,
            quiet: kind == 'missing' ? [] : [range(0, 900)],
          );
          final job = ExportProcessor(
            renderer,
            store,
            cuts,
            (_) async => saved,
          );
          try {
            final previous = <String, String>{};
            for (final enabled in [false, true, false]) {
              if (kind == 'recovery' && enabled) disk.fail = true;
              final current = library.byId(document.id)!;
              final result = await job.export(
                current,
                current.takes.single,
                VideoFormat.feed,
                clean: clean,
                roomToneJoins: enabled,
                softAudioJoins: kind != 'disabled',
              );
              final wanted =
                  enabled &&
                  !['missing', 'disabled', 'restored'].contains(kind);
              expect(renderer.request!.roomTone != null, wanted);
              if (wanted) {
                expect(renderer.request!.toJson()['roomTone'], {
                  'startUs': 0,
                  'endUs': 100000,
                });
              }
              if (kind == 'recovery' && enabled) {
                expect(result, isNull);
                disk.fail = false;
                expect(await store.recover(), 1);
              }
              final video =
                  result ??
                  (await store.load(library.byId(document.id)!.takes.single))
                      .first;
              expect(video.roomTone != null, wanted);
              expect(
                video.duration,
                Duration(milliseconds: kind == 'restored' ? 4000 : 2600),
              );
              final metadata = jsonDecode(
                await store.file(video, 'json').readAsString(),
              ) as Map;
              expect(
                (metadata['video'] as Map)['roomTone'],
                wanted ? {'startUs': 0, 'endUs': 100000} : null,
              );
              for (final entry in previous.entries) {
                expect(await File(entry.key).readAsString(), entry.value);
              }
              for (final ext in ['mp4', 'json', 'srt', 'vtt']) {
                final file = store.file(video, ext);
                previous[file.path] = await file.readAsString();
              }
              expect(
                await source.readAsString(),
                'original generated room tone',
              );
            }
            final history = await store.load(
              library.byId(document.id)!.takes.single,
            );
            expect(history, hasLength(3));
            expect(
              history.where((v) => v.roomTone != null),
              hasLength(
                ['missing', 'disabled', 'restored'].contains(kind) ? 0 : 1,
              ),
            );
            expect(
              VideoExport.fromJson(history.first.toJson()..remove('roomTone'))
                  .roomTone,
              isNull,
            );
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

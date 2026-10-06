import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';

import '../cut/clean_plan_test.dart' show cleanFixture, gap;
import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;

class FakeRenderer implements VideoRenderer {
  FakeRenderer(this.inspector);
  final FakeInspector inspector;
  final started = Completer<void>();
  Completer<void>? deferred;
  VideoRenderRequest? request;
  bool fail = false;
  @override
  bool get supported => true;
  @override
  Future<void> render(
    VideoRenderRequest request,
    void Function(double) progress,
  ) async {
    this.request = request;
    if (!started.isCompleted) started.complete();
    if (deferred != null) await deferred!.future;
    if (fail) throw StateError('Generated render failure');
    await File(request.output).writeAsString('generated video bytes');
    inspector.info = RecordingInfo(
      readable: true,
      width: request.format.width,
      height: request.format.height,
      duration: request.plan.duration,
    );
    progress(1);
  }

  @override
  Future<void> cancel() async {
    if (deferred != null && !deferred!.isCompleted) {
      deferred!.completeError(const RenderCancelled());
    }
  }
}

void main() {
  late Directory root;
  late FailingStore disk;
  late ScriptLibrary library;
  late FakeInspector inspector;
  late FakeRenderer renderer;
  late VideoExportStore store;
  late CleanCutStore cuts;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('spawnalpha-exports-');
    disk = FailingStore();
    library = ScriptLibrary(disk);
    inspector = FakeInspector();
    renderer = FakeRenderer(inspector);
    store = VideoExportStore(
      Directory('${root.path}/exports'),
      library,
      inspector,
    );
    cuts = CleanCutStore(Directory('${root.path}/cuts'), library);
  });
  tearDown(() async {
    library.dispose();
    await root.delete(recursive: true);
  });
  for (final language in ScriptLanguage.values) {
    test(
      'exports frozen actual words/cut and preserves later edits $language',
      () async {
        final transcript = cleanFixture(language);
        final original = File('${root.path}/original.mp4');
        await original.writeAsString('original unchanged');
        final take = Take(
          path: original.path,
          recordedAt: DateTime(2026),
          duration: transcript.duration,
          wordsPath: '${root.path}/words.json',
        );
        final script = ScriptDocument.create(
          language: language,
          text: transcript.words.map((w) => w.text).join(' '),
        ).copyWith(recordingAid: RecordingAid.notes, takes: [take]);
        await library.save(script);
        final spoken = SavedTranscript(
          sourcePath: take.path,
          transcript: transcript,
          snapshot: script,
          quiet: [gap()],
        );
        final clean = await cuts.create(script, take, spoken);
        final savedTake = library.byId(script.id)!.takes.single;
        final job = ExportProcessor(renderer, store, cuts, (_) async => spoken);
        renderer.deferred = Completer<void>();
        final result = job.export(
          script,
          savedTake,
          VideoFormat.portrait,
          clean: clean,
        );
        await renderer.started.future;
        await library.save(library.byId(script.id)!.withText('Later edit'));
        renderer.deferred!.complete();
        final video = (await result)!;
        expect(job.phase, ExportPhase.done);
        expect(video.duration, lessThan(take.duration));
        expect(renderer.request!.plan.ranges.length, greaterThan(1));
        expect(await original.readAsString(), 'original unchanged');
        expect(library.byId(script.id)!.text, 'Later edit');
        final captions = await store.file(video, 'srt').readAsString();
        for (final word in transcript.words) {
          expect(captions, contains(word.text));
        }
        expect(
          await store.file(video, 'vtt').readAsString(),
          startsWith('WEBVTT'),
        );
        final portable =
            jsonDecode(await store.file(video, 'json').readAsString()) as Map;
        expect((portable['video'] as Map).keys, isNot(contains('wordsPath')));
        expect((portable['video'] as Map).keys, isNot(contains('cutPath')));
        expect(jsonEncode(portable), isNot(contains(root.path)));
        final reload = ScriptLibrary(disk);
        await reload.load();
        expect(
          (await store.load(reload.byId(script.id)!.takes.single)).single.id,
          video.id,
        );
        expect(
          library
              .byId(script.id)!
              .takes
              .single
              .withWords('new words')
              .exportsPath,
          isNotNull,
        );
        reload.dispose();
        job.dispose();
      },
    );
  }
  test(
    'completed export survives failed library save and recovers once',
    () async {
      final take = Take(
        path: '${root.path}/original.mp4',
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 4),
      );
      final script = ScriptDocument.create().copyWith(takes: [take]);
      await library.save(script);
      final job = ExportProcessor(renderer, store, cuts, (_) async => null);
      renderer.deferred = Completer<void>();
      final result = job.export(script, take, VideoFormat.landscape);
      await renderer.started.future;
      disk.fail = true;
      renderer.deferred!.complete();
      expect(await result, isNull);
      expect(job.phase, ExportPhase.failed);
      expect(await File(renderer.request!.output).exists(), isTrue);
      expect((await store.pending.list().toList()).whereType<File>().length, 1);
      disk.fail = false;
      expect(await store.recover(), 1);
      expect(await store.recover(), 0);
      expect(
        (await store.load(library.byId(script.id)!.takes.single)).length,
        1,
      );
      job.dispose();
    },
  );
  test(
    'caption save failure preserves verified video and recovers captions',
    () async {
      final transcript = cleanFixture(ScriptLanguage.ar);
      final take = Take(
        path: '${root.path}/original.mp4',
        recordedAt: DateTime(2026),
        duration: transcript.duration,
        wordsPath: '${root.path}/words.json',
      );
      final script = ScriptDocument.create(language: ScriptLanguage.ar)
          .copyWith(takes: [take]);
      await library.save(script);
      final spoken = SavedTranscript(
        sourcePath: take.path,
        transcript: transcript,
        snapshot: script,
      );
      final job = ExportProcessor(renderer, store, cuts, (_) async => spoken);
      renderer.deferred = Completer<void>();
      final result = job.export(script, take, VideoFormat.landscape);
      await renderer.started.future;
      final blocked = Directory(
        renderer.request!.output.replaceFirst(RegExp(r'\.mp4$'), '.srt'),
      );
      await blocked.create();
      renderer.deferred!.complete();
      expect(await result, isNull);
      expect(job.phase, ExportPhase.failed);
      expect(await File(renderer.request!.output).exists(), isTrue);
      await blocked.delete();
      expect(await store.recover(), 1);
      expect(await store.recover(), 0);
      final video = (await store.load(library.byId(script.id)!.takes.single))
          .single;
      final captions = await store.file(video, 'srt').readAsString();
      for (final word in transcript.words) {
        expect(captions, contains(word.text));
      }
      expect(await store.file(video, 'vtt').exists(), isTrue);
      job.dispose();
    },
  );
  test(
    'cancel never attaches output; stale cut/words never start render',
    () async {
      final take = Take(
        path: '${root.path}/original.mp4',
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 4),
      );
      final script = ScriptDocument.create().copyWith(takes: [take]);
      await library.save(script);
      final job = ExportProcessor(renderer, store, cuts, (_) async => null);
      renderer.deferred = Completer<void>();
      final result = job.export(script, take, VideoFormat.feed);
      await renderer.started.future;
      await job.cancel();
      expect(await result, isNull);
      expect(job.phase, ExportPhase.cancelled);
      expect(library.byId(script.id)!.takes.single.exportsPath, isNull);
      expect(await File(renderer.request!.output).exists(), isFalse);
      await library.save(script.copyWith(takes: [take.withWords('new words')]));
      expect(await job.export(script, take, VideoFormat.landscape), isNull);
      expect(job.phase, ExportPhase.failed);
      job.dispose();
    },
  );
  test(
    'unfinished journal and external catalog never appear as finished video',
    () async {
      final take = Take(
        path: '${root.path}/original.mp4',
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 4),
      );
      final script = ScriptDocument.create().copyWith(takes: [take]);
      await library.save(script);
      final job = ExportProcessor(renderer, store, cuts, (_) async => null);
      renderer.fail = true;
      expect(await job.export(script, take, VideoFormat.landscape), isNull);
      expect(await store.recover(), 0);
      expect(
        await store.load(take.withExports('${root.path}/outside.json')),
        isEmpty,
      );
      job.dispose();
    },
  );
}

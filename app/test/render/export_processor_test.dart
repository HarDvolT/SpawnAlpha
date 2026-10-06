import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/model/caption_style.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/captions.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';

import '../cut/clean_plan_test.dart' show cleanFixture, gap;
import '../cut/filler_review_test.dart'
    show fillerFixture, fillerQuiet, fillerScript;
import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;
import '../cut/retake_review_test.dart'
    show retakeWords, retakeScript, retakeQuiet;

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
    for (final style in [
      CaptionStyle.cue,
      CaptionStyle.punch,
      CaptionStyle.karaoke,
    ]) {
      test(
        '$style export uses corrected cut words and remembers its style/Still choice $language',
        () async {
          final transcript = cleanFixture(language);
          final take = Take(
            path: '${root.path}/generated.mp4',
            recordedAt: DateTime(2026),
            duration: transcript.duration,
            wordsPath: '${root.path}/words.json',
          );
          final script = ScriptDocument.create(language: language)
              .copyWith(recordingAid: RecordingAid.notes, takes: [take]);
          await library.save(script);
          final spoken = SavedTranscript(
            sourcePath: take.path,
            transcript: transcript,
            snapshot: script,
            quiet: [gap()],
          );
          final clean = await cuts.create(script, take, spoken);
          final job = ExportProcessor(
            renderer,
            store,
            cuts,
            (_) async => spoken,
          );
          final video = (await job.export(
            script,
            library.byId(script.id)!.takes.single,
            VideoFormat.portrait,
            clean: clean,
            captionStyle: style,
            captionMotion: false,
            softAudioJoins: style != CaptionStyle.karaoke,
          ))!;
          final expected = captionsFromSpeech(
            speechOnCleanCut(transcript, clean),
          );
          final rendered = captionsFromSpeech(
            speechOnCleanCut(transcript, clean),
            punch: style == CaptionStyle.punch,
          );
          expect(renderer.request!.captionStyle, style);
          expect(renderer.request!.captionMotion, isFalse);
          expect(
            renderer.request!.softAudioJoins,
            style != CaptionStyle.karaoke,
          );
          expect(
            renderer.request!.toJson()['audioJoinFadeUs'],
            style == CaptionStyle.karaoke ? 0 : 20000,
          );
          expect(
            renderer.request!.captions
                .expand((c) => c.words)
                .map((w) => w.toJson()),
            rendered.expand((c) => c.words).map((w) => w.toJson()),
          );
          expect(
            await store.file(video, 'srt').readAsString(),
            subtitleText(expected),
          );
          expect(video.captionStyle, style);
          expect(video.captionMotion, isFalse);
          expect(video.softAudioJoins, style != CaptionStyle.karaoke);
          expect(
            (await store.load(library.byId(script.id)!.takes.single))
                .single
                .softAudioJoins,
            style != CaptionStyle.karaoke,
          );
          expect(
            (await store.load(library.byId(script.id)!.takes.single))
                .single
                .captionStyle,
            style,
          );
          final metadata =
              jsonDecode(await store.file(video, 'json').readAsString()) as Map;
          expect((metadata['video'] as Map)['captionStyle'], style.name);
          expect((metadata['video'] as Map)['captionMotion'], isFalse);
          expect(
            (metadata['video'] as Map)['softAudioJoins'],
            style != CaptionStyle.karaoke,
          );
          job.dispose();
        },
      );
    }
    test(
      'retake selection exports only the chosen words and retains restore/history $language',
      () async {
        final words = retakeWords(language), frozen = retakeScript(language);
        final original = File('${root.path}/original.mp4');
        await original.writeAsString('unchanged generated original');
        final take = Take(
          path: original.path,
          recordedAt: DateTime(2026),
          duration: words.duration,
          wordsPath: '${root.path}/words.json',
        );
        final script = frozen.copyWith(takes: [take]);
        await library.save(script);
        final spoken = SavedTranscript(
          sourcePath: take.path,
          transcript: words,
          snapshot: frozen,
          quiet: retakeQuiet(words),
          alignment: {'attemptCount': 2},
        );
        final plan = await cuts.create(script, take, spoken);
        final job = ExportProcessor(renderer, store, cuts, (_) async => spoken);
        final chosen = plan.restoreAll().withAttempt(plan.retakes.single.id, 1);
        await cuts.save(
          script.id,
          library.byId(script.id)!.takes.single,
          chosen,
        );
        final video = (await job.export(
          script,
          library.byId(script.id)!.takes.single,
          VideoFormat.landscape,
          clean: chosen,
        ))!;
        final captions = renderer.request!.captions;
        expect(
          captions.map((c) => c.text).join(' '),
          words.words.skip(3).map((w) => w.text).join(' '),
        );
        expect(
          captions.first.start,
          words.words[3].start -
              chosen.retakes.single.options.first.removal!.duration,
        );
        expect(video.duration, chosen.asCutPlan().duration);
        final srt = await store.file(video, 'srt').readAsString();
        expect(
          RegExp(RegExp.escape(words.words.first.text)).allMatches(srt),
          hasLength(1),
        );
        final restored = chosen.restoreAll();
        await cuts.save(
          script.id,
          library.byId(script.id)!.takes.single,
          restored,
        );
        final second = (await job.export(
          script,
          library.byId(script.id)!.takes.single,
          VideoFormat.portrait,
          clean: restored,
        ))!;
        expect(second.duration, words.duration);
        expect(
          RegExp(RegExp.escape(words.words.first.text))
              .allMatches(await store.file(second, 'srt').readAsString()),
          hasLength(2),
        );
        expect(await store.file(video, 'srt').readAsString(), srt);
        expect(
          (await store.load(library.byId(script.id)!.takes.single)),
          hasLength(2),
        );
        expect(await original.readAsString(), 'unchanged generated original');
        job.dispose();
      },
    );
    test(
      'chosen filler leaves both video captions and subtitles; original and restore stay complete $language',
      () async {
        final transcript = fillerFixture(language),
            frozen = fillerScript(fillerFixture(language), notes: true);
        final original = File('${root.path}/original.mp4');
        await original.writeAsString('unchanged original');
        final take = Take(
          path: original.path,
          recordedAt: DateTime(2026),
          duration: transcript.duration,
          wordsPath: '${root.path}/words.json',
        );
        final script = frozen.copyWith(takes: [take]);
        await library.save(script);
        final spoken = SavedTranscript(
          sourcePath: take.path,
          transcript: transcript,
          snapshot: frozen,
          quiet: fillerQuiet(transcript),
        );
        final plan = await cuts.create(script, take, spoken);
        final chosen = plan.withEnabled(plan.changes.single.id, true);
        await cuts.save(
          script.id,
          library.byId(script.id)!.takes.single,
          chosen,
        );
        final job = ExportProcessor(renderer, store, cuts, (_) async => spoken);
        final video = (await job.export(
          script,
          library.byId(script.id)!.takes.single,
          VideoFormat.landscape,
          clean: chosen,
        ))!;
        final text = renderer.request!.captions.map((c) => c.text).join(' ');
        expect(
          text,
          '${transcript.words.first.text} ${transcript.words.last.text}',
        );
        expect(
          await store.file(video, 'srt').readAsString(),
          isNot(contains(transcript.words[1].text)),
        );
        expect(video.duration, chosen.asCutPlan().duration);
        await cuts.save(
          script.id,
          library.byId(script.id)!.takes.single,
          chosen.restoreAll(),
        );
        final restored = (await job.export(
          script,
          library.byId(script.id)!.takes.single,
          VideoFormat.landscape,
          clean: chosen.restoreAll(),
        ))!;
        expect(
          await store.file(restored, 'srt').readAsString(),
          contains(transcript.words[1].text),
        );
        expect(
          (await store.load(library.byId(script.id)!.takes.single)),
          hasLength(2),
        );
        expect(await original.readAsString(), 'unchanged original');
        expect(transcript.words, hasLength(3));
        job.dispose();
      },
    );
    test(
      'captions off keeps subtitle files and saved history $language',
      () async {
        final transcript = cleanFixture(language);
        final take = Take(
          path: '${root.path}/original.mp4',
          recordedAt: DateTime(2026),
          duration: transcript.duration,
          wordsPath: '${root.path}/words.json',
        );
        final script = ScriptDocument.create(language: language)
            .copyWith(takes: [take]);
        await library.save(script);
        final spoken = SavedTranscript(
          sourcePath: take.path,
          transcript: transcript,
          snapshot: script,
        );
        final job = ExportProcessor(renderer, store, cuts, (_) async => spoken);
        final video = (await job.export(
          script,
          take,
          VideoFormat.landscape,
          burnedCaptions: false,
        ))!;
        expect(video.captions, isTrue);
        expect(video.burnedCaptions, isFalse);
        expect(renderer.request!.captions, isEmpty);
        expect(await store.file(video, 'srt').exists(), isTrue);
        expect(await store.file(video, 'vtt').exists(), isTrue);
        expect(
          (await store.load(library.byId(script.id)!.takes.single))
              .single
              .burnedCaptions,
          isFalse,
        );
        job.dispose();
      },
    );
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
        expect(video.burnedCaptions, isTrue);
        final captionClock = captionsFromSpeech(
          speechOnCut(transcript, clean.asCutPlan()),
        );
        expect(
          renderer.request!.captions.map((c) => c.text),
          captionClock.map((c) => c.text),
        );
        expect(
          renderer.request!.captions.map((c) => c.start),
          captionClock.map((c) => c.start),
        );
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
        expect((portable['video'] as Map)['burnedCaptions'], isTrue);
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

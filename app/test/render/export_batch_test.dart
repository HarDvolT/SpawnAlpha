import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/caption_style.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/export_batch.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/captions.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';

import '../cut/clean_plan_test.dart' show cleanFixture;
import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;
import 'export_processor_test.dart' show FakeRenderer;

class BatchRenderer extends FakeRenderer {
  BatchRenderer(super.inspector);
  final requests = <VideoRenderRequest>[];
  final held = Completer<void>();
  int active = 0, maximum = 0;
  int? failAt, holdAt;
  @override
  Future<void> render(
    VideoRenderRequest request,
    void Function(double) progress,
  ) async {
    requests.add(request);
    ++active;
    if (active > maximum) maximum = active;
    try {
      progress(.25);
      if (requests.length == holdAt) {
        deferred = Completer<void>();
        held.complete();
      } else {
        deferred = null;
      }
      this.fail = requests.length == failAt;
      await super.render(request, progress);
    } finally {
      --active;
    }
  }
}

void main() {
  late Directory root;
  late FailingStore disk;
  late ScriptLibrary library;
  late FakeInspector inspector;
  late BatchRenderer renderer;
  late VideoExportStore store;
  late CleanCutStore cuts;
  late ExportProcessor job;
  late ExportBatch batch;
  late ScriptDocument script;
  late Take take;
  SavedTranscript? spoken;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('spawnalpha-batch-');
    disk = FailingStore();
    library = ScriptLibrary(disk);
    inspector = FakeInspector();
    renderer = BatchRenderer(inspector);
    store = VideoExportStore(
      Directory('${root.path}/exports'),
      library,
      inspector,
    );
    cuts = CleanCutStore(Directory('${root.path}/cuts'), library);
    job = ExportProcessor(renderer, store, cuts, (_) async => spoken);
    batch = ExportBatch(job);
    spoken = null;
    final original = File('${root.path}/generated.mp4');
    await original.writeAsString('generated original bytes');
    take = Take(
      path: original.path,
      recordedAt: DateTime(2026),
      duration: const Duration(seconds: 4),
    );
    inspector.byPath[take.path] = const RecordingInfo(
      readable: true,
      hasAudio: true,
      width: 640,
      height: 360,
      duration: Duration(seconds: 4),
    );
    script = ScriptDocument.create().copyWith(takes: [take]);
    await library.save(script);
  });
  tearDown(() async {
    batch.dispose();
    job.dispose();
    library.dispose();
    await root.delete(recursive: true);
  });

  for (final language in ScriptLanguage.values) {
    test(
      'four formats retain the same frozen cut, captions, sound and history $language',
      () async {
        final words = cleanFixture(language);
        take = take.withWords('${root.path}/words.json');
        script =
            ScriptDocument.create(
              language: language,
              text: words.words.map((w) => w.text).join(' '),
            ).copyWith(
              recordingAid: language == ScriptLanguage.fr
                  ? RecordingAid.notes
                  : RecordingAid.script,
              takes: [take],
            );
        spoken = SavedTranscript(
          sourcePath: take.path,
          transcript: words,
          snapshot: script,
          quiet: [
            SourceRange(
              start: const Duration(milliseconds: 600),
              end: const Duration(milliseconds: 900),
            ),
          ],
        );
        await File(take.wordsPath!).writeAsString(jsonEncode(spoken!.toJson()));
        final originalWords = await File(take.wordsPath!).readAsString();
        await library.save(script);
        final clean = CleanPlan(
          takeId: 'generated',
          language: language,
          sourceDuration: take.duration,
          changes: [
            CutChange(
              id: 'quiet-0',
              range: SourceRange(
                start: const Duration(milliseconds: 1400),
                end: const Duration(milliseconds: 2800),
              ),
            ),
          ],
        );
        await cuts.save(script.id, take, clean);
        take = library.byId(script.id)!.takes.single;
        final progress = <double>[];
        batch.addListener(() {
          if (batch.busy) progress.add(batch.progress);
        });
        final formats = VideoFormat.values.toList();
        final pending = batch.run(
          script,
          take,
          formats,
          choices: ExportChoices(
            clean: clean,
            captionStyle: CaptionStyle.karaoke,
            captionMotion: false,
            balanceSound: true,
            softenSharpSound: true,
            reduceNoise: true,
            roomToneJoins: true,
          ),
        );
        formats.clear(); // The queue owns its copy from the first call.
        final videos = await pending;
        expect(videos.map((v) => v.format), VideoFormat.values);
        expect(renderer.maximum, 1);
        expect(renderer.requests, hasLength(4));
        expect(batch.busy, isFalse);
        expect(batch.problem, isNull);
        expect(batch.progress, 1);
        expect(progress.every((p) => p >= 0 && p <= 1), isTrue);
        expect(progress, contains(.3125)); // One saved + second render at 25%.
        final expected = captionsFromSpeech(speechOnCleanCut(words, clean));
        for (final video in videos) {
          expect(video.duration, clean.asCutPlan().duration);
          expect(video.wordsPath, take.wordsPath);
          expect(video.cutPath, take.cutPath);
          expect(video.captionStyle, CaptionStyle.karaoke);
          expect(video.captionMotion, isFalse);
          expect(
            video.balanceSound && video.softenSharpSound && video.reduceNoise,
            isTrue,
          );
          expect(video.roomTone, isNotNull);
          expect(
            await store.file(video, 'srt').readAsString(),
            subtitleText(expected),
          );
          expect(
            await store.file(video, 'vtt').readAsString(),
            subtitleText(expected, vtt: true),
          );
          final portable = VideoExport.fromJson(
            (jsonDecode(await store.file(video, 'json').readAsString())
                    as Map<String, Object?>)['video']
                as Map<String, Object?>,
          );
          expect(portable.format, video.format);
          expect(portable.captionStyle, video.captionStyle);
          expect(portable.roomTone!.toJson(), video.roomTone!.toJson());
          expect(portable.wordsPath, isNull);
          expect(portable.cutPath, isNull);
        }
        expect(
          (await store.load(library.byId(script.id)!.takes.single))
              .map((v) => v.id)
              .toSet(),
          videos.map((v) => v.id).toSet(),
        );
        expect(
          await File(take.path).readAsString(),
          'generated original bytes',
        );
        expect(await File(take.wordsPath!).readAsString(), originalWords);
        expect(() => batch.completed.clear(), throwsUnsupportedError);
      },
    );
  }

  test('cancel during a second render preserves the first video and skips the rest', () async {
    renderer.holdAt = 2;
    final pending = batch.run(script, take, VideoFormat.values);
    await renderer.held.future;
    expect(batch.saved, 1);
    expect(batch.current, VideoFormat.portrait);
    expect(batch.progress, .3125);
    await batch.cancel();
    final videos = await pending;
    expect(videos, hasLength(1));
    expect(renderer.requests, hasLength(2));
    expect(batch.cancelled, isTrue);
    expect(batch.problem, isNull);
    expect(await store.file(videos.single).exists(), isTrue);
    expect(
      await store.load(library.byId(script.id)!.takes.single),
      hasLength(1),
    );
    expect(await File(renderer.request!.output).exists(), isFalse);
  });

  test('failure stops the queue but keeps earlier videos playable', () async {
    renderer.failAt = 2;
    final videos = await batch.run(script, take, VideoFormat.values);
    expect(videos, hasLength(1));
    expect(renderer.requests, hasLength(2));
    expect(batch.problem, job.problem);
    expect(batch.problem, isNotNull);
    expect(batch.cancelled, isFalse);
    expect(
      await store.file(videos.single).readAsString(),
      'generated video bytes',
    );
    await store.recover();
    expect(
      await store.load(library.byId(script.id)!.takes.single),
      hasLength(1),
    );
  });

  test(
    'stop while attaching finishes that video and does not start the next',
    () async {
      job.addListener(() {
        if (job.phase == ExportPhase.saving) unawaited(batch.cancel());
      });
      final videos = await batch.run(script, take, VideoFormat.values);
      expect(videos, hasLength(1));
      expect(batch.cancelled, isTrue);
      expect(job.phase, ExportPhase.done);
      expect(renderer.requests, hasLength(1));
      expect(
        await store.load(library.byId(script.id)!.takes.single),
        hasLength(1),
      );
    },
  );

  test(
    'an interrupted attachment is recovered without starting remaining formats',
    () async {
      job.addListener(() {
        if (job.phase == ExportPhase.saving) disk.fail = true;
      });
      expect(await batch.run(script, take, VideoFormat.values), isEmpty);
      expect(batch.problem, isNotNull);
      expect(renderer.requests, hasLength(1));
      disk.fail = false;
      await store.recover();
      expect(
        await store.load(library.byId(script.id)!.takes.single),
        hasLength(1),
      );
      expect(renderer.requests, hasLength(1));
    },
  );

  for (final revision in ['words', 'cut']) {
    test(
      'a changed $revision revision stops before rendering the next format',
      () async {
        Future<void>? edit;
        batch.addListener(() {
          if (batch.saved == 1 && edit == null) {
            final current = library.byId(script.id)!;
            edit = library.save(
              current.copyWith(
                takes: [
                  revision == 'words'
                      ? current.takes.single.withWords(
                          '${root.path}/new-words.json',
                        )
                      : current.takes.single.withCut(
                          '${root.path}/new-cut.json',
                        ),
                ],
              ),
            );
          }
        });
        final videos = await batch.run(script, take, VideoFormat.values);
        await edit;
        expect(videos, hasLength(1));
        expect(renderer.requests, hasLength(1));
        expect(batch.problem, isNotNull);
        expect(await store.file(videos.single).exists(), isTrue);
      },
    );
  }

  test('repeated requests cannot overlap an active batch', () async {
    renderer.holdAt = 1;
    final first = batch.run(script, take, VideoFormat.values);
    await renderer.held.future;
    expect(await batch.run(script, take, [VideoFormat.feed]), isEmpty);
    expect(batch.total, 4);
    await batch.cancel();
    expect(await first, isEmpty);
    renderer.holdAt = null;
    expect(await batch.run(script, take, [VideoFormat.feed]), hasLength(1));
    expect(batch.cancelled, isFalse);
    expect(batch.problem, isNull);
  });

  test('a separate active export prevents starting a queue', () async {
    renderer.holdAt = 1;
    final other = job.export(script, take, VideoFormat.feed);
    await renderer.held.future;
    expect(await batch.run(script, take, VideoFormat.values), isEmpty);
    expect(batch.busy, isFalse);
    expect(batch.total, 0);
    await job.cancel();
    expect(await other, isNull);
  });

  test('empty or duplicated formats never create a native job', () async {
    await expectLater(batch.run(script, take, []), throwsArgumentError);
    await expectLater(
      batch.run(script, take, [VideoFormat.feed, VideoFormat.feed]),
      throwsArgumentError,
    );
    expect(batch.busy, isFalse);
    expect(renderer.requests, isEmpty);
    await batch.cancel();
  });

  test(
    'leaving the review cancels a render without notifying disposed listeners',
    () async {
      renderer.holdAt = 1;
      final pending = batch.run(script, take, VideoFormat.values);
      await renderer.held.future;
      batch.dispose();
      expect(await pending, isEmpty);
      expect(job.phase, ExportPhase.cancelled);
      await expectLater(
        batch.run(script, take, VideoFormat.values),
        throwsStateError,
      );
      // Replace the disposed object so tearDown can dispose exactly once.
      batch = ExportBatch(job);
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/camera_punches.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/caption_cues.dart';
import 'package:spawnalpha/src/transcription/captions.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

import 'export_processor_test.dart' show FakeRenderer;
import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;
import '../transcription/caption_cues_test.dart' show cueScript;

const policy = CameraPunchPolicy(
  minimum: Duration(seconds: 20),
  interval: Duration(seconds: 8),
  hold: Duration(milliseconds: 1400),
);
Duration ms(int value) => Duration(milliseconds: value);
SourceRange span(int from, int to) => SourceRange(start: ms(from), end: ms(to));
WordTranscript speech(ScriptDocument script) => WordTranscript(
  language: script.language,
  duration: ms(25000),
  words: [
    for (final start in [1000, 5000, 10000, 19000])
      for (var i = 0; i < 3; ++i)
        SpokenWord(
          text: script.tokens[i].text,
          start: ms(start + i * 400),
          end: ms(start + i * 400 + 200),
          confidence: .9,
        ),
  ],
);
CutPlan plan(WordTranscript source, [List<SourceRange>? ranges]) => CutPlan(
  takeId: 'generated',
  language: source.language,
  sourceDuration: source.duration,
  ranges: ranges ?? [SourceRange(start: Duration.zero, end: source.duration)],
);
List<Caption> phrases(
  WordTranscript source,
  CutPlan cut,
  ScriptDocument? frozen, {
  bool aligned = true,
}) {
  final words = <SpokenWord>[];
  var output = Duration.zero;
  for (final range in cut.ranges) {
    for (final w in source.words.where(
      (w) => w.start >= range.start && w.end <= range.end,
    )) {
      words.add(
        SpokenWord(
          text: w.text,
          start: output + w.start - range.start,
          end: output + w.end - range.start,
          confidence: w.confidence,
          recognizedText: w.recognizedText,
        ),
      );
    }
    output += range.duration;
  }
  final kept = WordTranscript(
    language: source.language,
    duration: cut.duration,
    words: words,
  );
  return captionsFromSpeech(
    kept,
    cues: captionCuesOnCut(
      source: source,
      kept: kept,
      plan: cut,
      snapshot: frozen,
      aligned: aligned,
    ),
  );
}

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'reopened saved take supports off/on/off without replacing earlier videos $language',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'spawnalpha-later-effects-',
        );
        final scripts = Directory('${root.path}/scripts'),
            inspector = FakeInspector();
        var library = ScriptLibrary(FileScriptStore(scripts));
        ExportProcessor? job;
        try {
          final original = File('${root.path}/generated.mp4');
          await original.writeAsString('generated original');
          final frozen = cueScript(language),
              words = speech(cueScript(language));
          final take = Take(
            path: original.path,
            recordedAt: DateTime(2026),
            duration: words.duration,
            wordsPath: '${root.path}/words.json',
          );
          final originalWords = jsonEncode(
            SavedTranscript(
              sourcePath: take.path,
              transcript: words,
              snapshot: frozen,
              alignment: {'attemptCount': 4},
            ).toJson(),
          );
          await File(take.wordsPath!).writeAsString(originalWords);
          final doc = frozen.copyWith(takes: [take]);
          await library.save(doc);
          final videos = <VideoExport>[];
          final priorFiles = <String, String>{};
          String? subtitles;
          for (final on in [false, true, false]) {
            // A fresh library/services instance simulates returning to the take later.
            library.dispose();
            library = ScriptLibrary(FileScriptStore(scripts));
            await library.load();
            final currentDoc = library.byId(doc.id)!;
            await library.save(currentDoc.withText('A later script edit.'));
            final reopened = library.byId(doc.id)!,
                currentTake = reopened.takes.single;
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
              (t) async => SavedTranscript.fromJson(
                jsonDecode(await File(t.wordsPath!).readAsString())
                    as Map<String, Object?>,
              ),
            );
            final video = (await job.export(
              reopened,
              currentTake,
              VideoFormat.portrait,
              cameraPunch: on,
            ))!;
            expect(video.cameraPunchCount, on ? 3 : 0);
            expect(renderer.request!.cameraPunches!.count, on ? 3 : 0);
            videos.add(video);
            final srt = await store.file(video, 'srt').readAsString();
            if (subtitles != null) expect(srt, subtitles);
            subtitles = srt;
            for (final entry in priorFiles.entries) {
              expect(await File(entry.key).readAsString(), entry.value);
            }
            for (final extension in ['mp4', 'json', 'srt', 'vtt']) {
              final file = store.file(video, extension);
              priorFiles[file.path] = await file.readAsString();
            }
            expect(
              (await store.load(library.byId(doc.id)!.takes.single)).length,
              videos.length,
            );
            expect(await original.readAsString(), 'generated original');
            expect(await File(take.wordsPath!).readAsString(), originalWords);
            job.dispose();
            job = null;
          }
          expect(videos.map((v) => v.id).toSet(), hasLength(3));
          expect(videos.map((v) => v.cameraPunchCount), [0, 3, 0]);
        } finally {
          job?.dispose();
          library.dispose();
          await root.delete(recursive: true);
        }
      },
    );
    test(
      'camera stress uses frozen words, output spacing and continuous splits $language',
      () {
        final frozen = cueScript(language),
            source = speech(cueScript(language));
        final whole = plan(source),
            split = plan(source, [span(0, 1550), span(1550, 25000)]);
        // A split within a word is rejected by frozen-source provenance mapping.
        expect(() => phrases(source, split, frozen), throwsFormatException);
        final continuous = plan(source, [span(0, 3000), span(3000, 25000)]);
        final track = cameraPunchesOnCut(
          whole,
          phrases(source, whole, frozen),
          policy,
        );
        expect(track.steps.map((s) => s.time.inMilliseconds), [
          1400,
          3000,
          10400,
          12000,
          19400,
          21000,
        ]);
        expect(track.count, 3);
        expect(
          cameraPunchesOnCut(
            continuous,
            phrases(source, continuous, frozen),
            policy,
          ).toJson(),
          track.toJson(),
        );
        expect(CameraPunches.fromJson(track.toJson()).toJson(), track.toJson());
        expect(() => track.steps.clear(), throwsUnsupportedError);
        expect(
          jsonEncode(track.toJson()),
          isNot(contains(frozen.tokens[1].text)),
        );
        final cut = plan(source, [span(0, 2000), span(4000, 25000)]);
        expect(
          cameraPunchesOnCut(
            cut,
            phrases(source, cut, frozen),
            policy,
          ).steps.map((s) => s.time.inMilliseconds),
          [1400, 2000, 17400, 19000],
        );
        final reordered = plan(source, [span(9000, 25000), span(0, 9000)]);
        expect(
          cameraPunchesOnCut(
            reordered,
            phrases(source, reordered, frozen),
            policy,
          ).steps.map((s) => s.time.inMilliseconds),
          [1400, 3000, 10400, 12000, 21400, 23000],
        );
      },
    );
    test(
      'camera emphasis never borrows untrusted speech or Notes cues $language',
      () {
        final frozen = cueScript(language),
            source = speech(cueScript(language)),
            cut = plan(speech(cueScript(language)));
        for (final snapshot in [
          null,
          frozen.copyWith(recordingAid: RecordingAid.notes),
          frozen.copyWith(
            marks: [for (final m in frozen.marks) m.copyWith(accepted: false)],
          ),
        ]) {
          expect(
            cameraPunchesOnCut(
              cut,
              phrases(source, cut, snapshot),
              policy,
            ).count,
            0,
          );
        }
        expect(
          cameraPunchesOnCut(
            cut,
            phrases(source, cut, frozen, aligned: false),
            policy,
          ).count,
          0,
        );
        for (final changed in [false, true]) {
          final unsure = WordTranscript(
            language: language,
            duration: source.duration,
            words: [
              for (final (i, w) in source.words.indexed)
                SpokenWord(
                  text: changed && i % 3 == 1 ? 'unmatched' : w.text,
                  start: w.start,
                  end: w.end,
                  confidence: changed ? .9 : .1,
                ),
            ],
          );
          expect(
            cameraPunchesOnCut(cut, phrases(unsure, cut, frozen), policy).count,
            0,
          );
        }
        final corrected = WordTranscript(
          language: language,
          duration: source.duration,
          words: [
            for (final w in source.words)
              SpokenWord(
                text: w.text,
                start: w.start,
                end: w.end,
                confidence: .1,
                recognizedText: 'original',
              ),
          ],
        );
        expect(
          cameraPunchesOnCut(
            cut,
            phrases(corrected, cut, frozen),
            policy,
          ).count,
          3,
        );
      },
    );
    test(
      'short take, short cut and partial camera protect the picture $language',
      () {
        final frozen = cueScript(language),
            source = speech(cueScript(language)),
            whole = plan(speech(cueScript(language)));
        final captions = phrases(source, whole, frozen);
        expect(
          cameraPunchesOnCut(
            whole,
            captions,
            policy,
            cameraDuration: ms(19000),
          ).count,
          0,
        );
        expect(
          cameraPunchesOnCut(
            whole,
            captions,
            policy,
            cameraDuration: ms(20200),
          ).steps.last.time,
          ms(20200),
        );
        final short = plan(source, [span(0, 19000)]);
        expect(
          cameraPunchesOnCut(
            short,
            phrases(source, short, frozen),
            policy,
          ).count,
          0,
        );
        final littleCamera = plan(source, [span(21000, 25000), span(0, 19000)]);
        expect(
          cameraPunchesOnCut(
            littleCamera,
            phrases(source, littleCamera, frozen),
            policy,
            cameraDuration: ms(21000),
          ).count,
          0,
        );
        expect(
          () => cameraPunchesOnCut(
            whole,
            captions,
            policy,
            cameraDuration: ms(26000),
          ),
          throwsFormatException,
        );
      },
    );
    for (final choice in [
      'camera',
      'both',
      'off',
      'hide',
      'notes',
      'short-camera',
    ]) {
      test(
        'independent export keeps originals and caption clock $language $choice',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'spawnalpha-camera-punch-',
          );
          final library = ScriptLibrary(MemoryScriptStore()),
              inspector = FakeInspector();
          final actualRenderer = FakeRenderer(inspector);
          final store = VideoExportStore(
            Directory('${root.path}/exports'),
            library,
            inspector,
          );
          ExportProcessor? job;
          try {
            final original = File('${root.path}/generated.mp4');
            await original.writeAsString('generated original');
            final camera = File('${root.path}/camera.mp4');
            await camera.writeAsString('generated camera');
            final frozen = cueScript(language).copyWith(
              recordingAid: choice == 'notes'
                  ? RecordingAid.notes
                  : RecordingAid.script,
            );
            final source = speech(frozen);
            final take = Take(
              path: original.path,
              recordedAt: DateTime(2026),
              duration: source.duration,
              mode: choice == 'camera' ? TakeMode.camera : TakeMode.both,
              cameraPath: choice == 'camera' ? null : camera.path,
              wordsPath: '${root.path}/words.json',
            );
            inspector.byPath[camera.path] = RecordingInfo(
              readable: true,
              width: 640,
              height: 360,
              duration: ms(choice == 'short-camera' ? 19000 : 25000),
            );
            final document = frozen.copyWith(takes: [take]);
            await library.save(document);
            final saved = SavedTranscript(
              sourcePath: take.path,
              transcript: source,
              snapshot: frozen,
              alignment: {'attemptCount': 4},
            );
            job = ExportProcessor(
              actualRenderer,
              store,
              CleanCutStore(Directory('${root.path}/cuts'), library),
              (_) async => saved,
            );
            final video = (await job.export(
              document,
              take,
              VideoFormat.feed,
              burnedCaptions: false,
              cameraPunch: choice != 'off',
              camera: choice != 'hide',
            ))!;
            final expected = choice == 'camera' || choice == 'both' ? 3 : 0;
            expect(video.cameraPunchCount, expected);
            expect(actualRenderer.request!.cameraPunches!.count, expected);
            expect(actualRenderer.request!.captions, isEmpty);
            expect(actualRenderer.request!.cameraPunchMain, choice == 'camera');
            final captions = phrases(source, plan(source), frozen);
            expect(
              await store.file(video, 'srt').readAsString(),
              subtitleText(captions),
            );
            final json = jsonDecode(
              await store.file(video, 'json').readAsString(),
            ) as Map;
            expect(
              CameraPunches.fromJson(
                Map<String, Object?>.from(json['cameraPunches'] as Map),
              ).count,
              expected,
            );
            expect(jsonEncode(json), isNot(contains(original.path)));
            expect(jsonEncode(json), isNot(contains(camera.path)));
            expect(
              (await store.load(library.byId(document.id)!.takes.single))
                  .single
                  .cameraPunchCount,
              expected,
            );
            expect(await original.readAsString(), 'generated original');
            expect(await camera.readAsString(), 'generated camera');
          } finally {
            job?.dispose();
            library.dispose();
            await root.delete(recursive: true);
          }
        },
      );
    }
  }
  test(
    'strict track schema, bounded collection and native-compatible clock',
    () {
      final valid = CameraPunches([
        CameraPunchStep(ms(1000), true),
        CameraPunchStep(ms(2600), false),
      ]);
      for (final bad in [
        {...valid.toJson(), 'text': 'private'},
        {
          'version': 1,
          'steps': [
            {'timeUs': 1000000, 'zoomed': true, 'face': .5},
            {'timeUs': 2000000, 'zoomed': false},
          ],
        },
        {
          'version': 1,
          'steps': [
            {'timeUs': 1000000, 'zoomed': 1},
          ],
        },
        {
          'version': 1,
          'steps': [
            {'timeUs': 1000000, 'zoomed': true},
            {'timeUs': 1000000, 'zoomed': false},
          ],
        },
        {'version': 1, 'steps': List.filled(20001, {})},
      ]) {
        expect(() => CameraPunches.fromJson(bad), throwsFormatException);
      }
      final frozen = cueScript(ScriptLanguage.en),
          cut = plan(speech(cueScript(ScriptLanguage.en)));
      VideoRenderRequest request({
        CutPlan? p,
        CameraPunches? track,
        bool main = true,
        String? camera,
        bool frame = false,
      }) => VideoRenderRequest(
        source: 'generated',
        output: 'fresh',
        plan: p ?? cut,
        format: VideoFormat.landscape,
        cameraPunches: track ?? valid,
        cameraPunchMain: main,
        camera: camera,
        screenFrame: frame,
      );
      final json = request().toJson();
      expect(json['punchFactor'], 1.12);
      expect(json['punchMain'], true);
      expect(json['punchSpring'], {
        'mass': 1.0,
        'stiffness': 90.0,
        'damping': 19.0,
      });
      expect(
        () => request(p: plan(speech(frozen), [span(0, 19000)])),
        throwsFormatException,
      );
      expect(() => request(main: false), throwsFormatException);
      expect(() => request(camera: 'paired'), throwsFormatException);
      expect(() => request(frame: true), throwsFormatException);
      expect(
        () => request(
          track: CameraPunches([
            CameraPunchStep(ms(24000), true),
            CameraPunchStep(ms(26000), false),
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => request(
          track: CameraPunches([
            ...valid.steps,
            CameraPunchStep(ms(4000), true),
            CameraPunchStep(ms(5000), false),
          ]),
        ),
        throwsFormatException,
      );
      expect(
        request(main: false, camera: 'paired').toJson()['punchMain'],
        false,
      );
      final video = VideoExport(
        id: 'generated',
        format: VideoFormat.feed,
        duration: ms(25000),
        createdAt: DateTime(2026),
        cameraPunchCount: 1,
      );
      expect(VideoExport.fromJson(video.toJson()).cameraPunchCount, 1);
      expect(
        VideoExport.fromJson(video.toJson()..remove('cameraPunchCount'))
            .cameraPunchCount,
        0,
      );
      expect(
        () =>
            VideoExport.fromJson({...video.toJson(), 'cameraPunchCount': true}),
        throwsFormatException,
      );
    },
  );
  test('frozen camera history recovers after words disappear, rejects malformed clocks', () async {
    final root = await Directory.systemTemp.createTemp(
      'spawnalpha-camera-recover-',
    );
    final disk = FailingStore(), inspector = FakeInspector();
    final library = ScriptLibrary(disk), renderer = FakeRenderer(inspector);
    final store = VideoExportStore(
      Directory('${root.path}/exports'),
      library,
      inspector,
    );
    ExportProcessor? job;
    try {
      final frozen = cueScript(ScriptLanguage.ar),
          source = speech(cueScript(ScriptLanguage.ar));
      final original = File('${root.path}/generated.mp4');
      await original.writeAsString('generated original');
      final take = Take(
        path: original.path,
        recordedAt: DateTime(2026),
        duration: source.duration,
        wordsPath: '${root.path}/words.json',
      );
      final doc = frozen.copyWith(takes: [take]);
      await library.save(doc);
      final saved = SavedTranscript(
        sourcePath: take.path,
        transcript: source,
        snapshot: frozen,
        alignment: {'attemptCount': 4},
      );
      job = ExportProcessor(
        renderer,
        store,
        CleanCutStore(Directory('${root.path}/cuts'), library),
        (_) async => saved,
      );
      renderer.deferred = Completer<void>();
      final future = job.export(doc, take, VideoFormat.portrait);
      await renderer.started.future;
      final expected = renderer.request!.cameraPunches!.toJson();
      disk.fail = true;
      renderer.deferred!.complete();
      expect(await future, isNull);
      disk.fail = false;
      final journal = (await store.pending.list().toList())
          .whereType<File>()
          .single;
      final json = jsonDecode(await journal.readAsString()) as Map;
      for (final bad in [
        {'version': 1, 'steps': []},
        {
          'version': 1,
          'steps': [
            {'timeUs': 24000000, 'zoomed': true},
            {'timeUs': 26000000, 'zoomed': false},
          ],
        },
        {
          'version': 1,
          'steps': [
            for (final start in [1000000, 4000000, 7000000]) ...[
              {'timeUs': start, 'zoomed': true},
              {'timeUs': start + 1000000, 'zoomed': false},
            ],
          ],
        },
      ]) {
        await journal.writeAsString(
          jsonEncode({...json, 'cameraPunches': bad}),
        );
        expect(await store.recover(), 0);
      }
      await journal.writeAsString(jsonEncode(json));
      expect(await store.recover(), 1);
      expect(await store.recover(), 0);
      final video = (await store.load(library.byId(doc.id)!.takes.single))
          .single;
      expect(video.cameraPunchCount, 3);
      expect(
        (jsonDecode(await store.file(video, 'json').readAsString())
            as Map)['cameraPunches'],
        expected,
      );
      expect(await original.readAsString(), 'generated original');
    } finally {
      job?.dispose();
      library.dispose();
      await root.delete(recursive: true);
    }
  });
}

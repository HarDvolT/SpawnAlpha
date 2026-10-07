// Generated sound, pictures and words only; never owner recordings or input.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:spawnalpha/src/transcription/word_timing.dart';

void require(bool value) {
  if (!value) throw StateError('Generated batch check failed');
}

bool sameBytes(List<int> a, List<int> b) =>
    a.length == b.length && a.indexed.every((v) => v.$2 == b[v.$1]);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Checking saved video formats…')),
      ),
    ),
  );
  var stage = 'generated inputs';
  ScriptLibrary? library;
  ExportProcessor? job;
  ExportBatch? batch;
  try {
    final prefix = (await File(
      'build/room-fixture-prefix.txt',
    ).readAsString()).trim();
    require(
      prefix.startsWith('${Directory.current.path}\\build\\exports\\room-'),
    );
    final root = await Directory('build/exports').createTemp('batch-app-');
    library = ScriptLibrary(
      FileScriptStore(Directory('${root.absolute.path}/scripts')),
    );
    final store = VideoExportStore(
      Directory('${root.absolute.path}/exports'),
      library,
      const WindowsRecordingInspector(),
    );
    job = ExportProcessor(
      WindowsVideoRenderer(),
      store,
      CleanCutStore(Directory('${root.absolute.path}/cuts'), library),
      (take) async => SavedTranscript.fromJson(
        jsonDecode(await File(take.wordsPath!).readAsString())
            as Map<String, Object?>,
      ),
    );
    batch = ExportBatch(job);
    var count = 0;
    for (final language in ScriptLanguage.values) {
      stage = 'prepare ${language.name}';
      final source = await File(
        '$prefix-room-source-${language == ScriptLanguage.ar ? 2 : 1}.mp4',
      ).copy('${root.absolute.path}/${language.name}.mp4');
      final original = await source.readAsBytes();
      final snapshot = ScriptDocument.create(
        language: language,
        recordingAid: language == ScriptLanguage.fr
            ? RecordingAid.notes
            : RecordingAid.script,
        text: switch (language) {
          ScriptLanguage.en => 'We launch today.',
          ScriptLanguage.fr => 'Nous lançons demain.',
          ScriptLanguage.ar => 'نحن نبدأ الآن.',
        },
      );
      final words = WordTranscript(
        language: language,
        duration: const Duration(seconds: 4),
        words: [
          for (var i = 0; i < snapshot.tokens.length; ++i)
            SpokenWord(
              text: snapshot.tokens[i].text,
              start: Duration(milliseconds: [1050, 3050, 3300][i]),
              end: Duration(milliseconds: [1250, 3250, 3500][i]),
              confidence: .9,
            ),
        ],
      );
      final take = Take(
        path: source.path,
        recordedAt: DateTime(2026),
        duration: words.duration,
        mode: switch (language) {
          ScriptLanguage.en => TakeMode.camera,
          ScriptLanguage.fr => TakeMode.screen,
          ScriptLanguage.ar => TakeMode.both,
        },
        cameraPath: language == ScriptLanguage.ar ? source.path : null,
        wordsPath: '${source.path}.words.json',
      );
      final spoken = SavedTranscript(
        sourcePath: source.path,
        transcript: words,
        snapshot: snapshot,
        alignment: snapshot.usesNotes ? null : {'attemptCount': 1},
        quiet: [
          SourceRange(
            start: const Duration(milliseconds: 100),
            end: const Duration(milliseconds: 900),
          ),
        ],
      );
      await File(take.wordsPath!).writeAsString(jsonEncode(spoken.toJson()));
      final originalWords = await File(take.wordsPath!).readAsString();
      await library.save(snapshot.copyWith(takes: [take]));
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
      await job.cuts.save(snapshot.id, take, clean);
      final current = library.byId(snapshot.id)!;
      stage = 'batch ${language.name}';
      final videos = await batch.run(
        current,
        current.takes.single,
        VideoFormat.values,
        choices: ExportChoices(
          clean: clean,
          captionStyle: CaptionStyle.karaoke,
          captionMotion: false,
          balanceSound: true,
          softenSharpSound: true,
          reduceNoise: true,
          roomToneJoins: true,
          cameraClear: false,
          autoZoom: false,
          motionBlur: false,
          clickHighlights: false,
          showShortcuts: false,
          cameraPunch: false,
        ),
      );
      require(
        videos.length == 4 &&
            batch.progress == 1 &&
            batch.problem == null &&
            !batch.busy,
      );
      final expected = captionsFromSpeech(speechOnCleanCut(words, clean));
      final savedBytes = <String, List<int>>{};
      for (final video in videos) {
        require(
          video.duration == const Duration(milliseconds: 2600) &&
              video.balanceSound &&
              video.reduceNoise &&
              video.softenSharpSound &&
              video.roomTone != null &&
              video.captionStyle == CaptionStyle.karaoke &&
              !video.captionMotion,
        );
        require(
          await store.file(video, 'srt').readAsString() ==
              subtitleText(expected),
        );
        require(
          await store.file(video, 'vtt').readAsString() ==
              subtitleText(expected, vtt: true),
        );
        final portable =
            (jsonDecode(await store.file(video, 'json').readAsString())
                    as Map)['video']
                as Map;
        require(
          portable['format'] == video.format.name &&
              portable['wordsPath'] == null &&
              portable['cutPath'] == null &&
              jsonEncode(portable['roomTone']) ==
                  jsonEncode({'startUs': 100000, 'endUs': 200000}),
        );
        for (final extension in ['mp4', 'json', 'srt', 'vtt']) {
          final file = store.file(video, extension);
          savedBytes[file.path] = await file.readAsBytes();
        }
        ++count;
      }
      require(
        (await store.load(library.byId(snapshot.id)!.takes.single)).length == 4,
      );
      // Cancel a real second render after one completed file. Finished batch
      // versions must remain byte-for-byte intact, including all 4K outputs.
      if (language == ScriptLanguage.en) {
        stage = 'cancel real second render';
        var requested = false;
        void cancelSecond() {
          if (!requested &&
              batch!.saved == 1 &&
              job!.phase == ExportPhase.rendering &&
              job.progress >= .1) {
            requested = true;
            unawaited(batch.cancel());
          }
        }

        batch.addListener(cancelSecond);
        final partial = await batch.run(
          library.byId(snapshot.id)!,
          library.byId(snapshot.id)!.takes.single,
          [VideoFormat.feed, VideoFormat.portrait, VideoFormat.landscape],
          choices: ExportChoices(
            clean: clean,
            burnedCaptions: false,
            screenFrame: false,
            softAudioJoins: false,
            cameraClear: false,
            autoZoom: false,
            motionBlur: false,
            clickHighlights: false,
            showShortcuts: false,
            cameraPunch: false,
          ),
        );
        batch.removeListener(cancelSecond);
        require(
          requested &&
              batch.cancelled &&
              partial.length == 1 &&
              batch.problem == null &&
              partial.single.format == VideoFormat.feed &&
              !partial.single.balanceSound &&
              !partial.single.burnedCaptions,
        );
        await store.recover();
        require(
          (await store.load(library.byId(snapshot.id)!.takes.single)).length ==
              5,
        );
        ++count;
      }
      for (final entry in savedBytes.entries) {
        require(sameBytes(await File(entry.key).readAsBytes(), entry.value));
      }
      require(
        sameBytes(await source.readAsBytes(), original) &&
            await File(take.wordsPath!).readAsString() == originalWords,
      );
      await library.load();
      require(
        (await store.load(library.byId(snapshot.id)!.takes.single)).length ==
            (language == ScriptLanguage.en ? 5 : 4),
      );
    }
    await File('build/batch-app-check-result.json')
        .writeAsString(jsonEncode({'passed': true, 'exports': count}));
    stdout.writeln(
      'Generated batch app-channel checks passed: $count EN/FR/AR exports, all formats, cancelled second render, exact subtitles, history and original bytes.',
    );
    batch.dispose();
    job.dispose();
    library.dispose();
    exit(0);
  } on Object {
    stderr.writeln('Generated batch check failed at $stage.');
    batch?.dispose();
    job?.dispose();
    library?.dispose();
    exit(1);
  }
}

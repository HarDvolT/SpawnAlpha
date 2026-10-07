// Generated colour bars and labelled words only. No owner media or input.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/model/mark.dart';
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
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

void require(bool value) {
  if (!value) throw StateError('Generated camera emphasis check failed');
}

bool sameBytes(List<int> a, List<int> b) =>
    a.length == b.length && a.indexed.every((item) => item.$2 == b[item.$1]);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Checking local camera emphasis…')),
      ),
    ),
  );
  var stage = 'generated input';
  ScriptLibrary? library;
  ExportProcessor? job;
  try {
    final prefix = (await File(
      'build/punch-fixture-prefix.txt',
    ).readAsString()).trim();
    final fixture = File('$prefix-punch-source.mp4');
    require(
      prefix.startsWith('${Directory.current.path}\\build\\exports\\punch-') &&
          await fixture.exists(),
    );
    final root = await Directory('build/exports').createTemp('punch-app-');
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
    for (final language in ScriptLanguage.values) {
      stage = 'save generated camera words and frozen cues';
      final source = await fixture.copy(
        '${root.absolute.path}/${language.name}.mp4',
      );
      final camera = await fixture.copy(
        '${root.absolute.path}/${language.name}-camera.mp4',
      );
      final before = await source.readAsBytes(),
          cameraBefore = await camera.readAsBytes();
      final frozen =
          ScriptDocument.create(
            language: language,
            text: switch (language) {
              ScriptLanguage.en => 'We launch today.',
              ScriptLanguage.fr => 'Nous lançons demain.',
              ScriptLanguage.ar => 'نحن نبدأ الآن.',
            },
          ).copyWith(
            marks: [
              const Mark(id: 'stress', kind: MarkKind.stress, start: 1, end: 1),
            ],
          );
      final mainCamera = language == ScriptLanguage.en;
      final take = Take(
        path: source.path,
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 25),
        mode: mainCamera ? TakeMode.camera : TakeMode.both,
        cameraPath: mainCamera ? null : camera.path,
        wordsPath: '${source.path}.words.json',
      );
      final doc = frozen.copyWith(takes: [take]);
      final words = WordTranscript(
        language: language,
        duration: take.duration,
        words: [
          for (final start in [1000, 10000, 19000])
            for (var i = 0; i < 3; ++i)
              SpokenWord(
                text: frozen.tokens[i].text,
                start: Duration(milliseconds: start + i * 400),
                end: Duration(milliseconds: start + i * 400 + 200),
                confidence: .9,
              ),
        ],
      );
      await File(take.wordsPath!).writeAsString(
        jsonEncode(
          SavedTranscript(
            sourcePath: source.path,
            transcript: words,
            snapshot: frozen,
            alignment: {'attemptCount': 3},
          ).toJson(),
        ),
        flush: true,
      );
      await library.save(doc);
      String? subtitles;
      for (final on in [true, false]) {
        stage = 'render ${language.name} camera emphasis ${on ? 'on' : 'off'}';
        final current = library.byId(doc.id)!.takes.single;
        final video = await job.export(
          library.byId(doc.id)!,
          current,
          switch (language) {
            ScriptLanguage.en => VideoFormat.landscape,
            ScriptLanguage.fr => VideoFormat.feed,
            ScriptLanguage.ar => VideoFormat.portrait,
          },
          cameraPunch: on,
        );
        require(
          video != null &&
              job.phase == ExportPhase.done &&
              video.cameraPunchCount == (on ? 3 : 0),
        );
        require(
          video!.camera == !mainCamera && video.screenFrame == !mainCamera,
        );
        final json =
            jsonDecode(await store.file(video, 'json').readAsString()) as Map;
        final track = CameraPunches.fromJson(
          Map<String, Object?>.from(json['cameraPunches'] as Map),
        );
        require(track.count == (on ? 3 : 0));
        if (on) {
          require(
            track.steps.map((s) => s.time.inMilliseconds).join(',') ==
                '1400,3000,10400,12000,19400,21000',
          );
        }
        final portable = jsonEncode(json);
        require(
          !portable.contains(source.path) && !portable.contains(camera.path),
        );
        final srt = await store.file(video, 'srt').readAsString();
        if (subtitles != null) {
          require(subtitles == srt);
        }
        subtitles = srt;
      }
      stage = 'reload camera history and verify unchanged original files';
      await library.load();
      final history = await store.load(library.byId(doc.id)!.takes.single);
      require(
        history.length == 2 &&
            history.where((v) => v.cameraPunchCount == 3).length == 1,
      );
      require(
        sameBytes(before, await source.readAsBytes()) &&
            sameBytes(cameraBefore, await camera.readAsBytes()),
      );
    }
    // ignore: avoid_print
    print(
      'Local camera emphasis check passed: EN/FR/AR Camera/Both wide/feed/portrait on/off, reliable frozen stress, exact subtitle clocks, immutable tracks/history and unchanged originals.',
    );
  } on Object {
    // ignore: avoid_print
    print('Local camera emphasis check failed at $stage.');
  } finally {
    job?.dispose();
    library?.dispose();
  }
}

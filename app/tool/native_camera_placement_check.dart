// Generated screen/camera colours and words only; never owner media/input.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/camera_targets.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

void require(bool value) {
  if (!value) throw StateError('Generated camera placement check failed');
}

bool sameBytes(List<int> a, List<int> b) =>
    a.length == b.length && a.indexed.every((v) => v.$2 == b[v.$1]);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Checking saved camera placement…')),
      ),
    ),
  );
  var stage = 'generated input';
  ScriptLibrary? library;
  ExportProcessor? job;
  try {
    final prefix = (await File(
      'build/clear-fixture-prefix.txt',
    ).readAsString()).trim();
    require(
      prefix.startsWith('${Directory.current.path}\\build\\exports\\clear-'),
    );
    final root = await Directory('build/exports').createTemp('clear-app-');
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
      stage = 'prepare generated paired take';
      final source = await File('$prefix-clear-screen.mp4')
          .copy('${root.absolute.path}/${language.name}.mp4');
      final camera = await File('$prefix-clear-camera.mp4')
          .copy('${root.absolute.path}/${language.name}-camera.mp4');
      final activity = File('${source.path}.activity.jsonl');
      await activity.writeAsString(
        [
          jsonEncode({
            'type': 'header',
            'version': 1,
            'coordinates': 'sourcePixels',
            'keys': 'timingOnly',
          }),
          for (final ms in [100, 400, 700, 1000, 1300, 1600, 1900, 2200, 2500])
            jsonEncode({
              'type': 'cursor',
              'timeUs': ms * 1000,
              'width': 640,
              'height': 360,
              'x': 544,
              'y': 306,
              'visible': true,
              'detail': 'arrow',
            }),
          jsonEncode({
            'type': 'end',
            'timeUs': 4000000,
            'events': 9,
            'complete': true,
          }),
          '',
        ].join('\n'),
      );
      final original = await source.readAsBytes(),
          paired = await camera.readAsBytes(),
          trace = await activity.readAsString();
      final snapshot = ScriptDocument.create(
        language: language,
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
              start: Duration(milliseconds: 300 + i * 500),
              end: Duration(milliseconds: 600 + i * 500),
              confidence: .9,
            ),
        ],
      );
      final take = Take(
        path: source.path,
        recordedAt: DateTime(2026),
        duration: words.duration,
        mode: TakeMode.both,
        cameraPath: camera.path,
        activityPath: activity.path,
        wordsPath: '${source.path}.words.json',
      );
      await File(take.wordsPath!).writeAsString(
        jsonEncode(
          SavedTranscript(
            sourcePath: source.path,
            transcript: words,
            snapshot: snapshot,
            alignment: {'attemptCount': 1},
          ).toJson(),
        ),
      );
      final originalWords = await File(take.wordsPath!).readAsString();
      await library.save(snapshot.copyWith(takes: [take]));
      String? srt;
      final saved = <String, List<int>>{};
      final format = switch (language) {
        ScriptLanguage.en => VideoFormat.landscape,
        ScriptLanguage.fr => VideoFormat.feed,
        ScriptLanguage.ar => VideoFormat.portrait,
      };
      for (final enabled in [true, false]) {
        stage =
            'export generated paired take ${language.name} camera-clear $enabled';
        final current = library.byId(snapshot.id)!;
        final video = await job.export(
          current,
          current.takes.single,
          format,
          cameraClear: enabled,
          autoZoom: false,
          clickHighlights: false,
          showShortcuts: false,
          cameraPunch: false,
        );
        require(
          video != null &&
              video.camera &&
              video.cameraClear == enabled &&
              video.duration == words.duration,
        );
        final metadata = jsonDecode(
          await store.file(video!, 'json').readAsString(),
        ) as Map<String, Object?>;
        if (enabled) {
          final targets = CameraTargets.fromJson(
            metadata['cameraTargets']! as Map<String, Object?>,
          );
          require(
            targets.targets.length == 1 &&
                targets.targets.single.start.inMilliseconds == 100 &&
                targets.targets.single.end.inMilliseconds == 3200,
          );
        } else {
          require(metadata['cameraTargets'] == null);
        }
        final subtitle = await store.file(video, 'srt').readAsString();
        require(srt == null || srt == subtitle);
        srt = subtitle;
        for (final entry in saved.entries) {
          require(sameBytes(await File(entry.key).readAsBytes(), entry.value));
        }
        for (final extension in ['mp4', 'json', 'srt', 'vtt']) {
          final file = store.file(video, extension);
          saved[file.path] = await file.readAsBytes();
        }
        require(
          sameBytes(await source.readAsBytes(), original) &&
              sameBytes(await camera.readAsBytes(), paired) &&
              await activity.readAsString() == trace &&
              await File(take.wordsPath!).readAsString() == originalWords,
        );
      }
      final history = await store.load(library.byId(snapshot.id)!.takes.single);
      require(
        history.length == 2 && history.where((v) => v.cameraClear).length == 1,
      );
    }
    await File('build/clear-app-check-result.json')
        .writeAsString(jsonEncode({'passed': true, 'exports': 6}));
    stdout.writeln(
      'Generated camera placement app-channel checks passed: six EN/FR/AR wide/feed/portrait on/off exports, exact subtitles, immutable targets/history and originals.',
    );
    job.dispose();
    library.dispose();
    exit(0);
  } on Object {
    stderr.writeln('Generated camera placement check failed at $stage.');
    job?.dispose();
    library?.dispose();
    exit(1);
  }
}

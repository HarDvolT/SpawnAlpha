// Generated tones, pictures and words only; never owner recordings/input.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:spawnalpha/src/transcription/word_timing.dart';

void require(bool value) {
  if (!value) throw StateError('Generated sound check failed');
}

bool sameBytes(List<int> a, List<int> b) =>
    a.length == b.length && a.indexed.every((v) => v.$2 == b[v.$1]);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Checking saved sound choices…')),
      ),
    ),
  );
  var stage = 'generated inputs';
  ScriptLibrary? library;
  ExportProcessor? job;
  try {
    final prefix = (await File(
      'build/sound-fixture-prefix.txt',
    ).readAsString()).trim();
    require(
      prefix.startsWith('${Directory.current.path}\\build\\exports\\sound-'),
    );
    final root = await Directory('build/exports').createTemp('sound-app-');
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
    var count = 0;
    for (final language in ScriptLanguage.values) {
      stage = 'prepare generated sound';
      final source = await File('$prefix-sound-source.mp4')
          .copy('${root.absolute.path}/${language.name}.mp4');
      final original = await source.readAsBytes();
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
        mode: switch (language) {
          ScriptLanguage.en => TakeMode.camera,
          ScriptLanguage.fr => TakeMode.screen,
          ScriptLanguage.ar => TakeMode.both,
        },
        cameraPath: language == ScriptLanguage.ar ? source.path : null,
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
      final formats = switch (language) {
        ScriptLanguage.en => [VideoFormat.landscape, VideoFormat.landscape4k],
        ScriptLanguage.fr => [VideoFormat.feed],
        ScriptLanguage.ar => [VideoFormat.portrait],
      };
      for (final format in formats) {
        for (final enabled in [true, false]) {
          stage =
              'export generated sound ${language.name} ${format.name} $enabled';
          final current = library.byId(snapshot.id)!;
          final video = await job.export(
            current,
            current.takes.single,
            format,
            balanceSound: enabled,
            cameraClear: false,
            autoZoom: false,
            motionBlur: false,
            clickHighlights: false,
            showShortcuts: false,
            cameraPunch: false,
          );
          require(
            video != null &&
                video.balanceSound == enabled &&
                video.duration == words.duration,
          );
          final metadata = jsonDecode(
            await store.file(video!, 'json').readAsString(),
          ) as Map;
          require((metadata['video'] as Map)['balanceSound'] == enabled);
          final subtitle = await store.file(video, 'srt').readAsString();
          require(srt == null || srt == subtitle);
          srt = subtitle;
          for (final entry in saved.entries) {
            require(
              sameBytes(await File(entry.key).readAsBytes(), entry.value),
            );
          }
          for (final extension in ['mp4', 'json', 'srt', 'vtt']) {
            final file = store.file(video, extension);
            saved[file.path] = await file.readAsBytes();
          }
          require(
            sameBytes(await source.readAsBytes(), original) &&
                await File(take.wordsPath!).readAsString() == originalWords,
          );
          ++count;
        }
      }
      final history = await store.load(library.byId(snapshot.id)!.takes.single);
      require(
        history.length == formats.length * 2 &&
            history.where((v) => v.balanceSound).length == formats.length,
      );
    }
    await File('build/sound-app-check-result.json')
        .writeAsString(jsonEncode({'passed': true, 'exports': count}));
    stdout.writeln(
      'Generated sound app-channel checks passed: eight EN/FR/AR exports in all four formats, saved on/off choices, exact subtitles, history and original bytes.',
    );
    job.dispose();
    library.dispose();
    exit(0);
  } on Object {
    stderr.writeln('Generated sound check failed at $stage.');
    job?.dispose();
    library?.dispose();
    exit(1);
  }
}

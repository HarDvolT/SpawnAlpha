// Generated colour bars and labelled words only. No owner media or input.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/screen_zooms.dart';
import 'package:spawnalpha/src/render/screen_clicks.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

void require(bool value) {
  if (!value) throw StateError('Generated screen zoom check failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Checking local screen zooms…'))),
    ),
  );
  var stage = 'generated input';
  ScriptLibrary? library;
  ExportProcessor? job;
  try {
    final prefix = (await File(
      'build/screen-zoom-fixture-prefix.txt',
    ).readAsString()).trim();
    final fixture = File('$prefix-zoom-source.mp4');
    require(
      prefix.startsWith(
            '${Directory.current.path}\\build\\exports\\screen-zooms-',
          ) &&
          await fixture.exists(),
    );
    final root = await Directory('build/exports').createTemp('zoom-app-');
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
      (take) async {
        return SavedTranscript.fromJson(
          jsonDecode(await File(take.wordsPath!).readAsString())
              as Map<String, Object?>,
        );
      },
    );
    for (final language in ScriptLanguage.values) {
      stage = 'save generated screen activity and labelled words';
      final source = await fixture.copy(
        '${root.absolute.path}/${language.name}.mp4',
      );
      final before = await source.readAsBytes();
      final activity = File('${source.path}.activity.jsonl');
      await activity.writeAsString(
        [
          jsonEncode({
            'type': 'header',
            'version': 1,
            'coordinates': 'sourcePixels',
            'keys': 'timingOnly',
          }),
          for (final ms in [700])
            jsonEncode({
              'type': 'click',
              'timeUs': ms * 1000,
              'width': 640,
              'height': 360,
              'x': 512,
              'y': 180,
              'visible': true,
              'detail': 'left',
            }),
          jsonEncode({
            'type': 'end',
            'timeUs': 4000000,
            'events': 1,
            'complete': true,
          }),
          '',
        ].join('\n'),
        flush: true,
      );
      final activityBefore = await activity.readAsString();
      final frozen = ScriptDocument.create(
        language: language,
        text: switch (language) {
          ScriptLanguage.en => 'Click here now.',
          ScriptLanguage.fr => 'Cliquez ici maintenant.',
          ScriptLanguage.ar => 'اضغط هنا الآن.',
        },
      );
      final take = Take(
        path: source.path,
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 4),
        mode: TakeMode.screen,
        activityPath: activity.path,
        wordsPath: '${source.path}.words.json',
      );
      final document = frozen.copyWith(takes: [take]);
      final words = WordTranscript(
        language: language,
        duration: take.duration,
        words: [
          for (final (i, token) in frozen.tokens.indexed)
            SpokenWord(
              text: token.text,
              start: Duration(milliseconds: 400 + i * 200),
              end: Duration(milliseconds: 550 + i * 200),
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
            alignment: {'attemptCount': 1},
          ).toJson(),
        ),
        flush: true,
      );
      await library.save(document);
      String? subtitles;
      for (final choice in ['all', 'plain', 'clicks']) {
        final enabled = choice == 'all', highlight = choice != 'plain';
        stage = 'render enabled and full-picture choices';
        final latest = library.byId(document.id)!.takes.single;
        final video = await job.export(
          document,
          latest,
          language == ScriptLanguage.ar
              ? VideoFormat.portrait
              : language == ScriptLanguage.fr
              ? VideoFormat.feed
              : VideoFormat.landscape,
          autoZoom: enabled,
          clickHighlights: highlight,
        );
        require(
          video != null &&
              job.phase == ExportPhase.done &&
              video.zoomCount == (enabled ? 1 : 0) &&
              video.clickCount == (highlight ? 1 : 0) &&
              video.duration == take.duration,
        );
        final metadata =
            jsonDecode(await store.file(video!, 'json').readAsString()) as Map;
        final track = ScreenZooms.fromJson(
          Map<String, Object?>.from(metadata['screenZooms'] as Map),
        );
        require(track.count == video.zoomCount);
        final clicks = metadata['screenClicks'] == null
            ? null
            : ScreenClicks.fromJson(
                Map<String, Object?>.from(metadata['screenClicks'] as Map),
              );
        require((clicks?.count ?? 0) == video.clickCount);
        if (highlight) {
          require(
            clicks!.pulses.single.start == const Duration(milliseconds: 700) &&
                clicks.pulses.single.end == const Duration(milliseconds: 1120),
          );
        }
        if (enabled) {
          require(
            track.steps.first.time == const Duration(milliseconds: 400) &&
                track.steps.last.time == const Duration(milliseconds: 2100),
          );
        }
        final portable = jsonEncode(metadata);
        require(
          !portable.contains(source.path) && !portable.contains(activity.path),
        );
        final srt = await store.file(video, 'srt').readAsString();
        if (subtitles != null) require(subtitles == srt);
        subtitles = srt;
      }
      stage = 'reload history and compare original bytes';
      await library.load();
      final history = await store.load(library.byId(document.id)!.takes.single);
      require(
        history.length == 3 &&
            history.where((v) => v.zoomCount == 1).length == 1,
      );
      require(history.where((v) => v.clickCount == 1).length == 2);
      final after = await source.readAsBytes();
      require(
        before.length == after.length &&
            before.indexed.every((item) => item.$2 == after[item.$1]),
      );
      require(activityBefore == await activity.readAsString());
    }
    // ignore: avoid_print
    print(
      'Local screen zoom check passed: EN/FR/AR spoken pointing phrases, one click, wide/feed/portrait, independent zoom/click on/off, caption clocks, immutable targets/history and unchanged source/activity bytes.',
    );
  } on Object {
    // ignore: avoid_print
    print('Local screen zoom check failed at $stage.');
  } finally {
    job?.dispose();
    library?.dispose();
  }
}

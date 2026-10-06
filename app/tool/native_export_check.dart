// Generated colours and tones only. No owner take, input or recording device.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/captions.dart';
import 'package:spawnalpha/src/playback/local_playback.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';

void require(bool condition) {
  if (!condition) throw StateError('Generated export check failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Checking local video export…'))),
    ),
  );
  var stage = 'find generated fixture';
  PlaybackHandle? handle;
  const playback = WindowsLocalPlayback();
  ScriptLibrary? library;
  ExportProcessor? job;
  try {
    final fixture = File(
      '${Directory.current.path}/build/playback/generated.mp4',
    );
    require(await fixture.exists());
    final root = Directory(
      '${Directory.current.path}/build/exports/native-${newId()}',
    );
    await root.create(recursive: true);
    final source = await fixture.copy('${root.path}/generated-é-العربية.mp4');
    const inspector = WindowsRecordingInspector();
    final renderer = WindowsVideoRenderer();
    library = ScriptLibrary(FileScriptStore(Directory('${root.path}/scripts')));
    var take = Take(
      path: source.path,
      mode: TakeMode.both,
      cameraPath: source.path,
      recordedAt: DateTime(2026),
      duration: const Duration(seconds: 4),
    );
    final script = ScriptDocument.create().copyWith(takes: [take]);
    await library.save(script);
    final store = VideoExportStore(
      Directory('${root.path}/exports'),
      library,
      inspector,
    );
    final plan = CutPlan(
      takeId: 'generated',
      language: script.language,
      sourceDuration: take.duration,
      ranges: [
        SourceRange(
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 2),
        ),
        SourceRange(
          start: const Duration(seconds: 3),
          end: const Duration(seconds: 4),
        ),
      ],
    );
    for (final format in VideoFormat.values) {
      final language = format == VideoFormat.portrait
          ? ScriptLanguage.ar
          : format == VideoFormat.feed
          ? ScriptLanguage.fr
          : ScriptLanguage.en;
      final captionPlan = CutPlan(
        takeId: plan.takeId,
        language: language,
        sourceDuration: plan.sourceDuration,
        ranges: plan.ranges,
      );
      final captions = [
        Caption(
          switch (language) {
            ScriptLanguage.en => 'Hello everyone.',
            ScriptLanguage.fr => 'Bonjour à tous.',
            ScriptLanguage.ar => 'مرحبا بكم اليوم.',
          },
          const Duration(milliseconds: 250),
          const Duration(milliseconds: 1750),
        ),
      ];
      stage = 'render ${format.name}';
      final video = VideoExport(
        id: newId(),
        format: format,
        duration: plan.duration,
        createdAt: DateTime(2026),
        camera: format == VideoFormat.portrait,
        captions: true,
        burnedCaptions: true,
      );
      final reservation = await store.reserve(
        script.id,
        take,
        video,
        captionPlan,
        srt: subtitleText(captions),
        vtt: subtitleText(captions, vtt: true),
      );
      double progress = 0;
      await renderer.render(
        VideoRenderRequest(
          source: source.path,
          output: store.file(video).path,
          camera: video.camera ? source.path : null,
          plan: captionPlan,
          format: format,
          captions: captions,
        ),
        (value) {
          require(value >= progress);
          progress = value;
        },
      );
      require(progress == 1);
      stage = 'probe ${format.name}';
      final info = await inspector.inspect(store.file(video).path);
      // Generated fixture dimensions and numeric clock only.
      // ignore: avoid_print
      print(
        'Generated ${format.name}: readable=${info.readable} audio=${info.hasAudio} size=${info.width}x${info.height} durationUs=${info.duration.inMicroseconds}',
      );
      require(
        info.readable &&
            info.hasAudio &&
            info.width == format.width &&
            info.height == format.height,
      );
      require(
        (info.duration - plan.duration).abs() <=
            const Duration(milliseconds: 10),
      );
      stage = 'save ${format.name}';
      await store.finish(reservation);
      take = library.byId(script.id)!.takes.single;
      require((await store.load(take)).first.id == video.id);
      require((await store.load(take)).first.burnedCaptions);
      require(
        await store.file(video, 'srt').exists() &&
            await store.file(video, 'vtt').exists(),
      );
      stage = 'open saved ${format.name}';
      handle = await playback.open(store.file(video).path);
      var ready = false;
      for (var attempt = 0; attempt < 100; ++attempt) {
        final status = await playback.status(handle);
        require(!status.failed && !status.closed && !status.playing);
        if (status.ready && status.frames > 0) {
          ready = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      require(ready);
      await playback.close(handle);
      handle = null;
    }
    stage = 'reload export history';
    await library.load();
    take = library.byId(script.id)!.takes.single;
    require((await store.load(take)).length == VideoFormat.values.length);
    stage = 'full processor with original sound';
    job = ExportProcessor(
      renderer,
      store,
      CleanCutStore(Directory('${root.path}/cuts'), library),
      (_) async => null,
    );
    final video = await job.export(
      script,
      take,
      VideoFormat.landscape,
      camera: false,
    );
    require(
      video != null &&
          job.phase == ExportPhase.done &&
          video.duration == take.duration,
    );
    stage = 'cancel in-flight native render';
    final cancelled = File('${root.path}/cancelled.mp4');
    bool requested = false, stopped = false;
    try {
      await renderer.render(
        VideoRenderRequest(
          source: source.path,
          output: cancelled.path,
          plan: plan,
          format: VideoFormat.landscape4k,
        ),
        (value) {
          if (!requested && value > 0) {
            requested = true;
            unawaited(renderer.cancel());
          }
        },
      );
    } on RenderCancelled {
      stopped = true;
    }
    require(requested && stopped && !await cancelled.exists());
    stage = 'preserve original';
    require(await source.length() == await fixture.length());
    require((await inspector.inspect(source.path)).readable);
    // ignore: avoid_print
    print(
      'Local export check passed: all four formats, Unicode paths, EN/FR/AR captions, exact cut/audio clock, optional camera, caption files and verified history/reload, saved playback, full processor and cancel cleanup.',
    );
  } on Object {
    // Fixed stage only. Never print media paths, text or OS exception messages.
    // ignore: avoid_print
    print('Local export check failed at $stage.');
  } finally {
    if (handle != null) await playback.close(handle);
    job?.dispose();
    library?.dispose();
  }
}

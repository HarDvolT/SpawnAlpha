import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/screen_zooms.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

import 'export_processor_test.dart' show FakeRenderer;
import '../storage/screen_take_store_test.dart'
    show FakeInspector, FailingStore;

Future<File> activityFor(
  File source, {
  List<int> clicks = const [500, 700],
}) async {
  final file = File('${source.path}.activity.jsonl');
  await file.writeAsString(
    [
      jsonEncode({
        'type': 'header',
        'version': 1,
        'coordinates': 'sourcePixels',
        'keys': 'timingOnly',
      }),
      for (final ms in clicks)
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
        'events': clicks.length,
        'complete': true,
      }),
      '',
    ].join('\n'),
  );
  return file;
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
    root = await Directory.systemTemp.createTemp('spawnalpha-screen-zoom-');
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
    for (final mode in ['on', 'off', 'notes', 'unaligned']) {
      test(
        'export worker uses reliable spoken points only $language $mode',
        () async {
          final source = File('${root.path}/generated.mp4');
          await source.writeAsString('generated screen');
          final activity = await activityFor(source, clicks: [700]);
          final frozen =
              ScriptDocument.create(
                language: language,
                text: switch (language) {
                  ScriptLanguage.en => 'Click here now.',
                  ScriptLanguage.fr => 'Cliquez ici maintenant.',
                  ScriptLanguage.ar => 'اضغط هنا الآن.',
                },
              ).copyWith(
                recordingAid: mode == 'notes'
                    ? RecordingAid.notes
                    : RecordingAid.script,
              );
          final take = Take(
            path: source.path,
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 4),
            mode: TakeMode.screen,
            wordsPath: '${source.path}.words.json',
            activityPath: activity.path,
          );
          final document = frozen.copyWith(takes: [take]);
          await library.save(document);
          final spoken = SavedTranscript(
            sourcePath: source.path,
            snapshot: frozen,
            alignment: mode == 'unaligned' ? null : {'attemptCount': 1},
            transcript: WordTranscript(
              language: language,
              duration: take.duration,
              words: [
                for (final (i, t) in frozen.tokens.indexed)
                  SpokenWord(
                    text: t.text,
                    start: Duration(milliseconds: 400 + i * 200),
                    end: Duration(milliseconds: 550 + i * 200),
                    confidence: .9,
                  ),
              ],
            ),
          );
          final job = ExportProcessor(
            renderer,
            store,
            cuts,
            (_) async => spoken,
          );
          final result = (await job.export(
            document,
            take,
            VideoFormat.landscape,
            autoZoom: mode != 'off',
          ))!;
          expect(result.zoomCount, mode == 'on' ? 1 : 0);
          expect(result.clickCount, 1);
          expect(renderer.request!.screenZooms!.count, result.zoomCount);
          expect(renderer.request!.captions.first.text, frozen.text);
          expect(
            (await store.load(library.byId(document.id)!.takes.single))
                .single
                .zoomCount,
            result.zoomCount,
          );
          job.dispose();
        },
      );
    }
    for (final mode in ['on', 'off', 'unavailable']) {
      test(
        'zoom export preserves words, activity and history $language $mode',
        () async {
          final source = File('${root.path}/generated.mp4');
          await source.writeAsString('generated source');
          final activity = await activityFor(source);
          final before = await activity.readAsString();
          if (mode == 'unavailable') await activity.delete();
          final text = switch (language) {
            ScriptLanguage.en => 'Today',
            ScriptLanguage.fr => 'Aujourd’hui',
            ScriptLanguage.ar => 'اليوم',
          };
          final take = Take(
            path: source.path,
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 4),
            mode: TakeMode.screen,
            wordsPath: '${root.path}/words.json',
            activityPath: activity.path,
          );
          final script = ScriptDocument.create(
            language: language,
            text: text,
          ).copyWith(takes: [take]);
          await library.save(script);
          final spoken = SavedTranscript(
            sourcePath: source.path,
            snapshot: script,
            transcript: WordTranscript(
              language: language,
              duration: take.duration,
              words: [
                SpokenWord(
                  text: text,
                  start: const Duration(milliseconds: 400),
                  end: const Duration(milliseconds: 900),
                  confidence: .9,
                ),
              ],
            ),
          );
          final job = ExportProcessor(
            renderer,
            store,
            cuts,
            (_) async => spoken,
          );
          final video = (await job.export(
            script,
            take,
            VideoFormat.portrait,
            autoZoom: mode != 'off',
          ))!;
          expect(video.zoomCount, mode == 'on' ? 1 : 0);
          expect(video.clickCount, mode == 'unavailable' ? 0 : 2);
          expect(renderer.request!.screenZooms!.count, video.zoomCount);
          expect(
            renderer.request!.captions.single.words.single.start,
            spoken.transcript.words.single.start,
          );
          expect(
            await store.file(video, 'srt').readAsString(),
            contains('00:00:00,400 --> 00:00:00,900'),
          );
          final metadata =
              jsonDecode(await store.file(video, 'json').readAsString()) as Map;
          final zooms = ScreenZooms.fromJson(
            Map<String, Object?>.from(metadata['screenZooms'] as Map),
          );
          expect(zooms.count, video.zoomCount);
          if (mode == 'on') {
            expect(zooms.steps.first.time, const Duration(milliseconds: 200));
            expect(zooms.steps.last.time, const Duration(milliseconds: 2100));
          }
          final portable = jsonEncode(metadata);
          expect(portable, isNot(contains(source.path)));
          expect(portable, isNot(contains(activity.path)));
          expect(portable, isNot(contains('wordsPath')));
          expect(job.notice == null, mode != 'unavailable');
          expect(
            (await store.load(library.byId(script.id)!.takes.single))
                .single
                .zoomCount,
            video.zoomCount,
          );
          expect(await source.readAsString(), 'generated source');
          if (mode != 'unavailable') {
            expect(await activity.readAsString(), before);
          }
          job.dispose();
        },
      );
    }
  }
  test('camera export ignores screen activity', () async {
    final source = File('${root.path}/generated.mp4');
    await source.writeAsString('generated camera');
    final activity = await activityFor(source);
    final take = Take(
      path: source.path,
      recordedAt: DateTime(2026),
      duration: const Duration(seconds: 4),
      activityPath: activity.path,
    );
    final script = ScriptDocument.create().copyWith(takes: [take]);
    await library.save(script);
    final job = ExportProcessor(renderer, store, cuts, (_) async => null);
    expect(
      (await job.export(script, take, VideoFormat.landscape))!.zoomCount,
      0,
    );
    expect(renderer.request!.toJson().containsKey('zoomSteps'), isFalse);
    job.dispose();
  });
  test('completed zoom export recovers exact targets after failed history save', () async {
    final source = File('${root.path}/generated.mp4');
    await source.writeAsString('generated screen');
    final activity = await activityFor(source);
    final take = Take(
      path: source.path,
      recordedAt: DateTime(2026),
      duration: const Duration(seconds: 4),
      mode: TakeMode.screen,
      activityPath: activity.path,
    );
    final script = ScriptDocument.create().copyWith(takes: [take]);
    await library.save(script);
    final job = ExportProcessor(renderer, store, cuts, (_) async => null);
    renderer.deferred = Completer<void>();
    final result = job.export(script, take, VideoFormat.feed);
    await renderer.started.future;
    final expected = renderer.request!.screenZooms!.toJson();
    final expectedClicks = renderer.request!.screenClicks!.toJson();
    disk.fail = true;
    renderer.deferred!.complete();
    expect(await result, isNull);
    final journal = (await store.pending.list().toList())
        .whereType<File>()
        .single;
    final encoded = jsonDecode(await journal.readAsString()) as Map;
    // A malformed target must never be promoted to finished history.
    final bad = Map<String, Object?>.from(encoded);
    bad['screenZooms'] = {'version': 1, 'count': 2, 'steps': []};
    await journal.writeAsString(jsonEncode(bad));
    disk.fail = false;
    expect(await store.recover(), 0);
    final badClicks = Map<String, Object?>.from(encoded);
    badClicks['screenClicks'] = {'version': 1, 'pulses': []};
    await journal.writeAsString(jsonEncode(badClicks));
    expect(await store.recover(), 0);
    await journal.writeAsString(jsonEncode(encoded));
    // Recovery reads the frozen export track, never the mutable activity file.
    await activity.delete();
    expect(await store.recover(), 1);
    expect(await store.recover(), 0);
    final video = (await store.load(library.byId(script.id)!.takes.single))
        .single;
    expect(video.zoomCount, 1);
    expect(video.clickCount, 2);
    final portable =
        jsonDecode(await store.file(video, 'json').readAsString()) as Map;
    expect(portable['screenZooms'], expected);
    expect(portable['screenClicks'], expectedClicks);
    job.dispose();
  });
}

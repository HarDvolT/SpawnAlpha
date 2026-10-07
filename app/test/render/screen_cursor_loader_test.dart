import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/render/screen_cursor.dart';
import 'package:spawnalpha/src/render/screen_cursor_loader.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/screen_take_store.dart';

import '../storage/screen_take_store_test.dart' show FakeInspector;

Future<ScreenCursor?> _worker((VerifiedCursorSource, CutPlan) job) =>
    loadScreenCursor(job.$1, job.$2);

class MutatingInspector extends FakeInspector {
  Future<void> Function(String)? action;
  @override
  Future<RecordingInfo> inspect(String path) async {
    await action?.call(path);
    return super.inspect(path);
  }
}

void main() {
  late Directory root;
  late ScriptLibrary library;
  late MutatingInspector inspector;
  late Take take;
  late Map<String, Object?> metadata;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('spawnalpha-cursor-loader-');
    library = ScriptLibrary(MemoryScriptStore());
    inspector = MutatingInspector();
  });
  tearDown(() async {
    library.dispose();
    await root.delete(recursive: true);
  });
  Future<void> fixture(ScriptLanguage language, {bool camera = false}) async {
    final script = ScriptDocument.create(
      language: language,
      text: switch (language) {
        ScriptLanguage.en => 'Read this line.',
        ScriptLanguage.fr => 'Lisez cette phrase.',
        ScriptLanguage.ar => 'اقرأ هذه الجملة.',
      },
    );
    await library.save(script);
    final store = ScreenTakeStore(root, library, inspector);
    final pending = await store.reserve(
      presentation: FloatingPresentation(script: script),
      source: const ScreenSource(
        id: 'generated',
        name: 'Generated fixture',
        kind: ScreenSourceKind.window,
        width: 640,
        height: 360,
      ),
      recordAudio: true,
      recordActivity: true,
      pace: 'timed',
      cameraName: camera ? 'Generated camera' : null,
    );
    await File(pending.videoPath)
        .writeAsString('generated original sound and picture');
    await File(pending.cursorFreePath!)
        .writeAsString('generated silent clean picture');
    if (camera) {
      await File(pending.cameraPath!).writeAsString('generated camera');
    }
    inspector.byPath[pending.cursorFreePath!] = const RecordingInfo(
      readable: true,
      width: 640,
      height: 360,
      duration: Duration(seconds: 3),
    );
    await File(pending.activityPath!).writeAsString(
      [
        jsonEncode({
          'type': 'header',
          'version': 1,
          'coordinates': 'sourcePixels',
          'keys': 'timingOnly',
        }),
        for (var ms = 0; ms < 3000; ms += 100)
          jsonEncode({
            'type': 'cursor',
            'timeUs': ms * 1000,
            'width': 640,
            'height': 360,
            'x': ms % 640,
            'y': 180,
            'visible': true,
            'detail': 'arrow',
          }),
        jsonEncode({
          'type': 'end',
          'timeUs': 3000000,
          'events': 30,
          'complete': true,
        }),
        '',
      ].join('\n'),
    );
    take = await store.finish(
      pending,
      const ScreenRecordingStatus(
        phase: ScreenRecordingPhase.finished,
        duration: Duration(seconds: 3),
        frames: 90,
        cursorFreeFrames: 90,
        cursorFreeComplete: true,
        width: 640,
        height: 360,
      ),
    );
    metadata = Map<String, Object?>.from(
      jsonDecode(await File(take.metadataPath!).readAsString()) as Map,
    );
    inspector.inspected.clear();
  }

  Future<void> writeMetadata() =>
      File(take.metadataPath!).writeAsString(jsonEncode(metadata));
  CutPlan plan(ScriptLanguage language, [List<(int, int)>? ranges]) => CutPlan(
    takeId: 'generated',
    language: language,
    sourceDuration: take.duration,
    ranges: (ranges ?? [(0, 3000)])
        .map(
          (r) => SourceRange(
            start: Duration(milliseconds: r.$1),
            end: Duration(milliseconds: r.$2),
          ),
        )
        .toList(),
  );
  for (final language in ScriptLanguage.values) {
    for (final camera in [false, true]) {
      test(
        'saved source proof and worker cursor track preserve originals $language $camera',
        () async {
          await fixture(language, camera: camera);
          final before = await File(take.path).readAsBytes(),
              clean = await File(take.cursorFreePath!).readAsBytes();
          final verified = (await verifyCursorSource(
            Take.fromJson(take.toJson())!,
            inspector,
          ))!;
          expect(verified.originalPath, take.path);
          expect(verified.picturePath, take.cursorFreePath);
          expect(verified.original.hasAudio, isTrue);
          expect(verified.picture.hasAudio, isFalse);
          expect(verified.frames, 90);
          final cut = plan(language, [(1000, 1500), (200, 700), (1000, 1500)]);
          final track = (await compute(_worker, (verified, cut)))!;
          expect(track.duration.inMilliseconds, 1500);
          expect(
            track.steps
                .where((s) => s.reset)
                .map((s) => s.start.inMilliseconds),
            [0, 500, 1000],
          );
          expect(track.steps.length, 15);
          track.validateClock(cut);
          expect(
            jsonEncode(ScreenCursor.fromJson(track.toJson()).toJson()),
            jsonEncode(track.toJson()),
          );
          expect(await File(take.path).readAsBytes(), before);
          expect(await File(take.cursorFreePath!).readAsBytes(), clean);
          expect(await verified.unchanged(), isTrue);
        },
      );
    }
    test(
      'legacy and recovered takes never substitute the recorded pointer $language',
      () async {
        await fixture(language);
        final json = take.toJson();
        for (final patch in <Map<String, Object?>>[
          {'cursorFreePath': null},
          {'activityPath': null},
          {'metadataPath': null},
          {'recovered': true},
          {'mode': 'camera'},
          {'durationUs': 0},
        ]) {
          expect(
            await verifyCursorSource(
              Take.fromJson({...json, ...patch})!,
              inspector,
            ),
            isNull,
          );
        }
        expect(inspector.inspected, isEmpty);
      },
    );
  }
  for (final condition in [
    'state',
    'version',
    'mode',
    'method',
    'proof',
    'readable',
    'frames',
    'clock',
    'clean-clock',
    'id',
    'video',
    'picture',
    'activity',
    'date',
    'consent',
    'activity-count',
    'activity-complete',
  ]) {
    test('manifest rejects unverified cursor data: $condition', () async {
      await fixture(ScriptLanguage.en);
      switch (condition) {
        case 'state':
          metadata['state'] = 'recovered';
        case 'version':
          metadata['version'] = 2;
        case 'mode':
          metadata['mode'] = 'camera';
        case 'method':
          metadata['cursorFreeMethod'] = 'filenameGuess';
        case 'proof':
          metadata.remove('cursorFreeVersion');
        case 'readable':
          metadata['cursorFreeReadable'] = false;
        case 'frames':
          metadata['cursorFreeFrames'] = 89;
        case 'clock':
          metadata['durationUs'] = 3000035;
        case 'clean-clock':
          metadata['cursorFreeDurationUs'] = 3000003;
        case 'id':
          metadata['id'] = '../other';
        case 'video':
          metadata['video'] = 'other-screen.mp4';
        case 'picture':
          metadata['cursorFree'] = 'other-cursor-free.mp4';
        case 'activity':
          metadata['activity'] = 'other-activity.jsonl';
        case 'date':
          metadata['recordedAt'] = DateTime(2001).toIso8601String();
        case 'consent':
          metadata['recordActivity'] = false;
        case 'activity-count':
          (metadata['activitySummary'] as Map)['events'] = 29;
        case 'activity-complete':
          (metadata['activitySummary'] as Map)['complete'] = false;
      }
      await writeMetadata();
      expect(await verifyCursorSource(take, inspector), isNull);
      expect(
        await File(take.path).readAsString(),
        'generated original sound and picture',
      );
    });
  }
  for (final condition in [
    'original-clock',
    'clean-clock',
    'dimensions',
    'original-dimensions',
    'clean-audio',
    'original-audio',
    'unreadable',
    'missing',
    'link',
    'ancestor-link',
    'directory',
    'metadata-size',
    'activity-size',
    'metadata-change',
    'picture-change',
  ]) {
    test(
      'current local file checks reject changed cursor inputs: $condition',
      () async {
        await fixture(ScriptLanguage.en);
        final clean = File(take.cursorFreePath!);
        switch (condition) {
          case 'original-clock':
            inspector.info = const RecordingInfo(
              readable: true,
              hasAudio: true,
              width: 640,
              height: 360,
              duration: Duration(microseconds: 3000001),
            );
          case 'clean-clock':
            inspector.byPath[clean.path] = const RecordingInfo(
              readable: true,
              width: 640,
              height: 360,
              duration: Duration(microseconds: 3000003),
            );
          case 'dimensions':
            inspector.byPath[clean.path] = const RecordingInfo(
              readable: true,
              width: 642,
              height: 360,
              duration: Duration(seconds: 3),
            );
          case 'original-dimensions':
            inspector.info = const RecordingInfo(
              readable: true,
              hasAudio: true,
              width: 642,
              height: 360,
              duration: Duration(seconds: 3),
            );
          case 'clean-audio':
            inspector.byPath[clean.path] = inspector.info;
          case 'original-audio':
            metadata['hasAudio'] = false;
            await writeMetadata();
          case 'unreadable':
            inspector.byPath[clean.path] = const RecordingInfo();
          case 'missing':
            await clean.delete();
          case 'link':
            final target = File('${root.path}/unrelated.mp4');
            await target.writeAsString('unrelated');
            await clean.delete();
            await Link(clean.path).create(target.path);
          case 'ancestor-link':
            final link = Link('${root.path}/alias');
            await link.create(root.path);
            final json = take.toJson();
            for (final name in [
              'path',
              'metadataPath',
              'activityPath',
              'cursorFreePath',
            ]) {
              json[name] = (json[name]! as String).replaceFirst(
                root.path,
                link.path,
              );
            }
            take = Take.fromJson(json)!;
          case 'directory':
            await clean.delete();
            await Directory(clean.path).create();
          case 'metadata-size':
            final file = await File(take.metadataPath!)
                .open(mode: FileMode.writeOnlyAppend);
            await file.truncate(32 * 1024 * 1024 + 1);
            await file.close();
          case 'activity-size':
            final file = await File(take.activityPath!)
                .open(mode: FileMode.writeOnlyAppend);
            await file.truncate(256 * 1024 * 1024 + 1);
            await file.close();
          case 'metadata-change':
            inspector.action = (_) =>
                File(take.metadataPath!).writeAsString('changed');
          case 'picture-change':
            inspector.action = (_) =>
                clean.writeAsString('changed picture bytes');
        }
        expect(await verifyCursorSource(take, inspector), isNull);
      },
    );
  }
  test('two-microsecond companion rounding remains eligible', () async {
    await fixture(ScriptLanguage.fr);
    for (final offset in [-2, 2]) {
      inspector.byPath[take.cursorFreePath!] = RecordingInfo(
        readable: true,
        width: 640,
        height: 360,
        duration: Duration(microseconds: 3000000 + offset),
      );
      metadata['cursorFreeDurationUs'] = 3000000 + offset;
      await writeMetadata();
      expect(await verifyCursorSource(take, inspector), isNotNull);
    }
  });
  for (final condition in [
    'partial',
    'trailing-row',
    'private-field',
    'stale',
    'changed',
    'plan-clock',
  ]) {
    test(
      'activity and worker checks refuse unsafe replacement: $condition',
      () async {
        await fixture(ScriptLanguage.ar);
        final file = File(take.activityPath!);
        final verified = (await verifyCursorSource(take, inspector))!;
        final bytes = await file.readAsString();
        switch (condition) {
          case 'partial':
            await file.writeAsString(
              bytes.replaceFirst('"complete":true', '"complete":false'),
            );
          case 'trailing-row':
            await file.writeAsString('$bytes{"typed":"private');
          case 'private-field':
            await file.writeAsString(
              bytes.replaceFirst(
                '"detail":"arrow"',
                '"detail":"arrow","typed":"private"',
              ),
            );
          case 'stale':
            await file.writeAsString(
              bytes.replaceFirst('"timeUs":100000', '"timeUs":300001'),
            );
          case 'changed':
            await File(take.cursorFreePath!).writeAsString('changed picture');
          case 'plan-clock':
            expect(
              await loadScreenCursor(
                verified,
                CutPlan(
                  takeId: 'generated',
                  language: ScriptLanguage.ar,
                  sourceDuration: const Duration(seconds: 2),
                  ranges: [
                    SourceRange(
                      start: Duration.zero,
                      end: const Duration(seconds: 2),
                    ),
                  ],
                ),
              ),
              isNull,
            );
        }
        if (condition != 'plan-clock') {
          expect(
            await loadScreenCursor(verified, plan(ScriptLanguage.ar)),
            isNull,
          );
          expect(await verified.unchanged(), isFalse);
        }
        if (condition != 'changed' && condition != 'plan-clock') {
          expect(await verifyCursorSource(take, inspector), isNull);
        }
      },
    );
  }
  test(
    'Windows remote and alternate stream metadata paths fail before I/O',
    () async {
      if (!Platform.isWindows) return;
      await fixture(ScriptLanguage.en);
      for (final path in [
        r'\\server\share\take.json',
        '${take.metadataPath}:private',
        'relative.json',
      ]) {
        expect(
          await verifyCursorSource(
            Take.fromJson({...take.toJson(), 'metadataPath': path})!,
            inspector,
          ),
          isNull,
        );
      }
      expect(inspector.inspected, isEmpty);
    },
  );
}

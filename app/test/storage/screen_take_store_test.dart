import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/screen_take_store.dart';

import '../recording/activity_trace_test.dart' show generatedActivity;

class FakeInspector implements RecordingInspector {
  final inspected = <String>[];
  final byPath = <String, RecordingInfo>{};
  RecordingInfo info = const RecordingInfo(
    readable: true,
    hasAudio: true,
    width: 640,
    height: 360,
    duration: Duration(seconds: 3),
  );
  @override
  Future<RecordingInfo> inspect(String path) async {
    inspected.add(path);
    return byPath[path] ?? info;
  }
}

class FailingStore extends MemoryScriptStore {
  bool fail = false;
  @override
  Future<void> save(ScriptDocument script) async {
    if (fail) throw const FileSystemException('Fixture write failure');
    await super.save(script);
  }
}

void main() {
  late Directory directory;
  late FailingStore scripts;
  late ScriptLibrary library;
  late FakeInspector inspector;
  late ScreenTakeStore store;
  const source = ScreenSource(
    id: 'private-hwnd',
    name: 'Chosen source',
    kind: ScreenSourceKind.window,
    width: 640,
    height: 360,
  );
  const status = ScreenRecordingStatus(
    phase: ScreenRecordingPhase.finished,
    frames: 90,
    audioFrames: 144000,
    duration: Duration(seconds: 3),
    loudestRmsDb: -20,
  );
  ScriptDocument script(ScriptLanguage language) => ScriptDocument(
    id: 'script',
    title: 'Fixture',
    text: switch (language) {
      ScriptLanguage.en => 'Read this line.',
      ScriptLanguage.fr => 'Lisez cette phrase.',
      ScriptLanguage.ar => 'اقرأ هذه الجملة.',
    },
    language: language,
    style: CoachingStyle.presentation,
  );
  Future<PendingScreenTake> reserve(
    ScriptDocument script, {
    String? cameraName,
  }) => store.reserve(
    presentation: FloatingPresentation(script: script),
    source: source,
    recordAudio: true,
    microphoneName: 'Chosen microphone',
    cameraName: cameraName,
    pace: 'voice',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('spawnalpha-take-test-');
    scripts = FailingStore();
    library = ScriptLibrary(scripts);
    inspector = FakeInspector();
    store = ScreenTakeStore(directory, library, inspector);
  });
  tearDown(() async {
    library.dispose();
    await directory.delete(recursive: true);
  });

  for (final language in ScriptLanguage.values) {
    test('verified cursor-free companion stays frozen in $language', () async {
      await library.save(script(language));
      final pending = await store.reserve(
        presentation: FloatingPresentation(script: script(language)),
        source: source,
        recordAudio: true,
        recordActivity: true,
        pace: 'voice',
      );
      expect(pending.cursorFreePath, endsWith('${pending.id}-cursor-free.mp4'));
      await File(pending.videoPath).writeAsString('original');
      await File(pending.cursorFreePath!)
          .writeAsString('generated clean pictures');
      inspector.byPath[pending.cursorFreePath!] = const RecordingInfo(
        readable: true,
        width: 640,
        height: 360,
        duration: Duration(seconds: 3),
      );
      final take = await store.finish(
        pending,
        const ScreenRecordingStatus(
          phase: ScreenRecordingPhase.finished,
          width: 640,
          height: 360,
          frames: 90,
          cursorFreeFrames: 90,
          cursorFreeComplete: true,
          duration: Duration(seconds: 3),
        ),
      );
      expect(take.cursorFreePath, pending.cursorFreePath);
      for (final version in [
        take,
        take.withWords('new words'),
        take.withCut('new cut'),
        take.withExports('new history'),
      ]) {
        expect(
          Take.fromJson(version.toJson())!.cursorFreePath,
          pending.cursorFreePath,
        );
      }
      final metadata =
          jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
      expect(metadata['cursorFreeReadable'], isTrue);
      expect(metadata['cursorFreeMethod'], 'wgcCursorExcluded');
      expect(metadata['cursorFreeVersion'], 1);
      expect(metadata['cursorFreeFrames'], 90);
      expect(metadata['cursorFreeDurationUs'], 3000000);
      expect(await File(take.path).readAsString(), 'original');
    });
    test(
      'recovered companion is ineligible without finalized proof in $language',
      () async {
        await library.save(script(language));
        final pending = await store.reserve(
          presentation: FloatingPresentation(script: script(language)),
          source: source,
          recordAudio: false,
          recordActivity: true,
          pace: 'voice',
        );
        await File(pending.videoPath).writeAsString('original');
        await File(pending.cursorFreePath!).writeAsString('partial clean');
        inspector.byPath[pending.cursorFreePath!] = const RecordingInfo(
          readable: true,
          width: 640,
          height: 360,
          duration: Duration(seconds: 3),
        );
        expect(await store.recover(), 1);
        expect(library.scripts.single.takes.single.cursorFreePath, isNull);
        expect(inspector.inspected, isNot(contains(pending.cursorFreePath)));
        expect(
          await File(pending.cursorFreePath!).readAsString(),
          'partial clean',
        );
      },
    );
    test(
      'activity consent and truncated trace survive $language recovery',
      () async {
        final original = script(language);
        await library.save(original);
        final pending = await store.reserve(
          presentation: FloatingPresentation(script: original),
          source: source,
          recordAudio: false,
          recordActivity: true,
          pace: 'timed',
        );
        final metadata =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect(metadata['recordActivity'], isTrue);
        expect(metadata['activity'], '${pending.id}-activity.jsonl');
        await File(pending.videoPath).writeAsString('generated video');
        await File(pending.activityPath!)
            .writeAsString('${generatedActivity(complete: false)}{"type":');
        expect(await store.recover(), 1);
        final take = library.byId(original.id)!.takes.single;
        expect(take.activityPath, pending.activityPath);
        expect(take.recovered, isTrue);
        expect(Take.fromJson(take.toJson())!.activityPath, take.activityPath);
        final after =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect(after['activityReadable'], isTrue);
        expect((after['activitySummary'] as Map)['complete'], isFalse);
        expect(await store.recover(), 0);
      },
    );
  }

  for (final offsetUs in [-35, -34, 34, 35]) {
    test(
      'cursor proof permits only one MP4 track tick: $offsetUs us',
      () async {
        await library.save(script(ScriptLanguage.en));
        final pending = await store.reserve(
          presentation: FloatingPresentation(script: script(ScriptLanguage.en)),
          source: source,
          recordAudio: false,
          recordActivity: true,
          pace: 'timed',
        );
        await File(pending.videoPath).writeAsString('original');
        await File(pending.cursorFreePath!).writeAsString('clean');
        inspector.byPath[pending.cursorFreePath!] = const RecordingInfo(
          readable: true,
          width: 640,
          height: 360,
          duration: Duration(seconds: 3),
        );
        final take = await store.finish(
          pending,
          ScreenRecordingStatus(
            phase: ScreenRecordingPhase.finished,
            width: 640,
            height: 360,
            frames: 90,
            cursorFreeFrames: 90,
            cursorFreeComplete: true,
            duration: Duration(microseconds: 3000000 + offsetUs),
          ),
        );
        expect(
          take.cursorFreePath,
          offsetUs.abs() <= 34 ? pending.cursorFreePath : null,
        );
        expect(await File(pending.videoPath).readAsString(), 'original');
      },
    );
  }
  for (final condition in [
    'partial',
    'frames',
    'clock',
    'audio',
    'size',
    'short',
    'missing',
    'link',
  ]) {
    test('cursor companion $condition preserves the original', () async {
      await library.save(script(ScriptLanguage.en));
      final pending = await store.reserve(
        presentation: FloatingPresentation(script: script(ScriptLanguage.en)),
        source: source,
        recordAudio: false,
        recordActivity: true,
        pace: 'voice',
      );
      await File(pending.videoPath).writeAsString('original');
      if (condition == 'link') {
        final target = File(
          '${directory.path}${Platform.pathSeparator}unrelated.mp4',
        );
        await target.writeAsString('unrelated');
        await Link(pending.cursorFreePath!).create(target.absolute.path);
      } else if (condition != 'missing') {
        await File(pending.cursorFreePath!)
            .writeAsString('preserve clean bytes');
      }
      inspector.byPath[pending.cursorFreePath!] = RecordingInfo(
        readable: true,
        hasAudio: condition == 'audio',
        width: condition == 'size' ? 320 : 640,
        height: 360,
        duration: Duration(seconds: condition == 'short' ? 2 : 3),
      );
      final take = await store.finish(
        pending,
        ScreenRecordingStatus(
          phase: ScreenRecordingPhase.finished,
          width: 640,
          height: 360,
          frames: 90,
          cursorFreeFrames: condition == 'frames' ? 89 : 90,
          cursorFreeComplete: condition != 'partial',
          duration: Duration(seconds: condition == 'clock' ? 2 : 3),
        ),
      );
      expect(take.cursorFreePath, isNull);
      expect(await File(take.path).readAsString(), 'original');
      if (condition != 'missing') {
        expect(
          await File(pending.cursorFreePath!).readAsString(),
          condition == 'link' ? 'unrelated' : 'preserve clean bytes',
        );
      }
      if ([
        'partial',
        'frames',
        'clock',
        'missing',
        'link',
      ].contains(condition)) {
        expect(inspector.inspected, isNot(contains(pending.cursorFreePath)));
      }
      final metadata =
          jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
      expect(metadata['cursorFreeReadable'], isFalse);
      expect(metadata.containsKey('cursorFreeMethod'), isFalse);
    });
  }

  test('bad or missing activity preserves the video and local bytes', () async {
    final original = script(ScriptLanguage.en);
    await library.save(original);
    for (final contents in [null, 'private malformed data\n']) {
      final pending = await store.reserve(
        presentation: FloatingPresentation(script: original),
        source: source,
        recordAudio: false,
        recordActivity: true,
        pace: 'timed',
      );
      if (contents != null) {
        await File(pending.activityPath!).writeAsString(contents);
      }
      final take = await store.finish(pending, status);
      expect(take.activityPath, isNull);
      final metadata =
          jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
      expect(metadata['activityReadable'], isFalse);
      if (contents != null) {
        expect(await File(pending.activityPath!).readAsString(), contents);
      }
    }
  });

  test('recovery rejects substituted activity names and links', () async {
    final original = script(ScriptLanguage.en);
    await library.save(original);
    final pending = await store.reserve(
      presentation: FloatingPresentation(script: original),
      source: source,
      recordAudio: false,
      recordActivity: true,
      pace: 'timed',
    );
    await File(pending.videoPath).writeAsString('generated video');
    final metadata =
        jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
    metadata['activity'] = '../outside.jsonl';
    await File(pending.metadataPath).writeAsString(jsonEncode(metadata));
    expect(await store.recover(), 0);
    metadata['activity'] = '${pending.id}-activity.jsonl';
    await File(pending.metadataPath).writeAsString(jsonEncode(metadata));
    final target = File('${directory.path}/fixture.jsonl');
    await target.writeAsString(generatedActivity());
    await Link(pending.activityPath!).create(target.absolute.path);
    expect(await store.recover(), 0);
    expect(library.byId(original.id)!.takes, isEmpty);
  });

  for (final language in ScriptLanguage.values) {
    test(
      'flushed snapshot and take survive later edits in ${language.name}',
      () async {
        final original = script(language);
        await library.save(original);
        final pending = await reserve(original);
        final before =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect(before['state'], 'pending');
        expect(before['recordSystemAudio'], isFalse);
        expect(before['systemAudioScope'], isNull);
        expect((before['script'] as Map)['text'], original.text);
        expect(jsonEncode(before), isNot(contains(source.id)));
        expect(await File(pending.videoPath).exists(), isFalse);
        await library.save(original.withText('${original.text} More.'));
        final take = await store.finish(pending, status);
        expect(take.mode, TakeMode.screen);
        expect(take.duration, const Duration(seconds: 3));
        expect(library.byId(original.id)!.text, '${original.text} More.');
        final after =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect(after['state'], 'saved');
        expect((after['script'] as Map)['text'], original.text);
        expect(await store.recover(), 0);
      },
    );
  }

  for (final language in ScriptLanguage.values) {
    test(
      'computer-sound consent stays with the recovered $language take',
      () async {
        final original = script(language);
        await library.save(original);
        final pending = await store.reserve(
          presentation: FloatingPresentation(script: original),
          source: source,
          recordAudio: false,
          recordSystemAudio: true,
          pace: 'timed',
        );
        final before =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect(before['recordSystemAudio'], isTrue);
        expect(before['recordAudio'], isFalse);
        expect(before['systemAudioScope'], 'windowsPlaybackMix');
        expect(jsonEncode(before), isNot(contains(source.id)));
        await File(pending.videoPath).writeAsString('generated fixture');
        await library.save(original.withText('${original.text} More.'));
        expect(await store.recover(), 1);
        expect(await store.recover(), 0);
        final after =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect(after['state'], 'recovered');
        expect(after['recordSystemAudio'], isTrue);
        expect(after['recordAudio'], isFalse);
        expect(library.byId(original.id)!.text, '${original.text} More.');
      },
    );
  }

  test(
    'crash recovery adds one take, preserves edits and never duplicates it',
    () async {
      final original = script(ScriptLanguage.en);
      await library.save(original);
      final pending = await reserve(original);
      await File(pending.videoPath).writeAsBytes([1]);
      await library.save(original.withText('Later script version.'));
      expect(await store.recover(), 1);
      expect(await store.recover(), 0);
      final restored = library.byId(original.id)!;
      expect(restored.text, 'Later script version.');
      expect(restored.takes, hasLength(1));
      expect(restored.takes.single.recovered, isTrue);
      final take = Take.fromJson(restored.takes.single.toJson())!;
      expect(take.metadataPath, pending.metadataPath);
      expect(take.recovered, isTrue);
      expect(take.mode, TakeMode.screen);
    },
  );

  test(
    'failed library save keeps pending data and retry persists one take',
    () async {
      final original = script(ScriptLanguage.en);
      await library.save(original);
      final pending = await reserve(original);
      await File(pending.videoPath).writeAsBytes([1]);
      scripts.fail = true;
      await expectLater(
        store.finish(pending, status),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        (jsonDecode(await File(pending.metadataPath).readAsString())
            as Map)['state'],
        'pending',
      );
      scripts.fail = false;
      expect(await store.recover(), 1);
      expect(scripts.scripts[original.id]!.takes, hasLength(1));
    },
  );

  test(
    'unreadable and missing files remain local without adding takes',
    () async {
      final original = script(ScriptLanguage.en);
      await library.save(original);
      final pending = await reserve(original);
      expect(await store.recover(), 0);
      await File(pending.videoPath).writeAsBytes([1]);
      inspector.info = const RecordingInfo();
      expect(await store.recover(), 0);
      expect(await File(pending.metadataPath).exists(), isTrue);
      expect(library.byId(original.id)!.takes, isEmpty);
    },
  );

  test('recovery rejects paths outside the take folder and preserves deleted scripts', () async {
    final original = script(ScriptLanguage.en);
    await library.save(original);
    final pending = await reserve(original);
    final metadata = jsonDecode(
      await File(pending.metadataPath).readAsString(),
    ) as Map<String, dynamic>;
    metadata['video'] = '../private.mp4';
    await File(pending.metadataPath).writeAsString(jsonEncode(metadata));
    expect(await store.recover(), 0);
    expect(inspector.inspected, isEmpty);
    metadata['video'] = '${pending.id}-screen.mp4';
    await File(pending.metadataPath).writeAsString(jsonEncode(metadata));
    await File(pending.videoPath).writeAsBytes([1]);
    await library.delete(original.id);
    expect(await store.recover(), 0);
    expect(library.scripts, isEmpty);
  });

  test(
    'legacy camera take remains readable and new take retains both paths',
    () {
      final old = Take.fromJson({
        'path': 'camera.mp4',
        'recordedAt': '2026-10-05',
        'durationMs': 1000,
      })!;
      expect(old.mode, TakeMode.camera);
      expect(old.metadataPath, isNull);
      final both = Take(
        path: 'screen.mp4',
        cameraPath: 'camera.mp4',
        metadataPath: 'manifest.json',
        mode: TakeMode.both,
        recordedAt: old.recordedAt,
        duration: old.duration,
      );
      final restored = Take.fromJson(both.toJson())!;
      expect(restored.mode, TakeMode.both);
      expect(restored.cameraPath, 'camera.mp4');
    },
  );

  for (final language in ScriptLanguage.values) {
    test(
      'paired snapshot, files and recovery survive edits in ${language.name}',
      () async {
        final original = script(language);
        await library.save(original);
        final name = switch (language) {
          ScriptLanguage.en => 'Chosen camera',
          ScriptLanguage.fr => 'Caméra choisie',
          ScriptLanguage.ar => 'الكاميرا المختارة',
        };
        final pending = await reserve(original, cameraName: name);
        final before =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect(before['mode'], 'both');
        expect(before['camera'], '${pending.id}-camera.mp4');
        expect(before['cameraName'], name);
        expect(before.containsKey('cameraId'), isFalse);
        await File(pending.videoPath).writeAsBytes([1]);
        await File(pending.cameraPath!).writeAsBytes([2]);
        await library.save(original.withText('${original.text} Later.'));
        expect(await store.recover(), 1);
        final take = library.byId(original.id)!.takes.single;
        expect(take.mode, TakeMode.both);
        expect(take.cameraPath, pending.cameraPath);
        expect(take.recovered, isTrue);
        expect(library.byId(original.id)!.text, '${original.text} Later.');
        final after =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect((after['script'] as Map)['text'], original.text);
        expect(after['cameraReadable'], isTrue);
        expect(after['cameraDurationUs'], 3000000);
        expect(await store.recover(), 0);
      },
    );
  }

  test(
    'normal paired finish saves both paths with separate verified details',
    () async {
      final original = script(ScriptLanguage.en);
      await library.save(original);
      final pending = await reserve(original, cameraName: 'Chosen camera');
      await File(pending.cameraPath!).writeAsBytes([2]);
      inspector.byPath[pending.cameraPath!] = const RecordingInfo(
        readable: true,
        width: 1280,
        height: 720,
        duration: Duration(seconds: 3),
      );
      final take = await store.finish(pending, status);
      expect(take.mode, TakeMode.both);
      expect(take.cameraPath, pending.cameraPath);
      final metadata =
          jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
      expect(metadata['hasAudio'], isTrue);
      expect(metadata['cameraWidth'], 1280);
      expect(metadata['cameraHeight'], 720);
      expect(metadata['cameraReadable'], isTrue);
    },
  );

  test(
    'missing or unreadable camera preserves the screen and camera data',
    () async {
      final original = script(ScriptLanguage.en);
      await library.save(original);
      for (final missing in [true, false]) {
        final pending = await reserve(original, cameraName: 'Chosen camera');
        await File(pending.videoPath).writeAsBytes([1]);
        if (!missing) {
          await File(pending.cameraPath!).writeAsBytes([2]);
          inspector.byPath[pending.cameraPath!] = const RecordingInfo();
        }
        expect(await store.recover(), 1);
        final take = library.byId(original.id)!.takes.last;
        expect(take.mode, TakeMode.screen);
        expect(take.cameraPath, isNull);
        final metadata =
            jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
        expect(metadata['mode'], 'both');
        expect(metadata['cameraReadable'], isFalse);
        if (!missing) {
          expect(await File(pending.cameraPath!).readAsBytes(), [2]);
        }
      }
    },
  );

  test('paired recovery rejects an external camera path', () async {
    final original = script(ScriptLanguage.en);
    await library.save(original);
    final pending = await reserve(original, cameraName: 'Chosen camera');
    await File(pending.videoPath).writeAsBytes([1]);
    final metadata =
        jsonDecode(await File(pending.metadataPath).readAsString()) as Map;
    metadata['camera'] = '../private.mp4';
    await File(pending.metadataPath).writeAsString(jsonEncode(metadata));
    expect(await store.recover(), 0);
    expect(inspector.inspected, isEmpty);
    expect(library.byId(original.id)!.takes, isEmpty);
  });

  test(
    'paired save failure keeps a manifest and persists one pair on retry',
    () async {
      final original = script(ScriptLanguage.en);
      await library.save(original);
      final pending = await reserve(original, cameraName: 'Chosen camera');
      await File(pending.videoPath).writeAsBytes([1]);
      await File(pending.cameraPath!).writeAsBytes([2]);
      scripts.fail = true;
      await expectLater(
        store.finish(pending, status),
        throwsA(isA<FileSystemException>()),
      );
      scripts.fail = false;
      expect(await store.recover(), 1);
      expect(await store.recover(), 0);
      expect(scripts.scripts[original.id]!.takes, hasLength(1));
      expect(
        scripts.scripts[original.id]!.takes.single.cameraPath,
        pending.cameraPath,
      );
    },
  );
}

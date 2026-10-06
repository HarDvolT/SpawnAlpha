import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/recording/recording_hud.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/recording/screen_take_controller.dart';
import 'package:spawnalpha/src/storage/screen_take_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import '../storage/screen_take_store_test.dart' show FakeInspector;

class TestHuds implements RecordingHuds {
  TestHuds(this.events);
  final List<String> events;
  final stream = StreamController<HudCommand>.broadcast(sync: true);
  final states = <HudState>[];
  Completer<HudHandle>? delayed;
  bool reject = false;
  @override
  Stream<HudCommand> get commands => stream.stream;
  @override
  Future<HudHandle> open(ScreenSource source) async {
    events.add('protect');
    if (reject) throw Exception('private source detail');
    return delayed?.future ?? const HudHandle(7);
  }
  @override
  Future<bool> isOpen(HudHandle handle) async => true;
  @override
  Future<void> update(HudHandle handle, HudState state) async => states.add(state);
  @override
  Future<void> close(HudHandle handle) async => events.add('unprotect');
}
class TestReader implements FloatingPrompters {
  TestReader(this.events);
  final List<String> events;
  final states = <FloatingRecordingState>[];
  bool visible = true;
  @override
  bool get supported => true;
  @override
  Future<FloatingHandle> open(FloatingPresentation presentation) async { events.add('reader'); return const FloatingHandle(4); }
  @override
  Future<bool> isOpen(FloatingHandle handle) async => visible;
  @override
  Future<void> close(FloatingHandle handle) async => events.add('reader-close');
  @override
  Future<void> update(FloatingHandle handle, FloatingRecordingState state) async => states.add(state);
  @override
  Future<void> show(FloatingHandle handle, bool value) async { visible = value; events.add('reader-show'); }
  @override
  Future<void> lock(FloatingHandle handle) async => events.add('lock');
}
class TestRecorder implements ScreenRecordings {
  TestRecorder(this.events);
  final List<String> events;
  int polls = 0;
  bool stopped = false, paused = false, releaseFails = false;
  ScreenRecordingReason reason = ScreenRecordingReason.none;
  Future<void> Function(int)? onStatus;
  bool? audio;
  String? microphone;
  @override
  bool get supported => true;
  @override
  Future<ScreenRecordingHandle> start({required ScreenSource source, required String path, required bool recordAudio, String? microphoneId, String? cameraId, String? cameraPath}) async {
    expect(await File(path.replaceFirst('-screen.mp4', '.json')).exists(), isTrue);
    events.add('capture'); audio = recordAudio; microphone = microphoneId;
    await File(path).writeAsString('fixture', flush: true);
    return const ScreenRecordingHandle(3);
  }
  @override
  Future<ScreenRecordingStatus> status(ScreenRecordingHandle handle) async {
    await onStatus?.call(++polls);
    return ScreenRecordingStatus(phase: stopped ? ScreenRecordingPhase.finished : paused ? ScreenRecordingPhase.paused : ScreenRecordingPhase.recording,
      reason: reason, duration: const Duration(seconds: 3), frames: 90, audioFrames: audio == true ? 144000 : 0,
      loudestRmsDb: -20, rmsDb: -20, peakDb: -10);
  }
  @override
  Future<void> stop(ScreenRecordingHandle handle) async { stopped = true; events.add('stop'); }
  @override
  Future<void> pause(ScreenRecordingHandle handle, bool value) async { paused = value; events.add(value ? 'pause' : 'resume'); }
  @override
  Future<void> release(ScreenRecordingHandle handle) async {
    events.add('release');
    if (releaseFails) throw Exception('private native failure');
  }
}

void main() {
  late Directory dir;
  late ScriptLibrary library;
  late TestHuds huds;
  late TestReader reader;
  late TestRecorder recorder;
  late ScreenTakeController owner;
  late List<String> events;
  const source = ScreenSource(id: 'window:fixture', name: 'Fixture', kind: ScreenSourceKind.window, width: 640, height: 360);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('spawnalpha-owner-test-');
    library = ScriptLibrary(MemoryScriptStore());
    events = [];
    huds = TestHuds(events); reader = TestReader(events); recorder = TestRecorder(events);
    owner = ScreenTakeController(recorder: recorder, huds: huds, floating: reader,
      store: ScreenTakeStore(dir, library, FakeInspector()), wait: (_) => Future<void>.delayed(Duration.zero));
  });
  tearDown(() async { owner.dispose(); await huds.stream.close(); library.dispose(); await dir.delete(recursive: true); });
  Future<void> start(ScriptLanguage language, {bool audio = true}) async {
    final script = ScriptDocument.create(language: language, text: switch (language) {
      ScriptLanguage.en => 'Read the line.', ScriptLanguage.fr => 'Lisez cette phrase.', ScriptLanguage.ar => 'اقرأ هذه الجملة.',
    });
    await library.save(script);
    await owner.start(presentation: FloatingPresentation(script: script), source: source,
      recordAudio: audio, microphoneId: 'chosen', microphoneName: 'Chosen microphone');
  }
  for (final language in ScriptLanguage.values) {
    test('protected countdown, saved $language take and release ordering', () async {
      recorder.onStatus = (n) async { if (n == 3) owner.stop(); };
      await start(language);
      expect(owner.phase, ScreenTakePhase.saved);
      expect(owner.take!.mode, TakeMode.screen);
      expect(library.scripts.single.takes, hasLength(1));
      expect(events.take(3), ['protect', 'reader', 'capture']);
      expect(events.indexOf('release'), lessThan(events.indexOf('unprotect')));
      expect(huds.states.where((s) => s.phase == HudPhase.countdown).map((s) => s.countdown), [3, 2, 1]);
      expect(reader.states.any((s) => s.active), isTrue);
      expect(recorder.microphone, 'chosen');
      expect(recorder.audio, isTrue);
      expect(owner.busy, isFalse);
    });
  }
  test('HUD session guards, pause/resume, reader visibility and explicit silent take', () async {
    recorder.onStatus = (n) async {
      if (n == 2) {
        huds.stream.add(const HudCommand(99, 'stop'));
        await owner.togglePause();
        await owner.togglePrompter();
        await owner.lockPrompter();
      }
      if (n == 3) await owner.togglePause();
      if (n == 4) owner.stop();
    };
    await start(ScriptLanguage.en, audio: false);
    expect(recorder.audio, isFalse);
    expect(events, containsAllInOrder(['pause', 'reader-show', 'lock', 'resume', 'stop', 'release', 'unprotect']));
    expect(reader.states.any((s) => s.paused), isTrue);
    expect(owner.take, isNotNull);
    expect(owner.problem, isNull);
  });
  test('cancelled countdown never starts capture or leaves a pending manifest', () async {
    var beats = 0;
    owner.dispose();
    owner = ScreenTakeController(recorder: recorder, huds: huds, floating: reader,
      store: ScreenTakeStore(dir, library, FakeInspector()), wait: (d) async { if (d == SaDurations.beat && ++beats == 2) owner.stop(); });
    await start(ScriptLanguage.en);
    expect(events, ['protect', 'reader', 'reader-close', 'unprotect']);
    expect(await dir.list().isEmpty, isTrue);
    expect(owner.phase, ScreenTakePhase.idle);
  });
  test('failed exclusion prevents capture and keeps private errors out of UI', () async {
    huds.reject = true;
    await start(ScriptLanguage.en);
    expect(events, ['protect']);
    expect(owner.phase, ScreenTakePhase.failed);
    expect(owner.problem, isNot(contains('private')));
  });
  test('disposal owns a late protected window and closes it without capture', () async {
    huds.delayed = Completer<HudHandle>();
    final script = ScriptDocument.create(text: 'Fixture.');
    final run = owner.start(presentation: FloatingPresentation(script: script), source: source, recordAudio: false);
    await Future<void>.delayed(Duration.zero);
    owner.dispose();
    huds.delayed!.complete(const HudHandle(7));
    await run;
    expect(events, ['protect', 'unprotect']);
    // This owner has already been disposed; use a fresh idle owner for teardown.
    owner = ScreenTakeController(recorder: recorder, huds: huds, floating: reader, store: ScreenTakeStore(dir, library, FakeInspector()));
  });
  test('source loss keeps the readable part and explains the reason', () async {
    recorder.onStatus = (n) async { if (n == 2) { recorder.stopped = true; recorder.reason = ScreenRecordingReason.source; } };
    await start(ScriptLanguage.en);
    expect(owner.take, isNotNull);
    expect(owner.problem, contains('source'));
    expect(events.last, 'unprotect');
  });
  test('failed native release keeps capture protection and blocks a second take', () async {
    recorder.releaseFails = true;
    recorder.onStatus = (n) async { if (n == 2) owner.stop(); };
    await start(ScriptLanguage.en);
    expect(owner.busy, isTrue);
    expect(events, isNot(contains('unprotect')));
    expect(owner.problem, isNot(contains('private')));
    final before = events.length;
    await start(ScriptLanguage.fr);
    expect(events.length, before);
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/prompter/guide.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/recording/floating_trial_controller.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/theme/theme.dart';

class FakeFloatingPrompters implements FloatingPrompters {
  @override
  Future<void> update(FloatingHandle handle, FloatingRecordingState state) async {}
  @override
  Future<void> show(FloatingHandle handle, bool visible) async {}
  @override
  Future<void> lock(FloatingHandle handle) async {}
  @override
  bool get supported => true;
  Completer<FloatingHandle>? pending;
  Object? problem;
  final closed = <int>[];
  int opened = 0;
  bool visible = true;
  @override
  Future<bool> isOpen(FloatingHandle handle) async => visible;
  @override
  Future<FloatingHandle> open(FloatingPresentation presentation) async {
    ++opened;
    if (problem != null) throw problem!;
    return pending == null ? FloatingHandle(opened) : pending!.future;
  }
  @override
  Future<void> close(FloatingHandle handle) async => closed.add(handle.sessionId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final language in ScriptLanguage.values) {
    test('presentation preserves $language and choices without takes or keys', () {
      final script = ScriptDocument.create(text: switch (language) {
        ScriptLanguage.en => 'A clear voice. A new phrase.',
        ScriptLanguage.fr => 'Une voix claire. Une nouvelle phrase.',
        ScriptLanguage.ar => 'صوت واضح. عبارة جديدة.',
      }, language: language).copyWith(takes: [Take(path: 'private.mp4', recordedAt: DateTime(2026), duration: Duration.zero)]);
      final settings = Settings(secrets: MemorySecretStore())
        ..guide = PrompterGuide.underline ..motion = PrompterMotion.smooth
        ..alignment = PrompterAlignment.right ..mirror = true ..kinetic = false;
      final wire = FloatingPresentation.fromSettings(script, settings).encode();
      expect(wire, isNot(contains('private.mp4')));
      final fields = jsonDecode(wire) as Map;
      expect(fields.keys, unorderedEquals(['script', 'guide', 'motion', 'alignment', 'kinetic', 'mirror', 'pace']));
      final decoded = FloatingPresentation.decode(wire);
      expect(decoded.script.text, script.text);
      expect(decoded.script.language, language);
      expect(decoded.guide, PrompterGuide.underline);
      expect(decoded.motion, PrompterMotion.smooth);
      expect(decoded.alignment, PrompterAlignment.right);
      expect(decoded.mirror, isTrue);
      expect(decoded.kinetic, isFalse);
      expect(decoded.script.takes, isEmpty);
    });
  }
  final presentation = FloatingPresentation(script: ScriptDocument.create(text: 'A test phrase.'));
  test('native window must be excluded and visible before open completes', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      WindowsFloatingPrompters.channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'open' => 12,
          'status' => {'excluded': true, 'visible': true},
          _ => null,
        };
      });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(WindowsFloatingPrompters.channel, null));
    const backend = WindowsFloatingPrompters();
    final handle = await backend.open(presentation);
    expect(handle.sessionId, 12);
    await backend.close(handle);
    expect(calls.map((call) => call.method), ['open', 'status', 'close']);
    expect((calls.last.arguments as Map)['sessionId'], 12);
  });
  test('failed exclusion releases the native session', () async {
    final closed = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      WindowsFloatingPrompters.channel, (call) async {
        if (call.method == 'open') return 3;
        if (call.method == 'status') return {'excluded': false, 'visible': false};
        if (call.method == 'close') closed.add((call.arguments as Map)['sessionId'] as int);
        return null;
      });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(WindowsFloatingPrompters.channel, null));
    await expectLater(const WindowsFloatingPrompters().open(presentation), throwsFormatException);
    expect(closed, [3]);
  });
  test('late open after page disposal closes its session and duplicate tap is ignored', () async {
    final backend = FakeFloatingPrompters()..pending = Completer<FloatingHandle>();
    final controller = FloatingTrialController(backend, presentation);
    final opening = controller.toggle();
    await controller.toggle();
    expect(backend.opened, 1);
    controller.dispose();
    backend.pending!.complete(const FloatingHandle(4));
    await opening;
    expect(backend.closed, [4]);
  });
  test('errors are generic and retry releases the successful window', () async {
    final backend = FakeFloatingPrompters()..problem = Exception('private script and path');
    final controller = FloatingTrialController(backend, presentation);
    await controller.toggle();
    expect(controller.problem, isNot(contains('private')));
    backend.problem = null;
    await controller.toggle();
    expect(controller.visible, isTrue);
    await controller.toggle();
    expect(controller.visible, isFalse);
    expect(backend.closed, [2]);
    controller.dispose();
  });
  test('closing the child window releases its session and updates the preview', () {
    fakeAsync((time) {
      final backend = FakeFloatingPrompters();
      final controller = FloatingTrialController(backend, presentation);
      unawaited(controller.toggle());
      time.flushMicrotasks();
      expect(controller.visible, isTrue);
      backend.visible = false;
      time.elapse(SaDurations.previewPoll);
      time.flushMicrotasks();
      expect(controller.visible, isFalse);
      expect(backend.closed, [1]);
      expect(time.periodicTimerCount, 0);
      controller.dispose();
    });
  });
}

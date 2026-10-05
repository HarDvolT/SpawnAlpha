import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/screen_preview.dart';
import 'package:spawnalpha/src/recording/screen_preview_controller.dart';

import 'screen_source_test.dart' show display;

const handle = PreviewHandle(sessionId: 1, textureId: 10, width: 1920, height: 1080);

class FakeScreenPreviews implements ScreenPreviews {
  Future<PreviewHandle> Function()? opening;
  Future<PreviewStatus> Function()? checking;
  PreviewStatus current = const PreviewStatus(width: 1920, height: 1080, ready: true);
  final stopped = <int>[];
  int nextId = 0;
  @override
  bool get supported => true;
  @override
  Future<PreviewHandle> start(source) async => opening != null ? opening!() : PreviewHandle(
    sessionId: ++nextId, textureId: 10, width: source.width, height: source.height);
  @override
  Future<PreviewStatus> status(PreviewHandle handle) async => checking != null ? checking!() : current;
  @override
  Future<void> stop(PreviewHandle handle) async => stopped.add(handle.sessionId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native channel sends only an opaque source ID and stops the exact session', () async {
    final calls = <String>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(WindowsScreenPreviews.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') {
        expect(call.arguments, {'sourceId': display.id});
        return {'sessionId': 1, 'textureId': 10, 'width': 1920, 'height': 1080};
      }
      expect(call.arguments, {'sessionId': 1});
      return call.method == 'status' ? {'ready': true, 'width': 1920, 'height': 1080} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(WindowsScreenPreviews.channel, null));
    const backend = WindowsScreenPreviews();
    final opened = await backend.start(display);
    expect((await backend.status(opened)).ready, isTrue);
    await backend.stop(opened);
    expect(calls, ['start', 'status', 'stop']);
  });

  test('malformed partial replies still release the native capture', () async {
    var released = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(WindowsScreenPreviews.channel, (call) async {
      if (call.method == 'start') return {'sessionId': 1, 'textureId': 10, 'width': 0, 'height': 0};
      released = true;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(WindowsScreenPreviews.channel, null));
    await expectLater(const WindowsScreenPreviews().start(display), throwsFormatException);
    expect(released, isTrue);
  });

  test('live preview updates aspect ratio and releases on exit', () async {
    final backend = FakeScreenPreviews();
    final preview = ScreenPreviewController(backend);
    await preview.show(display);
    expect(preview.phase, PreviewPhase.live);
    expect(preview.aspectRatio, closeTo(16 / 9, .001));
    backend.current = const PreviewStatus(ready: true, width: 600, height: 900);
    await preview.checkStatus();
    expect(preview.aspectRatio, closeTo(2 / 3, .001));
    preview.dispose();
    expect(backend.stopped, [1]);
  });

  test('closed, minimized and failed sources hide frozen pixels and stop capture', () async {
    for (final state in [const PreviewStatus(closed: true), const PreviewStatus(failed: true)]) {
      final backend = FakeScreenPreviews();
      final preview = ScreenPreviewController(backend);
      await preview.show(display);
      backend.current = state;
      await preview.checkStatus();
      expect(preview.phase, PreviewPhase.unavailable);
      expect(preview.handle, isNull);
      expect(backend.stopped, [1]);
      preview.dispose();
    }
  });

  test('a late opening reply after exit is released without notifications', () async {
    final pending = Completer<PreviewHandle>();
    final backend = FakeScreenPreviews()..opening = () => pending.future;
    final preview = ScreenPreviewController(backend);
    final opening = preview.show(display);
    preview.dispose();
    pending.complete(handle);
    await opening;
    expect(backend.stopped, [1]);
  });

  test('retry keeps the newer session when an older opening finishes late', () async {
    final old = Completer<PreviewHandle>();
    final backend = FakeScreenPreviews()..opening = () => old.future;
    final preview = ScreenPreviewController(backend);
    final oldOpening = preview.show(display);
    backend.opening = () async => const PreviewHandle(sessionId: 2, textureId: 20, width: 1280, height: 720);
    await preview.show(display);
    old.complete(handle);
    await oldOpening;
    expect(preview.handle!.sessionId, 2);
    expect(backend.stopped, [1]);
    preview.dispose();
    expect(backend.stopped, [1, 2]);
  });

  test('private backend failures get a plain message and can be retried', () async {
    final backend = FakeScreenPreviews()..opening = () async => throw StateError('private title');
    final preview = ScreenPreviewController(backend);
    await preview.show(display);
    expect(preview.problem, isNot(contains('private')));
    backend.opening = null;
    await preview.show(display);
    expect(preview.phase, PreviewPhase.live);
    preview.dispose();
  });

  testWidgets('missing first frames time out, then release a late opening', (tester) async {
    final pending = Completer<PreviewHandle>();
    final backend = FakeScreenPreviews()..opening = () => pending.future;
    final preview = ScreenPreviewController(backend);
    final opening = preview.show(display);
    await tester.pump(const Duration(seconds: 6));
    expect(preview.phase, PreviewPhase.unavailable);
    pending.complete(handle);
    await opening;
    expect(backend.stopped, [1]);
    preview.dispose();
  });
}

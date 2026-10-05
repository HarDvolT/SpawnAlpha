import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backend = WindowsScreenRecordings();
  const source = ScreenSource(
    id: 'window:fixture',
    name: 'Private window',
    kind: ScreenSourceKind.window,
    width: 640,
    height: 360,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(
      WindowsScreenRecordings.channel,
      null,
    ),
  );

  test(
    'start sends exact chosen microphone and explicit audio choice',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(WindowsScreenRecordings.channel, (
        call,
      ) async {
        request = call;
        return {'sessionId': 7};
      });
      final handle = await backend.start(
        source: source,
        path: 'local/take.mp4',
        recordAudio: true,
        microphoneId: 'chosen-endpoint',
      );
      expect(handle.sessionId, 7);
      expect(request!.arguments, {
        'sourceId': source.id,
        'path': 'local/take.mp4',
        'recordAudio': true,
        'microphoneId': 'chosen-endpoint',
      });
      expect((request!.arguments as Map).values, isNot(contains(source.name)));
      await backend.start(
        source: source,
        path: 'local/silent.mp4',
        recordAudio: false,
      );
      expect(request!.arguments, {
        'sourceId': source.id,
        'path': 'local/silent.mp4',
        'recordAudio': false,
      });
    },
  );

  test('maps common-clock status and partial source-loss result', () async {
    messenger.setMockMethodCallHandler(
      WindowsScreenRecordings.channel,
      (_) async => {
        'state': 'finished',
        'reason': 'source',
        'width': 1920,
        'height': 1080,
        'frames': 90,
        'audioFrames': 144000,
        'durationUs': 3000000,
        'peakDb': -9.0,
        'rmsDb': -18.0,
        'loudestRmsDb': -12.0,
      },
    );
    final status = await backend.status(const ScreenRecordingHandle(7));
    expect(status.terminal, isTrue);
    expect(status.reason, ScreenRecordingReason.source);
    expect(status.duration, const Duration(seconds: 3));
    expect(status.audioFrames, 144000);
    expect(status.loudestRmsDb, -12);
  });

  test(
    'old-session status is terminal and stop identifies only its session',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(WindowsScreenRecordings.channel, (
        call,
      ) async {
        request = call;
        return call.method == 'status'
            ? {'state': 'failed', 'reason': 'cancelled'}
            : null;
      });
      final handle = const ScreenRecordingHandle(3);
      final status = await backend.status(handle);
      expect(status.terminal, isTrue);
      expect(status.frames, 0);
      await backend.stop(handle);
      expect(request!.method, 'stop');
      expect(request!.arguments, {'sessionId': 3});
    },
  );

  test('rejects missing or malformed native replies', () async {
    for (final reply in [
      null,
      {'sessionId': -1},
      {'sessionId': 'private'},
    ]) {
      messenger.setMockMethodCallHandler(
        WindowsScreenRecordings.channel,
        (_) async => reply,
      );
      await expectLater(
        backend.start(
          source: source,
          path: 'local/take.mp4',
          recordAudio: true,
        ),
        throwsFormatException,
      );
    }
    for (final reply in [
      null,
      {'state': 'unknown', 'reason': 'none'},
      {'state': 'recording', 'reason': 'none', 'width': -1},
    ]) {
      messenger.setMockMethodCallHandler(
        WindowsScreenRecordings.channel,
        (_) async => reply,
      );
      await expectLater(
        backend.status(const ScreenRecordingHandle(1)),
        throwsFormatException,
      );
    }
  });
}

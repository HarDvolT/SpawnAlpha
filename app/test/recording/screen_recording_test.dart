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
  test(
    'activity path is optional and must be separate from both videos',
    () async {
      Map? request;
      messenger.setMockMethodCallHandler(WindowsScreenRecordings.channel, (
        call,
      ) async {
        request = call.arguments as Map;
        return {'sessionId': 1};
      });
      await backend.start(
        source: source,
        path: 'screen.mp4',
        recordAudio: false,
        activityPath: 'trace.jsonl',
      );
      expect(request!['activityPath'], 'trace.jsonl');
      for (final path in ['', 'screen.mp4', 'camera.mp4']) {
        await expectLater(
          backend.start(
            source: source,
            path: 'screen.mp4',
            recordAudio: false,
            cameraId: 'fixture',
            cameraPath: 'camera.mp4',
            activityPath: path,
          ),
          throwsArgumentError,
        );
      }
      await backend.start(
        source: source,
        path: 'screen.mp4',
        recordAudio: false,
      );
      expect(request!.containsKey('activityPath'), isFalse);
    },
  );
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
        'recordSystemAudio': false,
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
        'recordSystemAudio': false,
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
    expect(status.cameraFrames, 0);
    expect(status.loudestRmsDb, -12);
  });

  test('paired start sends only the chosen camera and separate file', () async {
    MethodCall? request;
    messenger.setMockMethodCallHandler(WindowsScreenRecordings.channel, (
      call,
    ) async {
      request = call;
      return {'sessionId': 8};
    });
    await backend.start(
      source: source,
      path: 'local/screen.mp4',
      recordAudio: false,
      cameraId: 'chosen-camera-link',
      cameraPath: 'local/camera.mp4',
    );
    expect(request!.arguments, {
      'sourceId': source.id,
      'path': 'local/screen.mp4',
      'recordAudio': false,
      'recordSystemAudio': false,
      'cameraId': 'chosen-camera-link',
      'cameraPath': 'local/camera.mp4',
    });
  });

  test(
    'computer sound is independent of microphone and paired camera',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(WindowsScreenRecordings.channel, (
        call,
      ) async {
        request = call;
        return {'sessionId': 8};
      });
      for (final microphone in [false, true]) {
        await backend.start(
          source: source,
          path: 'local/screen.mp4',
          recordAudio: microphone,
          recordSystemAudio: true,
          microphoneId: microphone ? 'chosen-mic' : null,
          cameraId: 'chosen-camera',
          cameraPath: 'local/camera.mp4',
        );
        expect(request!.arguments, {
          'sourceId': source.id,
          'path': 'local/screen.mp4',
          'recordAudio': microphone,
          'recordSystemAudio': true,
          if (microphone) 'microphoneId': 'chosen-mic',
          'cameraId': 'chosen-camera',
          'cameraPath': 'local/camera.mp4',
        });
      }
    },
  );

  test(
    'computer sound loss has separate counts and never changes voice levels',
    () async {
      final reply = <String, Object?>{
        'state': 'finished',
        'reason': 'systemAudio',
        'width': 640,
        'height': 360,
        'frames': 30,
        'audioFrames': 48000,
        'systemAudioFrames': 36000,
        'durationUs': 1000000,
        'peakDb': -100,
        'rmsDb': -100,
        'loudestRmsDb': -100,
        'loudestSystemRmsDb': -18,
      };
      messenger.setMockMethodCallHandler(
        WindowsScreenRecordings.channel,
        (_) async => reply,
      );
      final status = await backend.status(const ScreenRecordingHandle(8));
      expect(status.reason, ScreenRecordingReason.systemAudio);
      expect(status.systemAudioFrames, 36000);
      expect(status.rmsDb, -100);
      expect(status.loudestSystemRmsDb, -18);
      for (final invalid in [-1, 'samples']) {
        reply['systemAudioFrames'] = invalid;
        await expectLater(
          backend.status(const ScreenRecordingHandle(8)),
          throwsFormatException,
        );
      }
      reply['systemAudioFrames'] = 36000;
      reply['loudestSystemRmsDb'] = double.nan;
      await expectLater(
        backend.status(const ScreenRecordingHandle(8)),
        throwsFormatException,
      );
    },
  );

  test('rejects incomplete camera choices before asking Windows', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(WindowsScreenRecordings.channel, (
      _,
    ) async {
      calls++;
      return {'sessionId': 8};
    });
    for (final choice in [
      ('chosen', null),
      (null, 'local/camera.mp4'),
      ('', 'local/camera.mp4'),
      ('chosen', ''),
      ('chosen', 'local/screen.mp4'),
    ]) {
      await expectLater(
        backend.start(
          source: source,
          path: 'local/screen.mp4',
          recordAudio: false,
          cameraId: choice.$1,
          cameraPath: choice.$2,
        ),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });

  test(
    'camera loss maps partial paired counts and rejects invalid counts',
    () async {
      final reply = <String, Object?>{
        'state': 'finished',
        'reason': 'camera',
        'width': 640,
        'height': 360,
        'frames': 30,
        'cameraFrames': 30,
        'audioFrames': 0,
        'durationUs': 1000000,
        'peakDb': -100,
        'rmsDb': -100,
        'loudestRmsDb': -100,
      };
      messenger.setMockMethodCallHandler(
        WindowsScreenRecordings.channel,
        (_) async => reply,
      );
      final status = await backend.status(const ScreenRecordingHandle(8));
      expect(status.reason, ScreenRecordingReason.camera);
      expect(status.cameraFrames, status.frames);
      expect(status.terminal, isTrue);
      reply['cameraFrames'] = -1;
      await expectLater(
        backend.status(const ScreenRecordingHandle(8)),
        throwsFormatException,
      );
    },
  );

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
      await backend.pause(handle, true);
      expect(request!.method, 'pause');
      expect(request!.arguments, {'sessionId': 3, 'paused': true});
      await backend.release(handle);
      expect(request!.method, 'release');
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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const inspector = WindowsRecordingInspector();
  tearDown(
    () => messenger.setMockMethodCallHandler(
      WindowsScreenRecordings.channel,
      null,
    ),
  );
  test('returns verified visible dimensions and fragment duration', () async {
    messenger.setMockMethodCallHandler(
      WindowsScreenRecordings.channel,
      (call) async => call.method == 'inspectStart'
          ? 4
          : {
              'ready': true,
              'readable': true,
              'hasAudio': true,
              'width': 640,
              'height': 360,
              'durationUs': 3900000,
            },
    );
    final info = await inspector.inspect('local/unfinished.mp4');
    expect(info.readable, isTrue);
    expect(info.height, 360);
    expect(info.hasAudio, isTrue);
    expect(info.duration, const Duration(milliseconds: 3900));
  });
  test(
    'recovery and export checks queue across instances after a failure',
    () async {
      final firstStatus = Completer<Map<String, Object?>>();
      final started = Completer<void>();
      var starts = 0;
      messenger.setMockMethodCallHandler(WindowsScreenRecordings.channel, (
        call,
      ) async {
        if (call.method == 'inspectStart') {
          ++starts;
          return starts;
        }
        if (call.method == 'inspectCancel') return null;
        if (starts == 1) {
          started.complete();
          return firstStatus.future;
        }
        return {
          'ready': true,
          'readable': true,
          'width': 1920,
          'height': 1080,
          'durationUs': 2000000,
        };
      });
      final first = inspector.inspect('generated/first.mp4');
      final failure = expectLater(first, throwsFormatException);
      await started.future;
      final second = const WindowsRecordingInspector().inspect(
        'generated/second.mp4',
      );
      await Future<void>.delayed(Duration.zero);
      expect(starts, 1);
      firstStatus.complete({'ready': true, 'readable': true, 'width': -1});
      await failure;
      expect((await second).readable, isTrue);
      expect(starts, 2);
    },
  );
  test(
    'unreadable output is explicit and invalid result cancels the job',
    () async {
      final calls = <String>[];
      var valid = true;
      messenger.setMockMethodCallHandler(WindowsScreenRecordings.channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'inspectStart') return 4;
        if (call.method == 'inspectCancel') return null;
        return valid
            ? {'ready': true, 'readable': false}
            : {'ready': true, 'readable': true, 'width': -1};
      });
      expect((await inspector.inspect('local/broken.mp4')).readable, isFalse);
      valid = false;
      await expectLater(
        inspector.inspect('local/broken.mp4'),
        throwsFormatException,
      );
      expect(calls.last, 'inspectCancel');
    },
  );
}

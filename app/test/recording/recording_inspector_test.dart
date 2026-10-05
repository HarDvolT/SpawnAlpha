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

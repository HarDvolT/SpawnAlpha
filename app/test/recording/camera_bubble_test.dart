import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/camera_bubble.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/theme/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const source = ScreenSource(
    id: 'fixture',
    name: 'Display',
    kind: ScreenSourceKind.display,
    width: 1920,
    height: 1080,
  );
  const backend = WindowsCameraBubbles();
  tearDown(
    () =>
        messenger.setMockMethodCallHandler(WindowsCameraBubbles.channel, null),
  );
  test('opens with design geometry and no private file or camera ID', () async {
    Object? arguments;
    messenger.setMockMethodCallHandler(WindowsCameraBubbles.channel, (
      call,
    ) async {
      if (call.method == 'open') {
        arguments = call.arguments;
        return 4;
      }
      if (call.method == 'status') return {'ready': true, 'excluded': true};
      return null;
    });
    final handle = await backend.open(source, 'Chosen camera');
    expect(arguments, {
      'sourceId': source.id,
      'name': 'Chosen camera',
      'diameter': SaPrompter.cameraBubbleSize.round(),
      'readerWidth': SaPrompter.floatingWidth.round(),
      'inset': SaSpace.s6.round(),
      'pollMs': SaDurations.recordingPoll.inMilliseconds,
    });
    expect(await backend.isSafe(handle), isTrue);
  });
  test('exclusion failure closes the owned window and prevents use', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(WindowsCameraBubbles.channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'open') return 5;
      if (call.method == 'status') return {'ready': true, 'excluded': false};
      return null;
    });
    await expectLater(backend.open(source, 'Camera'), throwsFormatException);
    expect(calls, ['open', 'status', 'close']);
    expect(await backend.isSafe(const CameraBubbleHandle(5)), isFalse);
  });
  test('malformed texture geometry never becomes live', () {
    for (final map in [
      <Object?, Object?>{},
      {'textureId': -1, 'width': 640, 'height': 360, 'live': true},
      {'textureId': 1, 'width': 0, 'height': 360, 'live': true},
      {'textureId': 1, 'width': 640, 'height': 'private', 'live': true},
    ]) {
      expect(CameraBubbleState.fromJson(map).live, isFalse);
    }
  });
}

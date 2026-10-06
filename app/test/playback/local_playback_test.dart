import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/playback/local_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backend = WindowsLocalPlayback();
  final calls = <MethodCall>[];
  Object? reply;
  setUp(() {
    calls.clear();
    reply = {'sessionId': 3, 'textureId': 7};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsLocalPlayback.channel, (call) async {
          calls.add(call);
          return reply;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsLocalPlayback.channel, null),
  );
  test('only absolute local paths reach native playback', () async {
    for (final path in [
      'https://example.com/a.mp4',
      r'\\host\share\a.mp4',
      'relative.mp4',
      r'E:\a.mp4:secret',
    ]) {
      await expectLater(backend.open(path), throwsFormatException);
    }
    expect(calls, isEmpty);
    final handle = await backend.open(r'E:\generated-é-العربية.mp4');
    expect(handle.textureId, 7);
    expect(calls.single.arguments['path'], r'E:\generated-é-العربية.mp4');
  });
  test('partial open is released and malformed status is rejected', () async {
    reply = {'sessionId': 3, 'textureId': -1};
    await expectLater(backend.open(r'E:\a.mp4'), throwsFormatException);
    expect(calls.last.method, 'close');
    reply = {'ready': true, 'durationUs': -1};
    await expectLater(
      backend.status(const PlaybackHandle(3, 7)),
      throwsFormatException,
    );
    reply = {'closed': true};
    expect((await backend.status(const PlaybackHandle(3, 7))).closed, isTrue);
  });
}

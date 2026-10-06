import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/recording_hud.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const source = ScreenSource(
    id: 'source',
    kind: ScreenSourceKind.display,
    name: 'Display',
    width: 1920,
    height: 1080,
  );
  tearDown(
    () =>
        messenger.setMockMethodCallHandler(WindowsRecordingHuds.channel, null),
  );
  test(
    'requires native capture exclusion before controls become usable',
    () async {
      final calls = <String>[];
      var excluded = true;
      messenger.setMockMethodCallHandler(WindowsRecordingHuds.channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'open') return 1;
        if (call.method == 'status') {
          return {'ready': true, 'excluded': excluded};
        }
        return null;
      });
      final backend = WindowsRecordingHuds();
      final handle = await backend.open(source);
      expect(await backend.isOpen(handle), isTrue);
      await backend.update(
        handle,
        const HudState(phase: HudPhase.paused, duration: Duration(seconds: 2)),
      );
      await backend.close(handle);
      excluded = false;
      await expectLater(backend.open(source), throwsFormatException);
      expect(calls.last, 'close');
    },
  );
  test('state transfer contains timer/meter only and round-trips', () {
    const state = HudState(
      phase: HudPhase.recording,
      duration: Duration(seconds: 2),
      microphone: 'Chosen microphone',
      peakDb: -12,
      recordAudio: false,
      recordSystemAudio: true,
      prompterOpen: false,
    );
    final restored = HudState.fromJson(state.toJson());
    expect(restored.duration, state.duration);
    expect(restored.phase, state.phase);
    expect(restored.recordAudio, isFalse);
    expect(restored.prompterOpen, isFalse);
    expect(restored.recordSystemAudio, isTrue);
    expect(HudState.fromJson(const {}).recordSystemAudio, isFalse);
    expect(state.toJson().keys, isNot(contains('script')));
    expect(state.toJson().keys, isNot(contains('path')));
  });
}

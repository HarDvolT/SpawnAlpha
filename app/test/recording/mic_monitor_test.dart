import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/audio_input.dart';
import 'package:spawnalpha/src/recording/mic_monitor.dart';

/// A microphone that plays back a list of levels.
class FakeAudioInputs implements AudioInputs {
  FakeAudioInputs(this.levels);

  final List<double> levels;
  var _i = 0;
  String? selected = 'none';
  String? metering = 'none';

  @override
  bool get supported => true;

  @override
  Future<List<AudioInput>> list() async => const [
        AudioInput(id: 'default-mic', name: 'Headset', isDefault: true),
        AudioInput(id: 'usb', name: 'USB microphone', isDefault: false),
      ];

  @override
  Future<void> select(String? id) async => selected = id;

  @override
  Future<void> startLevels(String? id) async => metering = id;

  @override
  Future<void> stopLevels() async => metering = 'stopped';

  @override
  Future<MicLevel> level() async {
    final db = levels[_i.clamp(0, levels.length - 1)];
    _i++;
    return MicLevel(peakDb: db + 6, rmsDb: db);
  }
}

void main() {
  test('keeps a saved microphone that still exists, and falls back to the default', () async {
    final fake = FakeAudioInputs([-70]);
    final mic = MicMonitor(fake);
    expect(await mic.start('usb'), 'usb');
    expect(fake.selected, 'usb');
    expect(mic.input!.name, 'USB microphone');
    expect(await mic.start('unplugged'), isNull);
    expect(fake.selected, isNull);
    expect(mic.input!.name, 'Headset');
    await mic.stop();
    expect(fake.metering, 'stopped');
    mic.dispose();
  });

  test('hears speech and remembers the loudest level of a take', () {
    fakeAsync((async) {
      final fake = FakeAudioInputs([...List.filled(20, -70.0), ...List.filled(10, -25.0), ...List.filled(20, -70.0)]);
      final mic = MicMonitor(fake);
      mic.start(null);
      async.flushMicrotasks();
      mic.resetLoudest();
      async.elapse(const Duration(milliseconds: 1000));
      expect(mic.speaking, isFalse);
      async.elapse(const Duration(milliseconds: 400));
      expect(mic.speaking, isTrue);
      expect(mic.loudestRmsDb, -25);
      async.elapse(const Duration(milliseconds: 1000));
      expect(mic.speaking, isFalse);
      mic.dispose();
    });
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/audio_input.dart';
import 'package:spawnalpha/src/recording/mic_monitor.dart';
import 'package:spawnalpha/src/recording/sound_check.dart';

/// A microphone that plays back a list of levels.
class FakeAudioInputs implements AudioInputs {
  FakeAudioInputs(this.played, {this.deniedAll = false});

  /// The chosen microphone's levels, one per poll.
  final List<double> played;

  /// Windows refuses every microphone.
  final bool deniedAll;
  bool watching = false;
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
    final db = played[_i.clamp(0, played.length - 1)];
    _i++;
    return MicLevel(peakDb: db + 6, rmsDb: db, failed: deniedAll, denied: deniedAll);
  }
  @override
  Future<void> watchAll() async => watching = true;

  @override
  Future<Map<String, MicLevel>> levels() async => {
        'default-mic': MicLevel(peakDb: -20, rmsDb: -30, failed: deniedAll, denied: deniedAll),
        'usb': MicLevel(peakDb: -100, rmsDb: -100, failed: deniedAll, denied: deniedAll),
      };

  @override
  Future<void> unwatchAll() async => watching = false;
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

  test('meters every microphone during set-up, and stops for the take', () {
    fakeAsync((async) {
      final fake = FakeAudioInputs([-70]);
      final mic = MicMonitor(fake);
      mic.start(null);
      mic.watchEveryMic();
      async.flushMicrotasks();
      expect(fake.watching, isTrue);
      async.elapse(const Duration(milliseconds: 120));
      expect(mic.levels.keys, containsAll(['default-mic', 'usb']));
      expect(mic.levels['default-mic']!.meter, greaterThan(mic.levels['usb']!.meter), reason: 'the one that moves');
      expect(mic.blocked, isFalse);
      mic.stopWatchingAll();
      async.flushMicrotasks();
      expect(fake.watching, isFalse);
      expect(mic.levels, isEmpty);
      mic.dispose();
    });
  });

  test('knows when Windows blocks the microphones', () {
    fakeAsync((async) {
      final mic = MicMonitor(FakeAudioInputs([-100], deniedAll: true));
      mic.start(null);
      mic.watchEveryMic();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 120));
      expect(mic.blocked, isTrue);
      mic.dispose();
    });
  });

  test('a sound check hears speech, a quiet voice, or nothing', () {
    expect(SoundCheck.judge(-28), SoundVerdict.heard);
    expect(SoundCheck.judge(-52), SoundVerdict.quiet);
    expect(SoundCheck.judge(-80), SoundVerdict.silent);
    expect(SoundCheck.judge(-100), SoundVerdict.silent);
  });
}

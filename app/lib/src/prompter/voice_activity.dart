import 'dart:math' as math;

/// Decides, from microphone levels, whether the speaker is talking: the
/// signal behind voice pacing, where the prompter moves while you speak and
/// waits when you stop.
///
/// It tracks the room's noise floor (falling fast to quiet levels, rising
/// slowly), and calls it speech when the level stands [marginDb] above the
/// floor and above [minSpeechDb]. Speech starts after [attack] of sound and
/// ends after [release] of quiet, so short gaps between words don't stop
/// the scroll. Pure Dart; the caller feeds it levels about 20 times a
/// second.
class VoiceActivity {
  VoiceActivity({
    this.marginDb = 12,
    this.minSpeechDb = -50,
    this.attack = const Duration(milliseconds: 60),
    this.release = const Duration(milliseconds: 350),
  });

  final double marginDb;
  final double minSpeechDb;
  final Duration attack;
  final Duration release;

  double _floor = -60;
  bool _speaking = false;
  Duration _loudFor = Duration.zero;
  Duration _quietFor = Duration.zero;

  /// The estimated noise floor, in dBFS.
  double get floorDb => _floor;

  bool get speaking => _speaking;

  /// Takes the level of the last [elapsed] and returns whether the speaker
  /// is talking.
  bool update(double rmsDb, Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (rmsDb < _floor) {
      // Quiet: the floor follows down quickly.
      _floor += (rmsDb - _floor) * math.min(1.0, seconds * 8);
    } else {
      // Louder: it creeps up slowly, so speech doesn't become the floor.
      _floor += math.min(rmsDb - _floor, 1.5 * seconds);
    }
    final loud = rmsDb > math.max(_floor + marginDb, minSpeechDb);
    if (loud) {
      _loudFor += elapsed;
      _quietFor = Duration.zero;
      if (!_speaking && _loudFor >= attack) _speaking = true;
    } else {
      _quietFor += elapsed;
      _loudFor = Duration.zero;
      if (_speaking && _quietFor >= release) _speaking = false;
    }
    return _speaking;
  }

  void reset() {
    _speaking = false;
    _loudFor = Duration.zero;
    _quietFor = Duration.zero;
  }
}

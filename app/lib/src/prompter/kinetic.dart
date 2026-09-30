import 'dart:math' as math;

import '../theme/tokens.g.dart';

/// The motion maths of the kinetic prompter (docs/design/prompter.md,
/// "Kinetic text"): pure functions of how far a word is from the reading
/// line and how long ago it was spoken. Painting reads these every frame;
/// nothing here can move a word to another line.
abstract final class Kinetic {
  /// Words start waking up this many lines before the reading line.
  static const wakeLines = 1.8;

  /// Text more than this many lines ahead sits back.
  static const sitBackLines = 3.0;

  /// How much a stressed word grows as it reaches the reading line. The
  /// stage reserves room for it beside the word.
  static const stressGrowth = 0.08;

  /// The extra size of the pop as a stressed word is spoken.
  static const popAmplitude = 0.08;

  /// How long the pop and a gap glyph's hit last.
  static const popWindow = Duration(milliseconds: 600);
  static const hitWindow = Duration(milliseconds: 520);

  /// Room reserved on each side of a stressed word, in ems, so growing
  /// toward the reading line never touches its neighbours. (The pop, a
  /// fifth of a second, may briefly reach past it.)
  static const stressRoom = 0.2;

  /// 1 on the reading line, easing to 0 [wakeLines] ahead (smoothstep).
  /// Words already read drop to 0 once they are half a line past.
  static double liveness(double linesAhead) {
    if (linesAhead < -0.5) return 0;
    if (linesAhead <= 0) return 1;
    final x = (linesAhead / wakeLines).clamp(0.0, 1.0);
    return 1 - x * x * (3 - 2 * x);
  }

  /// The `spring-pop` impulse at [since] after a stressed word starts,
  /// scaled so its peak is [popAmplitude]. Zero outside [popWindow].
  static double pop(Duration since) {
    if (since.isNegative || since >= popWindow) return 0;
    final t = since.inMicroseconds / 1e6;
    return popAmplitude * _impulse(t) / _impulsePeak;
  }

  /// The size of a stressed word: grown by its liveness, plus the pop.
  static double stressScale(double liveness, Duration? sinceSpoken) =>
      1 + stressGrowth * liveness + (sinceSpoken == null ? 0 : pop(sinceSpoken));

  /// Progress of a gap glyph's hit, 0 to 1, at [since] after its hold
  /// starts; null outside [hitWindow].
  static double? hit(Duration since) {
    if (since.isNegative || since >= hitWindow) return null;
    return since.inMicroseconds / hitWindow.inMicroseconds;
  }

  // An underdamped spring's response to a kick: e^(-ζω₀t)·sin(ω_d·t).
  static final _spring = SaSprings.pop;
  static final double _omega0 = math.sqrt(_spring.stiffness / _spring.mass);
  static final double _zeta = _spring.damping / (2 * math.sqrt(_spring.stiffness * _spring.mass));
  static final double _omegaD = _omega0 * math.sqrt(1 - _zeta * _zeta);
  static double _impulse(double t) => math.exp(-_zeta * _omega0 * t) * math.sin(_omegaD * t);
  static final double _impulsePeak = _impulse(math.atan(_omegaD / (_zeta * _omega0)) / _omegaD);
}

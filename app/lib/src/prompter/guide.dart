import 'dart:math' as math;
import 'dart:ui';

import '../model/mark.dart';
import 'delivery_timeline.dart';

/// How the prompter shows which word to say now (docs/design/prompter.md,
/// "The guide").
enum PrompterGuide {
  /// A ball that bounces from word to word and acts out each cue.
  dot('Dot', 'A ball jumps from word to word and acts out each cue'),

  /// A bar fills across the word being said.
  underline('Underline', 'A bar fills across the word to say'),

  /// Only the word being said, and the next one, at full strength.
  spotlight('Spotlight', 'Only the word to say and the next one are lit'),

  /// Only the reading line.
  off('Off', 'Only the reading line');

  const PrompterGuide(this.label, this.hint);

  final String label;
  final String hint;

  /// The next guide, for the G key.
  PrompterGuide get next => values[(index + 1) % values.length];

  static PrompterGuide fromName(String? name) =>
      values.firstWhere((g) => g.name == name, orElse: () => PrompterGuide.dot);
}

/// How the script moves between holds.
enum PrompterMotion {
  /// The line being read stays still; the view glides to the next line.
  lineStep('Line step', 'The line stays still, then steps up'),

  /// The classic prompter scroll, at an even rate through each line.
  smooth('Smooth', 'An even scroll, like a classic prompter');

  const PrompterMotion(this.label, this.hint);

  final String label;
  final String hint;

  static PrompterMotion fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => PrompterMotion.lineStep);
}

/// What colour the dot takes: white, or a cue's colour while it acts
/// that cue out.
enum DotTint { plain, stress, energy, slower, faster, pause, breath }

/// The sign the dot shows inside itself when it grows into a cue: the
/// cue vocabulary's glyph, or a microphone while it waits for the voice.
enum DotSign { pause, pauseLong, breath, slower, faster, energy, listen }

/// What the dot leaves behind as it travels: echoes in a slower run,
/// streaks in a faster run, sparks in an energy run.
enum DotTrail { none, echoes, streaks, sparks }

/// Where the bouncing dot is and what it is doing, at one moment.
class DotFrame {
  const DotFrame({
    required this.center,
    this.size = 1,
    this.scaleX = 1,
    this.scaleY = 1,
    this.tint = DotTint.plain,
    this.sign,
    this.signAlpha = 1,
    this.timer,
    this.burst,
    this.slam,
    this.slamBox,
    this.trail = DotTrail.none,
  });

  final Offset center;

  /// How big the dot is, as a multiple of its resting radius. It grows to
  /// act out a cue and shrinks back after.
  final double size;

  /// Squash and stretch: wider and shorter as it lands.
  final double scaleX;
  final double scaleY;
  final DotTint tint;

  /// The glyph inside the grown dot, and how much of it shows.
  final DotSign? sign;
  final double signAlpha;

  /// At a pause: how much of the hold is left, 1 to 0. A ring around the
  /// dot drains like a timer.
  final double? timer;

  /// After slamming onto a stressed word: how far its shockwave has
  /// spread, 0 to 1.
  final double? burst;

  /// The amber strike across a stressed word, 0 to 1 (drawn, then faded),
  /// and the word's box.
  final double? slam;
  final Rect? slamBox;

  /// What it leaves behind as it travels.
  final DotTrail trail;
}

/// What the dot needs to know about each word: where it is and which
/// cues it carries.
class DotWord {
  const DotWord({
    required this.box,
    this.stressed = false,
    this.run,
    this.opensRun = false,
    this.gap,
    this.gapGlyph,
  });

  /// The word's box in the paragraph, or null if it has none.
  final Rect? box;
  final bool stressed;

  /// The pace or energy run the word is in: [MarkKind.energy],
  /// [MarkKind.slower] or [MarkKind.faster].
  final MarkKind? run;

  /// The first word of its run: the dot announces the run with its glyph.
  final bool opensRun;

  /// The pause, long pause or breath after the word, and its glyph's box.
  final MarkKind? gap;
  final Rect? gapGlyph;
}

/// The bouncing dot's path through a script (docs/design/prompter.md, "The
/// bouncing dot"). Pure maths over the laid-out words and the delivery
/// timeline: [at] gives the dot at any moment, so painting is stateless.
///
/// It lands on each word as the word starts, a third of the way in from
/// the leading edge, and arcs to the next one so it arrives as that word
/// starts. It **becomes each cue** as it reaches it, in the cue's colour:
/// - into a stressed word it climbs, grows and slams down, striking the
///   word, with a shockwave;
/// - at a pause it grows into the pause sign while a ring drains over
///   exactly the hold, then shrinks and hops on in the last [hopOn];
/// - at a breath it inhales (swells, with the breath glyph) and exhales;
/// - a slower run makes it heavy and slow, leaving echoes; a faster run
///   makes it small and stretched, leaving streaks; an energy run makes it
///   pulse and throw sparks. It shows the run's glyph as the run opens;
/// - while voice pace waits, it grows a microphone and bobs.
class BouncePath {
  BouncePath({required this.words, required this.fontSize, required this.rtl});

  final List<DotWord> words;
  final double fontSize;
  final bool rtl;

  /// The dot's resting radius: its diameter is about 0.4 of the type size.
  double get radius => fontSize * 0.2;

  /// How long the hop from a pause glyph to the next word takes.
  static const hopOn = Duration(milliseconds: 160);

  /// How long a stressed word's shockwave lasts.
  static const burstLength = Duration(milliseconds: 520);

  /// How long the strike across a stressed word takes to draw and fade.
  static const slamLength = Duration(milliseconds: 700);

  /// How long the dot takes to grow into a pause or breath, and to shrink.
  static const growLength = Duration(milliseconds: 200);

  /// How long the dot shows a run's glyph as the run opens.
  static const announceLength = Duration(milliseconds: 650);

  /// Arc heights, in ems (docs/design/prompter.md).
  static const baseHop = 0.5;
  static const slowHop = 0.3;
  static const fastHop = 0.18;
  static const energyHop = 0.7;
  static const stressHop = 0.95;
  static const lineHop = 0.4;

  /// Sizes, as multiples of the resting radius.
  static const pauseSize = 2.3;
  static const longPauseSize = 2.9;
  static const breathSize = 2.6;
  static const stressSize = 1.8;
  static const announceSize = 2.1;
  static const listenSize = 1.9;
  static const slowSize = 1.3;
  static const fastSize = 0.8;
  static const energySize = 1.25;

  /// Before a new line, the dot stays on the last word for this much of it.
  static const lineStay = 0.6;

  /// Where the dot rests on [word]: just above it, a third in from the
  /// leading edge. Stressed words grow, so it rests a little higher.
  Offset? restOn(int word) {
    final w = words[word];
    final box = w.box;
    if (box == null) return null;
    final x = rtl ? box.right - box.width / 3 : box.left + box.width / 3;
    return Offset(x, box.top - radius * 1.2 - (w.stressed ? fontSize * 0.1 : 0));
  }

  /// Where the dot rests on the pause or breath glyph after [word]: its
  /// centre on the glyph, so it can grow into the sign in its place.
  Offset? restOnGlyph(int word) {
    final glyph = words[word].gapGlyph;
    if (glyph == null) return null;
    return glyph.center;
  }

  DotTint _tintOf(DotWord w) => w.stressed
      ? DotTint.stress
      : switch (w.run) {
          MarkKind.energy => DotTint.energy,
          MarkKind.slower => DotTint.slower,
          MarkKind.faster => DotTint.faster,
          _ => DotTint.plain,
        };

  double _sizeOf(DotWord w) => w.stressed
      ? 1.2
      : switch (w.run) {
          MarkKind.slower => slowSize,
          MarkKind.faster => fastSize,
          MarkKind.energy => energySize,
          _ => 1,
        };

  static DotSign? _signOf(MarkKind? kind) => switch (kind) {
        MarkKind.pauseShort => DotSign.pause,
        MarkKind.pauseLong => DotSign.pauseLong,
        MarkKind.breath => DotSign.breath,
        MarkKind.slower => DotSign.slower,
        MarkKind.faster => DotSign.faster,
        MarkKind.energy => DotSign.energy,
        _ => null,
      };

  /// The dot at [time] on [timeline]. With [waiting] (voice pace, the
  /// speaker has stopped) it grows a microphone and bobs on [clock], a wall
  /// clock in seconds. With [calm] (reduced motion) it jumps from word to
  /// word and holds each cue's colour and sign still: no arcs, squash,
  /// swelling, pulsing or bobbing.
  DotFrame? at(DeliveryTimeline timeline, Duration time, {bool waiting = false, double clock = 0, bool calm = false}) {
    if (timeline.isEmpty || timeline.length != words.length) return null;
    final i = timeline.tokenAt(time);
    final here = restOn(i);
    if (here == null) return null;
    final word = words[i];
    final hasNext = i + 1 < words.length;

    // ---- Holding at a pause or breath: the dot becomes the sign. --------
    if (timeline.isHolding(time) && word.gapGlyph != null && word.gap != null) {
      final (start, end) = timeline.holdAt(time)!;
      final glyph = restOnGlyph(i)!;
      final left = end - time;
      final into = time - start;
      final next = hasNext ? restOn(i + 1) : null;
      if (next != null && left < hopOn && !calm) {
        final u = 1 - left.inMicroseconds / hopOn.inMicroseconds;
        return DotFrame(center: _arc(glyph, next, u, baseHop * 1.1), size: _sizeOf(words[i + 1]));
      }
      final k = _fraction(into, end - start);
      final sign = _signOf(word.gap)!;
      if (word.gap == MarkKind.breath) {
        // Inhale, then exhale: the whole hold is one breath.
        final swell = calm ? breathSize : 1 + (breathSize - 1) * math.sin(math.pi * k);
        return DotFrame(center: glyph, size: swell, tint: DotTint.breath, sign: sign, signAlpha: calm ? 1 : _ramp(swell, 1.4, 2.0));
      }
      final full = word.gap == MarkKind.pauseLong ? longPauseSize : pauseSize;
      // Grow into the sign as the hold starts, shrink back before hopping on.
      final grow = calm ? 1.0 : _easeOutBack(_fraction(into, growLength));
      final shrink = calm ? 1.0 : _fraction(left - hopOn, growLength);
      final size = 1 + (full - 1) * math.min(grow, shrink);
      return DotFrame(
        center: glyph,
        size: size,
        tint: DotTint.pause,
        sign: sign,
        signAlpha: _ramp(size, 1.6, full - 0.2),
        timer: 1 - k,
      );
    }

    final tint = _tintOf(word);
    final since = time - timeline.startOf(i);
    final announcing = word.opensRun && word.run != null && since < announceLength;
    if (calm) {
      return DotFrame(
        center: here,
        tint: tint,
        size: announcing ? announceSize : _sizeOf(word),
        sign: announcing ? _signOf(word.run) : null,
      );
    }

    if (waiting) {
      final bob = math.sin(clock * 2 * math.pi / 1.4) * fontSize * 0.08;
      return DotFrame(
        center: here.translate(0, -fontSize * 0.25 + bob),
        size: listenSize,
        sign: DotSign.listen,
      );
    }

    // ---- Travelling: arc from this word to the next, or onto its glyph. --
    final glyph = word.gap != null ? restOnGlyph(i) : null;
    final Offset target;
    final Duration arrive;
    if (glyph != null) {
      target = glyph;
      arrive = timeline.endOf(i);
    } else if (hasNext && restOn(i + 1) != null) {
      target = restOn(i + 1)!;
      arrive = timeline.startOf(i + 1);
    } else {
      target = here;
      arrive = timeline.endOf(i);
    }
    final landed = _fraction(since, arrive - timeline.startOf(i));
    var u = landed;
    // To a new line: stay on the word, then swoop down to the next line
    // over the last part of it, rather than crossing the line being read.
    final newLine = (target.dy - here.dy).abs() > fontSize * 0.5;
    if (newLine) u = ((u - lineStay) / (1 - lineStay)).clamp(0.0, 1.0);

    final intoStress = glyph == null && hasNext && words[i + 1].stressed;
    var height = baseHop;
    if (word.run == MarkKind.slower) height = slowHop;
    if (word.run == MarkKind.faster) height = fastHop;
    if (word.run == MarkKind.energy) height = energyHop;
    if (intoStress) height = stressHop;
    if (newLine) height = lineHop;

    var size = _sizeOf(word);
    var frameTint = tint;
    var scaleX = 1.0;
    var scaleY = 1.0;
    Offset center;
    if (intoStress) {
      // Wind up and slam: climb slowly, then drop hard onto the word,
      // growing and turning amber on the way down.
      final eased = u < 0.55 ? 0.55 * _easeOut(u / 0.55) * 0.7 : 0.385 + 0.615 * _easeIn((u - 0.55) / 0.45);
      center = _arc(here, target, eased, height);
      final charge = ((u - 0.35) / 0.65).clamp(0.0, 1.0);
      size = size + (stressSize - size) * charge;
      if (charge > 0.3) frameTint = DotTint.stress;
      if (u > 0.55) {
        scaleX = 1 - 0.18 * charge;
        scaleY = 1 + 0.3 * charge;
      }
    } else {
      center = _arc(here, target, u, height);
    }

    // Landing: a squash on every word, a hard one on a stressed word.
    if (landed > 0 && landed < 0.12) {
      final squash = (0.12 - landed) * (word.stressed ? 5.0 : 2.5);
      scaleX = 1 + squash;
      scaleY = 1 - squash * 0.8;
    }
    if (word.stressed) {
      // Settles from the slam size back to its stressed size.
      final settle = _fraction(since, const Duration(milliseconds: 260));
      size = stressSize + (size - stressSize) * _easeOut(settle);
    }
    if (word.run == MarkKind.energy) {
      // A beat: it pulses three times a second.
      size *= 1 + 0.18 * math.sin(2 * math.pi * 3 * time.inMicroseconds / 1e6).abs();
    }
    if (word.run == MarkKind.faster) {
      // Stretched along its path while it travels.
      final travel = 4 * u * (1 - u);
      scaleX *= 1 + 0.6 * travel;
      scaleY *= 1 - 0.25 * travel;
    }
    DotSign? sign;
    var signAlpha = 0.0;
    if (announcing) {
      // The run opens: the dot grows its glyph, then lets it go, within the
      // first word.
      final span = arrive - timeline.startOf(i);
      final a = _fraction(since, span < announceLength ? span : announceLength);
      final bump = math.sin(math.pi * a);
      size = size + (announceSize - size) * bump;
      sign = _signOf(word.run);
      signAlpha = _ramp(bump, 0.3, 0.7);
    }
    return DotFrame(
      center: center,
      size: size,
      scaleX: scaleX,
      scaleY: scaleY,
      tint: frameTint,
      sign: sign,
      signAlpha: signAlpha,
      burst: word.stressed && since < burstLength ? _fraction(since, burstLength) : null,
      slam: word.stressed && since < slamLength ? _fraction(since, slamLength) : null,
      slamBox: word.stressed ? word.box : null,
      // No trail while it slams: the strike should read clean.
      trail: word.stressed && since < burstLength
          ? DotTrail.none
          : switch (word.run) {
              MarkKind.slower => DotTrail.echoes,
              MarkKind.faster => DotTrail.streaks,
              MarkKind.energy => DotTrail.sparks,
              _ => DotTrail.none,
            },
    );
  }

  /// A parabolic hop from [a] to [b], [height] ems at its peak.
  Offset _arc(Offset a, Offset b, double u, double height) {
    final lerp = Offset.lerp(a, b, u)!;
    return lerp.translate(0, -height * fontSize * 4 * u * (1 - u));
  }

  static double _fraction(Duration part, Duration whole) =>
      whole.inMicroseconds <= 0 ? 1 : (part.inMicroseconds / whole.inMicroseconds).clamp(0.0, 1.0);

  /// 0 below [from], 1 above [to], linear between.
  static double _ramp(double v, double from, double to) => ((v - from) / (to - from)).clamp(0.0, 1.0);

  static double _easeOut(double t) => 1 - (1 - t) * (1 - t);

  static double _easeIn(double t) => t * t;

  /// Overshoots a little and settles, like `spring-pop`.
  static double _easeOutBack(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }
}

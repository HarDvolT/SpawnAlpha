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

/// Where the bouncing dot is and what it is doing, at one moment.
class DotFrame {
  const DotFrame({
    required this.center,
    this.scaleX = 1,
    this.scaleY = 1,
    this.tint = DotTint.plain,
    this.ring,
    this.burst,
    this.sparks = false,
  });

  final Offset center;

  /// Squash and stretch: wider and shorter as it lands.
  final double scaleX;
  final double scaleY;
  final DotTint tint;

  /// At a pause: how far the ring around it has closed, 0 to 1.
  final double? ring;

  /// After landing on a stressed word: how far its burst has spread, 0 to 1.
  final double? burst;

  /// In an energy run: it throws sparks as it travels.
  final bool sparks;
}

/// What the dot needs to know about each word: where it is and which
/// cues it carries.
class DotWord {
  const DotWord({
    required this.box,
    this.stressed = false,
    this.run,
    this.gap,
    this.gapGlyph,
  });

  /// The word's box in the paragraph, or null if it has none.
  final Rect? box;
  final bool stressed;

  /// The pace or energy run the word is in: [MarkKind.energy],
  /// [MarkKind.slower] or [MarkKind.faster].
  final MarkKind? run;

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
/// starts. The arc says how to go on: low and long in a slower run, short
/// skips in a faster run, high into a stressed word. At a pause it hops
/// onto the glyph and rests while a ring closes; at a breath it swells.
/// In the last [hopOn] of a hold it hops on to the next word.
class BouncePath {
  BouncePath({required this.words, required this.fontSize, required this.rtl});

  final List<DotWord> words;
  final double fontSize;
  final bool rtl;

  /// The dot's radius: its diameter is about 0.4 of the type size.
  double get radius => fontSize * 0.2;

  /// How long the hop from a pause glyph to the next word takes.
  static const hopOn = Duration(milliseconds: 160);

  /// How long a stressed word's burst lasts.
  static const burstLength = Duration(milliseconds: 520);

  /// Arc heights, in ems (docs/design/prompter.md).
  static const baseHop = 0.5;
  static const slowHop = 0.3;
  static const fastHop = 0.18;
  static const stressHop = 0.85;
  static const lineHop = 0.4;

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

  /// Where the dot rests on the pause or breath glyph after [word].
  Offset? restOnGlyph(int word) {
    final glyph = words[word].gapGlyph;
    if (glyph == null) return null;
    return Offset(glyph.center.dx, glyph.top - radius * 1.2);
  }

  /// The dot at [time] on [timeline]. With [waiting] (voice pace, the
  /// speaker has stopped) it hovers over the word to say, bobbing on
  /// [clock], a wall clock in seconds. With [calm] (reduced motion) it
  /// jumps from word to word: no arcs, squash, swell or bobbing.
  DotFrame? at(DeliveryTimeline timeline, Duration time, {bool waiting = false, double clock = 0, bool calm = false}) {
    if (timeline.isEmpty || timeline.length != words.length) return null;
    final i = timeline.tokenAt(time);
    final here = restOn(i);
    if (here == null) return null;
    final word = words[i];
    final hasNext = i + 1 < words.length;

    if (timeline.isHolding(time) && word.gapGlyph != null && word.gap != null) {
      final (start, end) = timeline.holdAt(time)!;
      final glyph = restOnGlyph(i)!;
      final left = end - time;
      final next = hasNext ? restOn(i + 1) : null;
      if (next != null && left < hopOn && !calm) {
        final u = 1 - left.inMicroseconds / hopOn.inMicroseconds;
        return DotFrame(center: _arc(glyph, next, u, baseHop * 1.1));
      }
      final k = _fraction(time - start, end - start);
      if (word.gap == MarkKind.breath) {
        final swell = calm ? 1.0 : 1 + 0.8 * math.sin(math.pi * k);
        return DotFrame(center: glyph, scaleX: swell, scaleY: swell, tint: DotTint.breath);
      }
      return DotFrame(center: glyph, tint: DotTint.pause, ring: k);
    }

    final tint = word.stressed
        ? DotTint.stress
        : switch (word.run) {
            MarkKind.energy => DotTint.energy,
            MarkKind.slower => DotTint.slower,
            MarkKind.faster => DotTint.faster,
            _ => DotTint.plain,
          };
    if (calm) return DotFrame(center: here, tint: tint);

    if (waiting) {
      final bob = math.sin(clock * 2 * math.pi / 1.4) * fontSize * 0.08;
      return DotFrame(center: here.translate(0, -fontSize * 0.12 + bob));
    }

    // Arc from this word to the next, or onto its pause glyph.
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
    final since = time - timeline.startOf(i);
    final landed = _fraction(since, arrive - timeline.startOf(i));
    var u = landed;
    // To a new line: stay on the word, then swoop down to the next line
    // over the last part of it, rather than crossing the line being read.
    final newLine = (target.dy - here.dy).abs() > fontSize * 0.5;
    if (newLine) u = ((u - lineStay) / (1 - lineStay)).clamp(0.0, 1.0);

    var height = baseHop;
    if (word.run == MarkKind.slower) height = slowHop;
    if (word.run == MarkKind.faster) height = fastHop;
    if (glyph == null && hasNext && words[i + 1].stressed) height = stressHop;
    if (newLine) height = lineHop;

    // Squash on landing, for the first 12% of the word (not at rest on
    // the first word before the take starts).
    final squash = landed > 0 && landed < 0.12 ? (0.12 - landed) * 2.5 : 0.0;
    return DotFrame(
      center: _arc(here, target, u, height),
      scaleX: 1 + squash,
      scaleY: 1 - squash * 0.8,
      tint: tint,
      burst: word.stressed && since < burstLength ? _fraction(since, burstLength) : null,
      sparks: word.run == MarkKind.energy && u > 0.1,
    );
  }

  /// A parabolic hop from [a] to [b], [height] ems at its peak.
  Offset _arc(Offset a, Offset b, double u, double height) {
    final lerp = Offset.lerp(a, b, u)!;
    return lerp.translate(0, -height * fontSize * 4 * u * (1 - u));
  }

  static double _fraction(Duration part, Duration whole) =>
      whole.inMicroseconds <= 0 ? 1 : (part.inMicroseconds / whole.inMicroseconds).clamp(0.0, 1.0);
}

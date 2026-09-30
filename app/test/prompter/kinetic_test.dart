import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/token.dart';
import 'package:spawnalpha/src/prompter/delivery_timeline.dart';
import 'package:spawnalpha/src/prompter/kinetic.dart';

void main() {
  test('liveness wakes words up only near the reading line', () {
    expect(Kinetic.liveness(0), 1);
    expect(Kinetic.liveness(-0.2), 1, reason: 'the line being read');
    expect(Kinetic.liveness(-1), 0, reason: 'already read');
    expect(Kinetic.liveness(Kinetic.wakeLines), 0);
    expect(Kinetic.liveness(5), 0);
    expect(Kinetic.liveness(0.9), closeTo(0.5, 0.01));
    // It falls monotonically ahead of the line.
    var last = 1.0;
    for (var d = 0.0; d <= 2; d += 0.1) {
      final l = Kinetic.liveness(d);
      expect(l, lessThanOrEqualTo(last));
      last = l;
    }
  });

  test('the pop peaks at its amplitude and settles within its window', () {
    var peak = 0.0;
    for (var ms = 0; ms < 600; ms += 2) {
      peak = peak > Kinetic.pop(Duration(milliseconds: ms)) ? peak : Kinetic.pop(Duration(milliseconds: ms));
    }
    expect(peak, closeTo(Kinetic.popAmplitude, 0.001));
    expect(Kinetic.pop(Duration.zero), 0);
    expect(Kinetic.pop(const Duration(milliseconds: 599)).abs(), lessThan(0.005));
    expect(Kinetic.pop(const Duration(milliseconds: -10)), 0);
  });

  test('growing toward the line fits in the room reserved beside the word', () {
    // An eight-character word is about 4.4em wide (0.55em a character).
    const wordEms = 8 * 0.55;
    final grown = Kinetic.stressScale(1, null);
    expect((grown - 1) * wordEms / 2, lessThanOrEqualTo(Kinetic.stressRoom));
  });

  test('a stressed word punches to about 1.3 times as it is spoken', () {
    var peak = 0.0;
    for (var ms = 0; ms < 600; ms += 2) {
      final s = Kinetic.stressScale(1, Duration(milliseconds: ms));
      if (s > peak) peak = s;
    }
    expect(peak, closeTo(1.3, 0.01));
    expect(Kinetic.stressScale(1, const Duration(milliseconds: 599)), closeTo(1 + Kinetic.stressGrowth, 0.01));
  });

  test('energy words hop once, slower words float, staggered', () {
    expect(Kinetic.hop(Duration.zero), 0);
    expect(Kinetic.hop(Kinetic.hopWindow * 0.5), closeTo(1, 0.001));
    expect(Kinetic.hop(Kinetic.hopWindow), 0);
    expect(Kinetic.hop(const Duration(milliseconds: -5)), 0);
    for (var t = 0.0; t < 3; t += 0.1) {
      expect(Kinetic.float(t, 0).abs(), lessThanOrEqualTo(1));
    }
    expect(Kinetic.float(0.4, 0), isNot(Kinetic.float(0.4, 1)), reason: 'neighbours ripple');
  });

  test('hits run for their window only', () {
    expect(Kinetic.hit(Duration.zero), 0);
    expect(Kinetic.hit(const Duration(milliseconds: 260)), closeTo(0.5, 0.01));
    expect(Kinetic.hit(Kinetic.hitWindow), isNull);
  });

  test('the timeline reports the hold the prompter is in', () {
    final tokens = tokenize('one two three');
    final timeline = DeliveryTimeline.build(tokens, [const Mark.gap(id: 'p', kind: MarkKind.pauseLong, after: 0)],
        CoachingStyle.presentation);
    final (start, end) = timeline.holdAt(timeline.endOf(0))!;
    expect(start, timeline.endOf(0));
    expect(end, timeline.startOf(1));
    expect(end - start, CoachingStyle.presentation.longPause);
    expect(timeline.holdAt(timeline.startOf(1)), isNull);
  });
}

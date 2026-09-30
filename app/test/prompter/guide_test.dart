import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/token.dart';
import 'package:spawnalpha/src/prompter/delivery_timeline.dart';
import 'package:spawnalpha/src/prompter/guide.dart';
import 'package:spawnalpha/src/prompter/prompter_layout.dart';

const ms = Duration(milliseconds: 1);

void main() {
  // Four words of equal length (500 ms each at 120 wpm), two per line:
  // 0 and 1 on the first line, 2 and 3 on the second.
  final tokens = tokenize('aaaa bbbb cccc dddd');
  Rect wordBox(int i) => Rect.fromLTWH((i % 2) * 100, (i ~/ 2) * 60, 80, 40);

  DeliveryTimeline timeline(List<Mark> marks) =>
      DeliveryTimeline.build(tokens, marks, CoachingStyle.presentation, wordsPerMinute: 120);

  BouncePath path(List<DotWord> words, {bool rtl = false}) => BouncePath(words: words, fontSize: 40, rtl: rtl);

  List<DotWord> plainWords() => [for (var i = 0; i < 4; i++) DotWord(box: wordBox(i))];

  group('BouncePath', () {
    test('lands on each word as it starts, a third in from the leading edge', () {
      final t = timeline(const []);
      final p = path(plainWords());
      expect(p.restOn(0)!.dx, closeTo(80 / 3, 0.01));
      expect(p.restOn(0)!.dy, lessThan(0), reason: 'above the word');
      expect(p.at(t, t.startOf(0))!.center, p.restOn(0));
      expect(p.at(t, t.startOf(1))!.center, p.restOn(1));
    });

    test('arcs above the straight line between two words', () {
      final t = timeline(const []);
      final p = path(plainWords());
      final mid = p.at(t, t.startOf(0) + ms * 250)!.center;
      final straight = Offset.lerp(p.restOn(0), p.restOn(1), 0.5)!;
      expect(mid.dx, closeTo(straight.dx, 0.01));
      expect(mid.dy, straight.dy - BouncePath.baseHop * 40);
    });

    test('squashes as it lands', () {
      final t = timeline(const []);
      final landing = path(plainWords()).at(t, t.startOf(1) + ms * 10)!;
      expect(landing.scaleX, greaterThan(1));
      expect(landing.scaleY, lessThan(1));
    });

    test('stays on the last word of a line, then swoops to the next line', () {
      final t = timeline(const []);
      final p = path(plainWords());
      // Word 1 ends the first line: it stays for the first 60%.
      expect(p.at(t, t.startOf(1) + ms * 250)!.center, p.restOn(1));
      final swoop = p.at(t, t.startOf(1) + ms * 450)!.center;
      expect(swoop, isNot(p.restOn(1)));
      expect(p.at(t, t.startOf(2))!.center, p.restOn(2));
    });

    test('rests on a pause glyph while a ring closes, then hops on', () {
      final marks = [const Mark.gap(id: 'p', kind: MarkKind.pauseLong, after: 0)];
      final t = timeline(marks);
      final words = plainWords();
      words[0] = DotWord(box: wordBox(0), gap: MarkKind.pauseLong, gapGlyph: const Rect.fromLTWH(84, 8, 12, 24));
      final p = path(words);
      final glyph = p.restOnGlyph(0)!;
      // Arrives on the glyph as the hold starts.
      expect(p.at(t, t.endOf(0) - ms)!.center.dx, closeTo(glyph.dx, 1));
      final (start, end) = t.holdAt(t.endOf(0) + ms)!;
      final early = p.at(t, start + (end - start) * 0.25)!;
      final late = p.at(t, start + (end - start) * 0.75)!;
      expect(early.center, glyph);
      expect(early.tint, DotTint.pause);
      expect(early.ring, lessThan(late.ring!));
      // The last moment of the hold: on its way to the next word, in white.
      final hop = p.at(t, end - ms * 40)!;
      expect(hop.center, isNot(glyph));
      expect(hop.tint, DotTint.plain);
      expect(hop.ring, isNull);
    });

    test('swells on a breath', () {
      final t = timeline([const Mark.gap(id: 'b', kind: MarkKind.breath, after: 0)]);
      final words = plainWords();
      words[0] = DotWord(box: wordBox(0), gap: MarkKind.breath, gapGlyph: const Rect.fromLTWH(84, 8, 12, 24));
      final (start, end) = t.holdAt(t.endOf(0) + ms)!;
      final frame = path(words).at(t, start + (end - start) * 0.5)!;
      expect(frame.tint, DotTint.breath);
      expect(frame.scaleX, greaterThan(1.5));
    });

    test('jumps high into a stressed word, and bursts as it lands', () {
      final t = timeline(const []);
      final words = plainWords();
      words[1] = DotWord(box: wordBox(1), stressed: true);
      final p = path(words);
      final straight = Offset.lerp(p.restOn(0), p.restOn(1), 0.5)!;
      expect(p.at(t, t.startOf(0) + ms * 250)!.center.dy, closeTo(straight.dy - BouncePath.stressHop * 40, 0.01));
      final landed = p.at(t, t.startOf(1) + ms * 100)!;
      expect(landed.tint, DotTint.stress);
      expect(landed.burst, isNotNull);
      expect(p.at(t, t.startOf(1) + ms * 600)?.burst, isNull);
    });

    test('pace runs shape the hop, energy throws sparks', () {
      final t = timeline(const []);
      double peak(MarkKind run) {
        final words = plainWords();
        words[0] = DotWord(box: wordBox(0), run: run);
        return path(words).at(t, t.startOf(0) + ms * 250)!.center.dy;
      }

      final base = path(plainWords()).at(t, t.startOf(0) + ms * 250)!.center.dy;
      expect(peak(MarkKind.slower), greaterThan(base), reason: 'slow runs float low');
      expect(peak(MarkKind.faster), greaterThan(peak(MarkKind.slower)), reason: 'fast runs skip');
      final words = plainWords();
      words[0] = DotWord(box: wordBox(0), run: MarkKind.energy);
      final energy = path(words).at(t, t.startOf(0) + ms * 250)!;
      expect(energy.tint, DotTint.energy);
      expect(energy.sparks, isTrue);
    });

    test('bobs over the word while it waits for the voice', () {
      final t = timeline(const []);
      final p = path(plainWords());
      final a = p.at(t, t.startOf(0) + ms * 200, waiting: true, clock: 0.35)!.center;
      final b = p.at(t, t.startOf(0) + ms * 200, waiting: true, clock: 1.05)!.center;
      expect(a.dx, p.restOn(0)!.dx);
      expect(a.dy, isNot(b.dy));
    });

    test('with reduced motion it jumps from word to word', () {
      final t = timeline(const []);
      final p = path(plainWords());
      expect(p.at(t, t.startOf(0) + ms * 250, calm: true)!.center, p.restOn(0));
    });

    test('right to left, it lands a third in from the right edge', () {
      final p = path(plainWords(), rtl: true);
      expect(p.restOn(0)!.dx, closeTo(80 - 80 / 3, 0.01));
    });
  });

  group('guide and motion choices', () {
    test('G cycles through every guide', () {
      expect(PrompterGuide.dot.next, PrompterGuide.underline);
      expect(PrompterGuide.off.next, PrompterGuide.dot);
    });

    test('unknown names fall back to the defaults', () {
      expect(PrompterGuide.fromName('spotlight'), PrompterGuide.spotlight);
      expect(PrompterGuide.fromName(null), PrompterGuide.dot);
      expect(PrompterMotion.fromName('bogus'), PrompterMotion.lineStep);
    });

    test('smooth motion scrolls through a line, line step holds it', () {
      final layout = PrompterLayout(lineOfToken: [0, 0, 1, 1], lineTops: [0, 40], lineBottoms: [40, 80]);
      final t = timeline(const []);
      final halfway = t.startOf(1);
      expect(layout.scrollYAt(t, halfway), 0);
      expect(layout.scrollYAt(t, halfway, motion: PrompterMotion.smooth), closeTo(20, 0.01));
      expect(layout.scrollYAt(t, t.startOf(2), motion: PrompterMotion.smooth), 40);
    });
  });
}

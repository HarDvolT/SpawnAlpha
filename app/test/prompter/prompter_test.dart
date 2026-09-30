import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/token.dart';
import 'package:spawnalpha/src/prompter/delivery_timeline.dart';
import 'package:spawnalpha/src/prompter/prompter_controller.dart';
import 'package:spawnalpha/src/prompter/prompter_layout.dart';

const ms = Duration(milliseconds: 1);

void main() {
  group('DeliveryTimeline', () {
    // Five words of equal length, so each takes exactly 60/120 s = 500 ms.
    final tokens = tokenize('aaaa bbbb cccc dddd eeee');

    test('spaces words at the target words per minute', () {
      final t = DeliveryTimeline.build(tokens, const [], CoachingStyle.presentation, wordsPerMinute: 120);
      expect(t.startOf(1), ms * 500);
      expect(t.total, ms * 2500);
      expect(t.tokenAt(ms * 1200), 2);
      expect(t.isHolding(ms * 1200), isFalse);
    });

    test('holds at pause marks and does not count holds as speech', () {
      final t = DeliveryTimeline.build(
        tokens,
        [const Mark.gap(id: 'p', kind: MarkKind.pauseLong, after: 1)],
        CoachingStyle.presentation,
        wordsPerMinute: 120,
      );
      final long = CoachingStyle.presentation.longPause;
      expect(t.startOf(2), ms * 1000 + long);
      expect(t.holdingOn(ms * 1100), MarkKind.pauseLong);
      expect(t.tokenAt(ms * 1100), 1);
      // The spoken clock stops during the hold.
      expect(t.spokenAt(ms * 1100), ms * 1000);
      expect(t.spokenAt(ms * 1000 + long + ms * 100), ms * 1100);
    });

    test('stretches slower spans and squeezes faster ones', () {
      final t = DeliveryTimeline.build(
        tokens,
        const [
          Mark(id: 's', kind: MarkKind.slower, start: 0, end: 0),
          Mark(id: 'f', kind: MarkKind.faster, start: 1, end: 1),
        ],
        CoachingStyle.presentation,
        wordsPerMinute: 120,
      );
      expect(t.endOf(0), ms * 625);
      expect(t.endOf(1) - t.startOf(1), ms * 400);
    });

    test('gives longer words more time and adds beats at punctuation', () {
      final t = DeliveryTimeline.build(tokenize('a extraordinary. b'), const [], CoachingStyle.tutorial);
      final short = t.endOf(0) - t.startOf(0);
      final long = t.endOf(1) - t.startOf(1);
      expect(long, greaterThan(short * 2));
      expect(t.isHolding(t.endOf(1) + ms), isTrue);
      expect(t.holdingOn(t.endOf(1) + ms), isNull, reason: 'a natural beat is not a mark');
    });
  });

  group('PrompterLayout.scrollYAt', () {
    // Two lines: tokens 0-1 on the first, 2-3 on the second.
    final tokens = tokenize('aaaa bbbb cccc dddd');
    final layout = PrompterLayout(lineOfToken: [0, 0, 1, 1], lineTops: [0, 40], lineBottoms: [40, 80]);

    test('moves evenly through a line and stands still at a pause', () {
      final t = DeliveryTimeline.build(
        tokens,
        [const Mark.gap(id: 'p', kind: MarkKind.pauseShort, after: 0)],
        CoachingStyle.presentation,
        wordsPerMinute: 120,
      );
      expect(layout.scrollYAt(t, Duration.zero), 0);
      expect(layout.scrollYAt(t, ms * 250), 10);
      // Holding after the first word: still halfway through line one.
      expect(layout.scrollYAt(t, ms * 600), 20);
      expect(layout.scrollYAt(t, t.startOf(1)), 20);
      expect(layout.scrollYAt(t, t.startOf(2)), 40);
      expect(layout.scrollYAt(t, t.total), 80);
    });

    test('finds the first word on the line at a position', () {
      expect(layout.tokenAtY(10), 0);
      expect(layout.tokenAtY(50), 2);
      expect(layout.tokenAtY(500), 2);
    });
  });

  group('PrompterController', () {
    ScriptDocument script() => ScriptDocument.create(
          text: 'First sentence here. Second one now. Third.',
          language: ScriptLanguage.en,
          style: CoachingStyle.presentation,
        ).copyWith(marks: [
          const Mark.gap(id: 'a', kind: MarkKind.pauseLong, after: 2),
          const Mark.gap(id: 'p', kind: MarkKind.pauseShort, after: 5, accepted: false),
        ]);

    test('uses only accepted marks', () {
      final c = PrompterController(script());
      expect(c.marks.map((m) => m.id), ['a']);
    });

    test('advances only while playing in timed mode, then finishes', () {
      final c = PrompterController(script());
      c.advance(const Duration(seconds: 1));
      expect(c.position, Duration.zero);
      c.play();
      c.advance(const Duration(seconds: 1));
      expect(c.position, const Duration(seconds: 1));
      c.setMode(ScrollMode.manual);
      expect(c.state, PlaybackState.paused);
      c.setMode(ScrollMode.timed);
      c.play();
      c.advance(const Duration(minutes: 1));
      expect(c.state, PlaybackState.finished);
      expect(c.currentToken, c.tokens.length - 1);
    });

    test('speed scales time and stays in range', () {
      final c = PrompterController(script())..play();
      c.setSpeed(1.5);
      c.advance(const Duration(seconds: 1));
      expect(c.position, const Duration(milliseconds: 1500));
      c.setSpeed(9);
      expect(c.speed, PrompterController.maxSpeed);
      for (var i = 0; i < 30; i++) {
        c.slower();
      }
      expect(c.speed, PrompterController.minSpeed);
    });

    test('reports the pause it is holding on', () {
      final c = PrompterController(script())..play();
      c.advance(c.timeline.endOf(2) + ms * 10);
      expect(c.currentToken, 2);
      expect(c.holding, MarkKind.pauseLong);
    });

    test('jumps between sentences', () {
      final c = PrompterController(script());
      c.nextSentence();
      expect(c.currentToken, 3);
      c.nextSentence();
      expect(c.currentToken, 6);
      c.previousSentence();
      expect(c.currentToken, 3);
      c.seekToToken(4);
      c.previousSentence();
      expect(c.currentToken, 3);
    });

    test('notifies on word changes, not every frame', () {
      final c = PrompterController(script())..play();
      var notified = 0;
      c.addListener(() => notified++);
      c.advance(ms);
      c.advance(ms);
      expect(notified, 0);
      c.advance(const Duration(seconds: 1));
      expect(notified, greaterThan(0));
    });

    test('keeps the reader near the same word after an edit', () {
      final c = PrompterController(script());
      c.seekToToken(4);
      c.updateScript(c.script.withText('First sentence here. Second one now. Third. Fourth.'));
      expect(c.currentToken, 4);
      expect(c.tokens, hasLength(8));
    });
  });
}

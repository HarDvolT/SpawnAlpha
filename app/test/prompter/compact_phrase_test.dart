import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/token.dart';
import 'package:spawnalpha/src/prompter/delivery_timeline.dart';
import 'package:spawnalpha/src/prompter/guide.dart';
import 'package:spawnalpha/src/prompter/prompter_layout.dart';

void main() {
  for (final text in [
    'This phrase stays visible',
    'Une phrase très longue',
    'هذه عبارة طويلة واضحة',
  ]) {
    test('compact long phrase keeps its current line and pause: $text', () {
      final tokens = tokenize(text);
      expect(tokens.length, 4);
      final timeline = DeliveryTimeline.build(tokens, const [
        Mark.gap(id: 'p', kind: MarkKind.pauseShort, after: 1),
      ], CoachingStyle.presentation);
      final layout = PrompterLayout(
        lineOfToken: [0, 1, 2, 2],
        lineTops: [0, 50, 100],
        lineBottoms: [50, 100, 150],
        phraseStarts: [0],
      );
      expect(
        layout.scrollYAt(
          timeline,
          timeline.startOf(2),
          motion: PrompterMotion.phrase,
        ),
        0,
      );
      expect(
        layout.scrollYAt(
          timeline,
          timeline.startOf(2),
          motion: PrompterMotion.phrase,
          phraseViewportHeight: 150,
        ),
        0,
      );
      expect(
        layout.scrollYAt(
          timeline,
          timeline.startOf(2),
          motion: PrompterMotion.phrase,
          phraseViewportHeight: 80,
        ),
        100,
      );
      expect(
        layout.scrollYAt(
          timeline,
          timeline.endOf(1) + const Duration(milliseconds: 1),
          motion: PrompterMotion.phrase,
          phraseViewportHeight: 80,
        ),
        50,
      );
    });
  }
}

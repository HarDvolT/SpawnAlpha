import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/token.dart';
import 'package:spawnalpha/src/prompter/marked_text.dart';

void main() {
  final marks = [
    const Mark(id: 'e', kind: MarkKind.energy, start: 1, end: 2),
    const Mark.gap(id: 'p', kind: MarkKind.pauseShort, after: 1),
    const Mark(id: 's', kind: MarkKind.stress, start: 0, end: 0),
  ];

  /// Left edges of: word 1, the energy cue that opens it, and the pause
  /// cue after it.
  Future<({double word, double opening, double pause})> layOut(
    WidgetTester tester,
    String text,
    TextDirection direction,
  ) async {
    final tokens = tokenize(text);
    final marked = MarkedText.build(
      tokens: tokens,
      marks: marks,
      style: const TextStyle(fontSize: 20),
      colors: CueColors.light,
    );
    final key = GlobalKey();
    await tester.pumpWidget(Directionality(
      textDirection: direction,
      child: Center(child: SizedBox(width: 600, child: Text.rich(key: key, marked.span, textDirection: direction))),
    ));
    final paragraph = key.currentContext!.findRenderObject()! as RenderParagraph;
    double left(int start, int end) =>
        paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end)).first.left;
    final wordStart = marked.tokenOffsets[1];
    final opening = marked.cueRanges.firstWhere((r) => r.$3 == 1 && r.$2 <= wordStart);
    final pause = marked.cueRanges.firstWhere((r) => r.$3 == 1 && r.$1 >= wordStart);
    // Measure the glyphs, not the thin spaces beside them. Some icon glyphs
    // lie outside the basic plane and take two UTF-16 units.
    return (
      word: left(wordStart, wordStart + tokens[1].text.length),
      opening: left(opening.$1, opening.$2 - 1),
      pause: left(pause.$1 + 1, pause.$2),
    );
  }

  testWidgets('cues sit on the correct side of their word, left to right', (tester) async {
    final x = await layOut(tester, 'Stop scrolling now, friends', TextDirection.ltr);
    expect(x.opening, lessThan(x.word));
    expect(x.pause, greaterThan(x.word));
  });

  testWidgets('cues sit on the correct side of their word, right to left', (tester) async {
    final x = await layOut(tester, 'توقف عن التمرير الآن يا أصدقاء', TextDirection.rtl);
    expect(x.opening, greaterThan(x.word), reason: 'the energy cue opens the run, to the right');
    expect(x.pause, lessThan(x.word), reason: 'the pause follows the word, to the left');
  });

  test('taps on a cue open the word it belongs to', () {
    final tokens = tokenize('one two three');
    final marked = MarkedText.build(tokens: tokens, marks: marks, style: const TextStyle(), colors: CueColors.light);
    for (final (start, _, token) in marked.cueRanges) {
      expect(marked.tokenForTap(start, tokens), token);
    }
    expect(marked.tokenForTap(marked.tokenOffsets[2] + 1, tokens), 2);
  });
}

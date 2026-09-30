import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/token.dart';
import 'package:spawnalpha/src/prompter/marked_text.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/format.dart';
import 'package:spawnalpha/src/ui/script_page.dart';

void main() {
  Future<RenderScriptPage> pumpPage(
    WidgetTester tester, {
    required String text,
    required List<Mark> marks,
    double width = 900,
    TextDirection direction = TextDirection.ltr,
    double reveal = 1,
  }) async {
    final tokens = tokenize(text);
    final marked = MarkedText.build(
      tokens: tokens,
      marks: marks,
      style: SaType.scriptEdit,
      colors: CueColors.studioLight,
      stressStyle: StressStyle.marker,
    );
    final notes = [
      for (final m in marks)
        if (m.note != null) PageNote(offset: marked.tokenOffsets[m.kind.isGap ? m.end : m.start], text: m.note!),
    ];
    await tester.pumpWidget(Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: ScriptPage(
            text: marked.span,
            textDirection: direction,
            markers: marked.stressRanges,
            notes: notes,
            markerColor: CueColors.studioLight.marker,
            noteStyle: SaType.note,
            ruleColor: SaPalette.light.line,
            reveal: reveal,
          ),
        ),
      ),
    ));
    return tester.renderObject<RenderScriptPage>(find.byType(ScriptPage));
  }

  const text = 'Last quarter our team answered twelve thousand tickets. That is twice as many as the year '
      'before with the same people. So how did we do it? We stopped answering the same question twice.';
  final marks = [
    const Mark(id: 's1', kind: MarkKind.stress, start: 5, end: 6, note: 'the number is the story'),
    const Mark(id: 's2', kind: MarkKind.stress, start: 10, end: 10),
    const Mark.gap(id: 'p', kind: MarkKind.pauseLong, after: 7, note: 'let it land'),
    const Mark(id: 'e', kind: MarkKind.energy, start: 18, end: 23, note: 'lift, this is the turn'),
  ];

  testWidgets('notes sit in the trailing margin, level with their lines and never overlapping', (tester) async {
    final page = await pumpPage(tester, text: text, marks: marks);
    final notes = page.noteRects;
    expect(notes, hasLength(3));
    final twelve = page.plainText.indexOf('twelve');
    expect(notes.first.top, closeTo(page.rectOf(twelve, twelve + 6)!.top, 1));
    for (var i = 1; i < notes.length; i++) {
      expect(notes[i].top, greaterThanOrEqualTo(notes[i - 1].bottom), reason: 'notes stack, they never overlap');
    }
    // The margin is to the right of the text in a left-to-right script.
    expect(notes.first.left, greaterThan(page.rectOf(twelve, twelve + 6)!.right));
  });

  testWidgets('a note that cannot sit near its line stays out of the margin', (tester) async {
    // Three long notes on the same line: the third would drift too far.
    final crowded = [
      const Mark(id: 'a', kind: MarkKind.stress, start: 0, end: 0, note: 'a long note that takes more than one line here'),
      const Mark(id: 'b', kind: MarkKind.stress, start: 1, end: 1, note: 'another long note taking up two lines of margin'),
      const Mark(id: 'c', kind: MarkKind.stress, start: 2, end: 2, note: 'and a third one that has no room left beside it'),
    ];
    final page = await pumpPage(tester, text: text, marks: crowded);
    expect(page.noteRects.length, lessThan(3));
    final first = page.rectOf(0, 4)!;
    for (final note in page.noteRects) {
      expect(note.top - first.top, lessThanOrEqualTo(first.height * 1.2 + 1));
    }
  });

  testWidgets('in Arabic the margin is on the left', (tester) async {
    const arabic = 'في الربع الأخير أجاب فريق الدعم على اثني عشر ألف تذكرة أي ضعف ما أجبنا عليه العام الماضي';
    final page = await pumpPage(tester, text: arabic, marks: [
      const Mark(id: 's', kind: MarkKind.stress, start: 7, end: 9, note: 'الرقم هو القصة'),
    ], direction: TextDirection.rtl);
    final word = page.plainText.indexOf('اثني');
    expect(page.noteRects.single.right, lessThan(page.rectOf(word, word + 4)!.left));
  });

  testWidgets('the margin folds away on narrow screens', (tester) async {
    final page = await pumpPage(tester, text: text, marks: marks, width: 400);
    expect(page.noteRects, isEmpty);
  });

  testWidgets('taps map to the word under them, and never in the margin', (tester) async {
    final page = await pumpPage(tester, text: text, marks: marks);
    final twice = page.plainText.indexOf('twice');
    final offset = page.textOffsetAt(page.rectOf(twice, twice + 5)!.center)!;
    expect(offset, inInclusiveRange(twice, twice + 5));
    expect(page.textOffsetAt(page.noteRects.first.center), isNull);
  });

  testWidgets("the director's pass paints marks in without moving the text", (tester) async {
    final before = await pumpPage(tester, text: text, marks: marks, reveal: 0);
    final size = before.size;
    final twice = before.plainText.indexOf('twice');
    final rect = before.rectOf(twice, twice + 5);
    final after = await pumpPage(tester, text: text, marks: marks, reveal: 1);
    expect(after.size, size);
    expect(after.rectOf(twice, twice + 5), rect);
  });

  test('pencil case lowers a note unless it opens with an acronym', () {
    expect(pencilCase('Let the key point sink in'), 'let the key point sink in');
    expect(pencilCase('AI picks the pace'), 'AI picks the pace');
    expect(pencilCase('Laisse respirer'), 'laisse respirer');
    expect(pencilCase('الرقم هو القصة'), 'الرقم هو القصة');
  });
}

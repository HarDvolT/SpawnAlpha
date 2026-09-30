import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/mark_editing.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';

void main() {
  ScriptDocument script(List<Mark> marks) => ScriptDocument.create(
        text: 'We grew fast. Then we slowed down.',
        language: ScriptLanguage.en,
        style: CoachingStyle.presentation,
      ).copyWith(marks: marks);

  const pending = Mark(id: 's', kind: MarkKind.stress, start: 1, end: 1, origin: MarkOrigin.local, accepted: false);
  const pause = Mark.gap(id: 'p', kind: MarkKind.pauseShort, after: 2, origin: MarkOrigin.local, accepted: false);

  test('marksAt finds spans over a word and the gap after it', () {
    final s = script([pending, pause]);
    expect(s.marksAt(1).map((m) => m.id), ['s']);
    expect(s.marksAt(2).map((m) => m.id), ['p']);
    expect(s.marksAt(3), isEmpty);
  });

  test('accept, change and remove', () {
    var s = script([pending, pause]);
    s = s.acceptMark('s');
    expect(s.marks.firstWhere((m) => m.id == 's').accepted, isTrue);
    s = s.changeMarkKind('p', MarkKind.pauseLong);
    expect(s.marks.firstWhere((m) => m.id == 'p').kind, MarkKind.pauseLong);
    expect(s.marks.firstWhere((m) => m.id == 'p').accepted, isTrue);
    s = s.removeMark('s');
    expect(s.marks.map((m) => m.id), ['p']);
  });

  test('accept all and discard pending', () {
    final s = script([pending, pause]);
    expect(s.acceptAllMarks().pendingCount, 0);
    expect(s.acceptMark('p').discardPendingMarks().marks.map((m) => m.id), ['p']);
  });

  test('adds a pace run over the whole sentence, replacing the old one', () {
    var s = script([]).addMark(MarkKind.slower, 5);
    final slower = s.marks.single;
    expect((slower.start, slower.end, slower.origin, slower.accepted), (3, 6, MarkOrigin.user, true));
    s = s.addMark(MarkKind.faster, 4);
    expect(s.marks.single.kind, MarkKind.faster);
  });

  test('adds gap marks after a word but never after the last', () {
    final s = script([pause]);
    expect(s.addMark(MarkKind.breath, 2).marks.single.kind, MarkKind.breath);
    expect(s.canAddMark(MarkKind.pauseLong, 6), isFalse);
    expect(s.addMark(MarkKind.pauseLong, 6).marks, s.marks);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/prompter/delivery_timeline.dart';

import '../../tool/fixtures/cue_check_scripts.dart';

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'the ${language.name} hardware cue check covers every accepted cue',
      () {
        final script = cueCheckScript(language);
        expect(script.pendingCount, 0);
        expect(
          script.marks.map((m) => m.kind).toSet(),
          MarkKind.values.toSet(),
        );
        expect(script.marks, hasLength(MarkKind.values.length));
        expect(script.takes, isEmpty);
        expect(script.suggestions, isEmpty);
        expect(
          script.marks,
          normalizeMarks(script.marks, script.tokens.length),
        );
        expect(ScriptDocument.fromJson(script.toJson()).marks, script.marks);
        for (final mark in script.marks.where((m) => m.kind.isGap)) {
          expect(mark.end, lessThan(script.tokens.length - 1));
        }
        final timeline = DeliveryTimeline.build(
          script.tokens,
          script.marks,
          script.style,
        );
        for (final kind in [
          MarkKind.pauseShort,
          MarkKind.pauseLong,
          MarkKind.breath,
        ]) {
          final mark = script.marks.singleWhere((m) => m.kind == kind);
          expect(
            timeline.holdingOn(
              timeline.endOf(mark.end) + const Duration(milliseconds: 1),
            ),
            kind,
          );
        }
      },
    );
  }
}

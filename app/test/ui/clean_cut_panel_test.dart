import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/clean_cut_panel.dart';

import '../cut/clean_plan_test.dart' show cleanFixture, gap;

void main() {
  testWidgets('each removal can be restored with the visible switch', (
    tester,
  ) async {
    final words = cleanFixture(ScriptLanguage.en);
    var plan = planQuietCut(
      takeId: 'generated',
      transcript: words,
      quiet: [gap()],
      snapshot: ScriptDocument.create().copyWith(
        recordingAid: RecordingAid.notes,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => CleanCutPanel(
              plan: plan,
              busy: false,
              onChanged: (id, value) =>
                  update(() => plan = plan.withEnabled(id, value)),
              onRestore: () => update(() => plan = plan.restoreAll()),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Removed'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('Original restored'), findsOneWidget);
    expect(plan.asCutPlan().duration, words.duration);
    expect(find.text('Restore all gaps'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore all gaps'));
    await tester.pumpAndSettle();
    expect(plan.asCutPlan().duration, words.duration);
    expect(tester.takeException(), isNull);
  });
}

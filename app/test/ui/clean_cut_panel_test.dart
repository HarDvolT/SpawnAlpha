import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/clean_cut_panel.dart';

import '../cut/clean_plan_test.dart' show cleanFixture, gap;
import '../cut/filler_review_test.dart' show fillerFixture, fillerPlan;

void main() {
  for (final language in ScriptLanguage.values) {
    testWidgets(
      'filler begins kept, uses script direction and restores $language',
      (tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final words = fillerFixture(language);
        var plan = fillerPlan(words);
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
        expect(find.text('Possible filler'), findsOneWidget);
        expect(find.textContaining('Kept · check meaning'), findsOneWidget);
        final textContext = tester.element(find.text(words.words[1].text));
        expect(
          Directionality.of(textContext),
          language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        );
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(speechOnCleanCut(words, plan).words, hasLength(2));
        expect(find.textContaining('Removed'), findsOneWidget);
        await tester.tap(find.text('Restore all changes'));
        await tester.pumpAndSettle();
        expect(speechOnCleanCut(words, plan).words, hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  }
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

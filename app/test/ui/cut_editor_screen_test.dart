import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/cut_editor_screen.dart';

import '../cut/cut_editor_test.dart' show editorFixture;
import '../playback/playback_controller_test.dart' show FakePlayback;

void main() {
  for (final language in ScriptLanguage.values) {
    for (final action in ['save', 'cancel', 'reset', 'restore', 'listen']) {
      testWidgets('quiet-gap editor $action on a phone $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final plan = editorFixture(language), player = FakePlayback();
        CleanPlan? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Edit'),
                  onPressed: () async {
                    saved = await Navigator.of(context).push<CleanPlan>(
                      MaterialPageRoute(
                        builder: (_) => Directionality(
                          textDirection: language.isRtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: CutEditorScreen(
                            plan: plan,
                            take: Take(
                              path: 'generated',
                              recordedAt: DateTime(2026),
                              duration: plan.sourceDuration,
                            ),
                            playback: player,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(player.commands, isEmpty);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save changes'),
              )
              .onPressed,
          isNull,
        );
        final handles = find.byType(RangeSlider);
        await tester.scrollUntilVisible(
          handles,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(handles);
        await tester.dragFrom(
          Offset(rect.left + 24, rect.center.dy),
          Offset(rect.width * .25, 0),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<RangeSlider>(handles).values.start,
          greaterThan(0),
        );
        expect(
          tester.widget<RangeSlider>(handles).values.end,
          plan.changes.single.range.duration.inMicroseconds,
        );
        expect(plan.changes.single.originalRange, isNull);
        if (action == 'reset') {
          await tester.ensureVisible(find.text('Reset handles'));
          await tester.tap(find.text('Reset handles'));
          await tester.pumpAndSettle();
          expect(tester.widget<RangeSlider>(handles).values.start, 0);
        } else if (action == 'restore') {
          await tester.ensureVisible(find.text('Keep this gap'));
          await tester.tap(find.text('Keep this gap'));
          await tester.pumpAndSettle();
          expect(tester.widget<RangeSlider>(handles).onChanged, isNull);
          expect(find.text('Original gap kept'), findsOneWidget);
        } else if (action == 'listen') {
          await tester.ensureVisible(find.text('Hear original gap'));
          await tester.tap(find.text('Hear original gap'));
          await tester.pumpAndSettle();
          expect(player.commands, [
            'pause',
            'seek:650000',
            'mute:false',
            'play',
          ]);
          expect(
            find.textContaining('Original take · Phrase preview'),
            findsOneWidget,
          );
        }
        await tester.tap(
          find.text(
            action == 'cancel' || action == 'listen'
                ? 'Cancel'
                : 'Save changes',
          ),
        );
        await tester.pumpAndSettle();
        if (action == 'save') {
          expect(
            saved!.asCutPlan().duration,
            greaterThan(plan.asCutPlan().duration),
          );
          expect(
            saved!.changes.single.bounds.toJson(),
            plan.changes.single.range.toJson(),
          );
        } else if (action == 'reset') {
          expect(saved!.asCutPlan().toJson(), plan.asCutPlan().toJson());
        } else if (action == 'restore') {
          expect(saved!.asCutPlan().duration, plan.sourceDuration);
        } else {
          expect(saved, isNull);
        }
        expect(player.closed, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('long gap lists page and keep disabled edits intact', (
    tester,
  ) async {
    final initial = editorFixture(ScriptLanguage.en);
    final plan = CleanPlan(
      takeId: initial.takeId,
      language: initial.language,
      sourceDuration: const Duration(seconds: 30),
      changes: [
        for (var i = 0; i < 10; ++i)
          CutChange(
            id: 'quiet-$i',
            enabled: false,
            range: SourceRange(
              start:
                  initial.changes.single.range.start + Duration(seconds: i * 3),
              end: initial.changes.single.range.end + Duration(seconds: i * 3),
            ),
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: CutEditorScreen(
          plan: plan,
          take: Take(
            path: 'generated',
            recordedAt: DateTime(2026),
            duration: plan.sourceDuration,
          ),
          playback: FakePlayback(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Next gaps'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next gaps'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Page 2 of 2'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Gap 10 ·'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Gap 10 ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

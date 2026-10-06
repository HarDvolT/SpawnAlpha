import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/review/repeated_sections.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/retake_review_panel.dart';

import '../review/repeated_sections_test.dart'
    show repeatedScript, repeatedSpeech;
import '../cut/retake_review_test.dart'
    show retakeWords, retakeScript, retakePlan;

import 'package:spawnalpha/src/cut/clean_plan.dart';

void main() {
  for (final language in ScriptLanguage.values) {
    testWidgets(
      'choose and restore an attempt without changing original listening $language',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final words = retakeWords(language),
            sections = repeatedSections(
              retakeScript(language),
              retakeWords(language),
            );
        var plan = retakePlan(words).restoreAll();
        SourceRange? heard;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => ListView(
                  padding: const EdgeInsets.all(SaSpace.s5),
                  children: [
                    RetakeReviewPanel(
                      sections: sections,
                      busy: false,
                      plan: plan,
                      onSelect: (id, index) =>
                          update(() => plan = plan.withAttempt(id, index)),
                      onListen: (range) => heard = range,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Keep attempt 2'));
        await tester.pumpAndSettle();
        expect(plan.retakes.single.selected, 1);
        expect(find.text('Removed from cut'), findsOneWidget);
        expect(find.text('Kept in cut'), findsOneWidget);
        expect(speechOnCleanCut(words, plan).words, hasLength(3));
        await tester.tap(find.text('Hear attempt 1'));
        expect(heard, same(sections.single.attempts.first.range));
        await tester.tap(find.text('Keep all attempts'));
        await tester.pumpAndSettle();
        expect(plan.retakes.single.selected, isNull);
        expect(speechOnCleanCut(words, plan).words, hasLength(6));
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'unsafe and busy choices explain why they stay kept $language',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final words = retakeWords(language),
            sections = repeatedSections(
              retakeScript(language),
              retakeWords(language),
            );
        final plan = retakePlan(words, quiet: []);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: RetakeReviewPanel(
                sections: sections,
                busy: false,
                plan: plan,
                onSelect: (_, _) => fail('Unsafe removal'),
                onListen: (_) {},
              ),
            ),
          ),
        );
        expect(
          find.text('A safe cut was not found. Keep the attempts together.'),
          findsNWidgets(2),
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Keep attempt 2'),
              )
              .onPressed,
          isNull,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: RetakeReviewPanel(
                sections: sections,
                busy: true,
                plan: retakePlan(words),
                onSelect: (_, _) => fail('Busy removal'),
                onListen: (_) => fail('Busy listening'),
              ),
            ),
          ),
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Keep attempt 1'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Hear attempt 1'),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'attempts show actual words, partial coverage and explicit sound $language',
      (tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final script = repeatedScript(language);
        final sections = repeatedSections(
          script,
          repeatedSpeech(script, partial: true, confidence: null),
        );
        SourceRange? heard;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(SaSpace.s5),
                children: [
                  RetakeReviewPanel(
                    sections: sections,
                    busy: false,
                    onListen: (range) => heard = range,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(
          find.textContaining('3 of 5 script words matched · Partial section'),
          findsOneWidget,
        );
        expect(find.text('3 words need a wording check'), findsOneWidget);
        final actual = find.text(sections.single.attempts.first.text);
        expect(
          Directionality.of(tester.element(actual)),
          language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(heard, isNull);
        await tester.tap(find.text('Hear attempt 1'));
        expect(heard, same(sections.single.attempts.first.range));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: RetakeReviewPanel(
                sections: sections,
                busy: true,
                onListen: (_) => fail('Busy review must not start sound'),
              ),
            ),
          ),
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Hear attempt 1'),
              )
              .onPressed,
          isNull,
        );
      },
    );
    testWidgets(
      'attempt and section pages are bounded and reset with new words $language',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final script = repeatedScript(language);
        final two = script.withText('${script.text} ${script.text}');
        final sections = repeatedSections(
          two,
          repeatedSpeech(two, attempts: 4),
        );
        Widget panel(List<RepeatedSection> value) => MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: RetakeReviewPanel(
              sections: value,
              busy: false,
              onListen: (_) {},
            ),
          ),
        );
        await tester.pumpWidget(panel(sections));
        expect(find.text('Attempt 4 of 4'), findsNothing);
        await tester.tap(find.text('More attempts'));
        await tester.pump();
        expect(find.text('Attempt 4 of 4'), findsOneWidget);
        expect(find.text('Attempt 1 of 4'), findsNothing);
        await tester.tap(find.text('Next section'));
        await tester.pump();
        expect(find.text('Repeated section 2 of 2'), findsOneWidget);
        expect(find.text('Attempt 1 of 4'), findsOneWidget);
        await tester.pumpWidget(
          panel(repeatedSections(script, repeatedSpeech(script))),
        );
        expect(find.text('Repeated section 1 of 1'), findsOneWidget);
        expect(find.text('Attempt 1 of 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

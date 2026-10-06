import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';
import 'package:spawnalpha/src/ui/word_review_panel.dart';

import '../transcription/word_correction_test.dart' show wording;

void main() {
  for (final language in ScriptLanguage.values) {
    testWidgets('word dialog validates, saves and restores $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (wrong, right, next) = wording(language);
      var transcript = WordTranscript(
        language: language,
        duration: const Duration(seconds: 3),
        words: [
          SpokenWord(
            text: wrong,
            start: Duration.zero,
            end: const Duration(seconds: 1),
            confidence: .3,
          ),
        ],
      );
      final edits = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SingleChildScrollView(
                child: WordReviewPanel(
                  transcript: transcript,
                  busy: false,
                  onCorrect: (index, text) async {
                    edits.add(text);
                    update(() => transcript = transcript.withWord(index, text));
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review wording'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check wording'), findsOneWidget);
      expect(find.textContaining('0:00.0 – 0:01.0'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit word 1'));
      await tester.pumpAndSettle();
      final direction = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(
        direction.textDirection,
        language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      );
      await tester.enterText(find.byType(TextField), '$right $next');
      await tester.tap(find.text('Save word'));
      await tester.pump();
      expect(find.textContaining('Enter one word'), findsOneWidget);
      expect(edits, isEmpty);
      await tester.enterText(find.byType(TextField), right);
      await tester.tap(find.text('Save word'));
      await tester.pumpAndSettle();
      expect(edits, [right]);
      expect(find.textContaining('Corrected'), findsOneWidget);
      expect(find.textContaining('Check wording'), findsOneWidget);
      await tester.tap(find.byTooltip('Restore word 1'));
      await tester.pumpAndSettle();
      expect(edits, [right, wrong]);
      expect(find.text(wrong), findsOneWidget);
      expect(find.byTooltip('Restore word 1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('word pages stay bounded and saving disables edit controls', (
    tester,
  ) async {
    final transcript = WordTranscript(
      language: ScriptLanguage.en,
      duration: const Duration(seconds: 50),
      words: [
        for (var i = 0; i < 45; i++)
          SpokenWord(
            text: 'Word$i',
            start: Duration(seconds: i),
            end: Duration(seconds: i + 1),
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WordReviewPanel(
              transcript: transcript,
              busy: true,
              onCorrect: (_, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review wording'));
    await tester.pumpAndSettle();
    expect(find.text('Word0'), findsOneWidget);
    expect(find.text('Word20'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byTooltip('Edit word 1'),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.text('Next words'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next words'));
    await tester.pumpAndSettle();
    expect(find.text('Word0'), findsNothing);
    expect(find.text('Word20'), findsOneWidget);
    expect(find.text('Word40'), findsNothing);
    await tester.tap(find.text('Next words'));
    await tester.pumpAndSettle();
    expect(find.text('Word40'), findsOneWidget);
    expect(find.text('Word44'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

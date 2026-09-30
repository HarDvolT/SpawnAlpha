import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/prompter/prompter_controller.dart';
import 'package:spawnalpha/src/prompter/prompter_view.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';

AppServices services() => AppServices(
      library: ScriptLibrary(MemoryScriptStore()),
      settings: Settings(secrets: MemorySecretStore()),
      recordingsDir: Directory.systemTemp,
    );

void main() {
  testWidgets('adds the sample scripts, marks one up and accepts the marks', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = services();
    await tester.pumpWidget(SpawnAlphaApp(services: app));

    await tester.tap(find.textContaining('Add sample scripts'));
    await tester.pumpAndSettle();
    expect(app.library.scripts, hasLength(3));
    expect(find.text('Sample: quarterly update'), findsOneWidget);

    await tester.tap(find.text('Sample: quarterly update'));
    await tester.pumpAndSettle();
    expect(find.text('Mark up with on-device coach'), findsOneWidget);

    await tester.tap(find.text('Mark up with on-device coach'));
    await tester.pumpAndSettle();
    expect(find.text('Accept all'), findsOneWidget);

    await tester.tap(find.text('Accept all'));
    // Let the debounced autosave run.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final saved = app.library.scripts.firstWhere((s) => s.title == 'Sample: quarterly update');
    expect(saved.marks, isNotEmpty);
    expect(saved.pendingCount, 0);
  });

  testWidgets('a new script picks its language from what is typed', (tester) async {
    final app = services();
    await tester.pumpWidget(SpawnAlphaApp(services: app));
    await tester.tap(find.text('New script'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Write or paste your script. Blank lines separate paragraphs.'),
        'مرحباً بكم في هذا الفيديو القصير عن التصوير.');
    await tester.pump(const Duration(seconds: 1));
    expect(app.library.scripts.single.language, ScriptLanguage.ar);
  });

  group('PrompterView', () {
    ScriptDocument script(ScriptLanguage language, String text) => ScriptDocument.create(
          text: text,
          language: language,
          style: CoachingStyle.presentation,
        ).copyWith(marks: [
          const Mark.gap(id: 'p', kind: MarkKind.pauseLong, after: 1),
          const Mark(id: 's', kind: MarkKind.stress, start: 0, end: 0),
        ]);

    Future<ScrollPosition> pumpPrompter(WidgetTester tester, PrompterController c) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(width: 400, height: 600, child: PrompterView(controller: c, fontSize: 32)),
      ));
      await tester.pump();
      return tester.state<ScrollableState>(find.byType(Scrollable)).position;
    }

    testWidgets('scrolls while playing and holds at a long pause', (tester) async {
      final words = List.generate(80, (i) => 'word$i').join(' ');
      final c = PrompterController(script(ScriptLanguage.en, 'Hello there, $words.'));
      final position = await pumpPrompter(tester, c);
      expect(position.pixels, 0);

      c.play();
      // The ticker's first frame starts its clock.
      await tester.pump();
      // Into the long pause after the second word.
      await tester.pump(c.timeline.endOf(1) + const Duration(milliseconds: 100));
      expect(c.holding, MarkKind.pauseLong);
      final atPause = position.pixels;
      await tester.pump(const Duration(milliseconds: 500));
      expect(position.pixels, atPause);
      expect(find.text('LONG PAUSE'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      expect(position.pixels, greaterThan(atPause + 40));
      c.pause();
    });

    testWidgets('lays out Arabic right to left', (tester) async {
      final c = PrompterController(script(ScriptLanguage.ar, 'مرحبا بكم في هذا الفيديو'));
      await pumpPrompter(tester, c);
      final text = tester.widget<RichText>(find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('مرحبا'),
      ));
      expect(text.textDirection, TextDirection.rtl);
    });

    testWidgets('manual scroll moves the reader', (tester) async {
      final words = List.generate(120, (i) => 'word$i').join(' ');
      final c = PrompterController(script(ScriptLanguage.en, words), mode: ScrollMode.manual);
      await pumpPrompter(tester, c);
      await tester.drag(find.byType(PrompterView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(c.currentToken, greaterThan(10));
    });
  });
}

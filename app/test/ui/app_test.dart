import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/mark_editing.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/prompter/guide.dart';
import 'package:spawnalpha/src/prompter/marked_text.dart';
import 'package:spawnalpha/src/prompter/prompter_controller.dart';
import 'package:spawnalpha/src/prompter/prompter_view.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/ui/prompter_screen.dart';

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
    // On the Home screen: in the Record next hero, and as a page.
    expect(find.text('Sample: quarterly update'), findsWidgets);

    await tester.tap(find.text('Sample: quarterly update').last);
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

    testWidgets('kinetic and still text lay out the same, so switching never reflows', (tester) async {
      final words = List.generate(40, (i) => 'word$i').join(' ');
      final c = PrompterController(script(ScriptLanguage.en, 'Hello there, $words.'));
      Future<List<Rect>> boxes(bool kinetic) async {
        await tester.pumpWidget(MaterialApp(
          home: SizedBox(width: 400, height: 600, child: PrompterView(controller: c, fontSize: 32, kinetic: kinetic)),
        ));
        await tester.pump();
        final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText).first);
        final text = paragraph.text.toPlainText();
        final probes = ['Hello', 'there', 'word7', 'word39'];
        return [
          for (final w in probes)
            paragraph
                .getBoxesForSelection(TextSelection(baseOffset: text.indexOf(w), extentOffset: text.indexOf(w) + w.length))
                .first
                .toRect(),
        ];
      }

      final kinetic = await boxes(true);
      final still = await boxes(false);
      expect(kinetic, still);
    });

    testWidgets('kinetic leaves stressed words to the overlay, still draws them in amber', (tester) async {
      final c = PrompterController(script(ScriptLanguage.en, 'Hello there, friends.'));
      Color? stressColor(bool kinetic) {
        final marked = MarkedText.build(
          tokens: c.tokens,
          marks: c.marks,
          style: const TextStyle(fontSize: 32),
          colors: CueColors.stage,
          stressStyle: kinetic ? StressStyle.stageOverlay : StressStyle.stage,
        );
        Color? found;
        marked.span.visitChildren((span) {
          if (span is TextSpan && span.text == 'Hello') found = span.style?.color;
          return found == null;
        });
        return found;
      }

      expect(stressColor(false), CueColors.stage.stress);
      expect(stressColor(true)!.a, 0);
    });

    testWidgets('kinetic also leaves energy and pace-run words to the overlay, so they can move', (tester) async {
      final doc = ScriptDocument.create(
        text: 'Go now, then slowly after.',
        language: ScriptLanguage.en,
        style: CoachingStyle.presentation,
      ).copyWith(marks: [
        const Mark(id: 'e', kind: MarkKind.energy, start: 0, end: 1),
        const Mark(id: 's', kind: MarkKind.slower, start: 3, end: 4),
      ]);
      Color? colorOf(String word, StressStyle style) {
        final marked = MarkedText.build(
          tokens: doc.tokens,
          marks: doc.marks,
          style: const TextStyle(fontSize: 32),
          colors: CueColors.stage,
          stressStyle: style,
        );
        Color? found;
        marked.span.visitChildren((span) {
          if (span is TextSpan && span.text == word) found = span.style?.color;
          return found == null;
        });
        return found;
      }

      expect(colorOf('Go', StressStyle.stage), CueColors.stage.energy);
      expect(colorOf('Go', StressStyle.stageOverlay)!.a, 0);
      expect(colorOf('slowly', StressStyle.stageOverlay)!.a, 0);
      expect(colorOf('then', StressStyle.stageOverlay), isNull, reason: 'plain words stay in the paragraph');
    });

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

    testWidgets('every guide and motion paints while playing, without moving a word', (tester) async {
      final words = List.generate(40, (i) => 'word$i').join(' ');
      final c = PrompterController(script(ScriptLanguage.en, 'Hello there, $words.').acceptAllMarks());
      for (final motion in PrompterMotion.values) {
        Rect? first;
        for (final guide in PrompterGuide.values) {
          c.restart();
          await tester.pumpWidget(MaterialApp(
            home: SizedBox(
              width: 400,
              height: 600,
              child: PrompterView(controller: c, fontSize: 32, guide: guide, motion: motion),
            ),
          ));
          await tester.pump();
          c.play();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 900));
          expect(tester.takeException(), isNull, reason: '$guide, $motion');
          final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText).first);
          final text = paragraph.text.toPlainText();
          final box = paragraph
              .getBoxesForSelection(TextSelection(baseOffset: text.indexOf('word7'), extentOffset: text.indexOf('word7') + 5))
              .first
              .toRect();
          first ??= box;
          expect(box, first, reason: 'the guide never reflows the text ($guide, $motion)');
          if (motion == PrompterMotion.phrase) {
            // One phrase: a larger size, and the phrase starts its own block.
            final hello = paragraph
                .getBoxesForSelection(TextSelection(baseOffset: text.indexOf('Hello'), extentOffset: text.indexOf('Hello') + 5))
                .first;
            expect(hello.bottom - hello.top, greaterThan(32 * 1.2));
          }
          c.pause();
        }
      }
    });

    testWidgets('the control bar and the G key choose the guide', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = services();
      final doc = script(ScriptLanguage.en, 'Hello there, friends.');
      await tester.pumpWidget(AppScope(services: app, child: MaterialApp(home: PrompterScreen(script: doc))));
      await tester.pumpAndSettle();
      expect(app.settings.guide, PrompterGuide.dot);

      await tester.tap(find.text('Spotlight'));
      await tester.pumpAndSettle();
      expect(app.settings.guide, PrompterGuide.spotlight);
      expect(tester.widget<PrompterView>(find.byType(PrompterView)).guide, PrompterGuide.spotlight);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pumpAndSettle();
      expect(app.settings.guide, PrompterGuide.off);

      await tester.tap(find.text('Smooth'));
      await tester.pumpAndSettle();
      expect(tester.widget<PrompterView>(find.byType(PrompterView)).motion, PrompterMotion.smooth);
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

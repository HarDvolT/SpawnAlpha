import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/prompter/prompter_view.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/notes_editor_screen.dart';
import 'package:spawnalpha/src/ui/notes_stage.dart';
import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';
import '../model/note_deck_test.dart' show fixtureNotes;

void main() {
  for (final language in ScriptLanguage.values) {
    testWidgets('card buttons and keyboard boundaries $language', (tester) async {
      final c = NoteController(fixtureNotes(language));
      final changes = <int>[];
      await tester.pumpWidget(MaterialApp(home: NotesStage(controller: c, language: language, onChanged: changes.add)));
      expect(find.text('Card 1 of 2'), findsOneWidget);
      final text = find.text(c.card!.title);
      expect(Directionality.of(tester.element(text)), language.isRtl ? TextDirection.rtl : TextDirection.ltr);
      await tester.tap(find.byTooltip('Previous card · Ctrl+Shift+Left'));
      expect(changes, isEmpty);
      await tester.tap(find.byTooltip('Next card · Ctrl+Shift+Right'));
      await tester.pumpAndSettle();
      expect(find.text('Card 2 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Next card · Ctrl+Shift+Right'));
      expect(changes, [1]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(c.index, 0);
      expect(changes, [1, 0]);
    });
    testWidgets('edit, reorder, remove, save and preserve script $language', (tester) async {
      final library = ScriptLibrary(MemoryScriptStore());
      final document = ScriptDocument.create(text: 'Keep this script', language: language)
          .copyWith(recordingAid: RecordingAid.notes, notes: fixtureNotes(language));
      await library.save(document);
      final app = AppServices(library: library, settings: Settings(secrets: MemorySecretStore()), recordingsDir: Directory.systemTemp);
      await tester.pumpWidget(AppScope(services: app, child: MaterialApp(theme: buildTheme(Brightness.light), home: NotesEditorScreen(script: document))));
      await tester.enterText(find.widgetWithText(TextFormField, 'Talking points'), '${document.notes.cards.first.body}\nExtra');
      await tester.pumpAndSettle();
      expect(library.byId(document.id)!.notes.cards.first.body, endsWith('Extra'));
      await tester.tap(find.byTooltip('Move card later'));
      await tester.pumpAndSettle();
      expect(library.byId(document.id)!.notes.cards.last.id, 'opening');
      await tester.tap(find.byTooltip('Remove card'));
      await tester.pumpAndSettle();
      expect(library.byId(document.id)!.notes.cards, hasLength(1));
      expect(library.byId(document.id)!.text, 'Keep this script');
      await tester.tap(find.text('Add card'));
      await tester.pumpAndSettle();
      expect(library.byId(document.id)!.notes.cards, hasLength(2));
      expect(library.byId(document.id)!.stageReady, isFalse);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    });
    testWidgets('protected reader resets on take start and browses while paused $language', (tester) async {
      tester.view.physicalSize = const Size(640, 280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sent = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(floatingViewChannel, (call) async { sent.add(call); return null; });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(floatingViewChannel, null));
      final doc = ScriptDocument.create(language: language).copyWith(recordingAid: RecordingAid.notes, notes: fixtureNotes(language));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: FloatingPrompterScreen(presentation: FloatingPresentation(script: doc))));
      expect(find.byType(PrompterView), findsNothing);
      expect(find.byTooltip('Play'), findsNothing);
      Future<void> send(String method, Object value) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(floatingViewChannel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)), (_) {});
        await tester.pumpAndSettle();
      }
      await send('command', 'next');
      expect(find.text('Card 2 of 2'), findsOneWidget);
      await send('recordingState', {'active': true, 'paused': false});
      expect(find.text('Card 1 of 2'), findsOneWidget);
      await send('recordingState', {'active': true, 'paused': true});
      await send('command', 'next');
      await send('command', 'next');
      expect(find.text('Card 2 of 2'), findsOneWidget);
      expect(sent.where((c) => c.method == 'card').last.arguments, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('large Arabic cards keep navigation accessible and reduced motion is immediate', (tester) async {
    tester.view.physicalSize = const Size(440, 256);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = NoteController(NoteDeck([NoteCard(id: 'a', body: List.filled(40, 'هذه نقطة طويلة للتحدث عنها').join('\n')), NoteCard(id: 'b', title: 'النهاية')]));
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(disableAnimations: true, textScaler: TextScaler.linear(2)), child: NotesStage(controller: c, language: ScriptLanguage.ar))));
    await tester.tap(find.byTooltip('Next card · Ctrl+Shift+Right'));
    await tester.pump();
    expect(find.text('النهاية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

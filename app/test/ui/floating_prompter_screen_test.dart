import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/prompter/prompter_controller.dart';
import 'package:spawnalpha/src/prompter/prompter_view.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';

void main() {
  for (final language in ScriptLanguage.values) {
    testWidgets('floating prompter reads $language with controls and correct direction', (tester) async {
      tester.view.physicalSize = Size(SaPrompter.floatingMinWidth, SaPrompter.floatingMinHeight);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(floatingViewChannel, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(floatingViewChannel, null));
      final script = ScriptDocument.create(language: language, text: switch (language) {
        ScriptLanguage.en => 'Hello. Keep a clear voice.',
        ScriptLanguage.fr => 'Bonjour. Gardez une voix claire.',
        ScriptLanguage.ar => 'مرحبا. حافظ على صوت واضح.',
      });
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
        home: FloatingPrompterScreen(presentation: FloatingPresentation(script: script))));
      await tester.pump();
      final view = tester.widget<PrompterView>(find.byType(PrompterView));
      expect(view.controller.script.language, language);
      expect(find.ancestor(of: find.byType(PrompterView), matching: find.byWidgetPredicate(
        (widget) => widget is Directionality && widget.textDirection == (language.isRtl ? TextDirection.rtl : TextDirection.ltr))), findsWidgets);
      expect(find.text('Hidden from recording'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(view.controller.isPlaying, isTrue);
      expect(view.controller.position, greaterThan(Duration.zero));
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(view.controller.state, PlaybackState.paused);
      await tester.tap(find.byTooltip('Restart'));
      await tester.pump();
      expect(view.controller.position, Duration.zero);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('lock is only shown as active after native confirmation', (tester) async {
    bool allow = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(floatingViewChannel, (call) async {
      if (call.method == 'lock') {
        if (!allow) throw PlatformException(code: 'used', message: 'private native detail');
        return call.arguments;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(floatingViewChannel, null));
    await tester.pumpWidget(MaterialApp(home: FloatingPrompterScreen(presentation:
      FloatingPresentation(script: ScriptDocument.create(text: 'A test phrase.')))));
    await tester.pump();
    await tester.tap(find.byTooltip('Lock · Ctrl+Shift+L unlocks'));
    await tester.pump();
    expect(find.text('A shortcut is in use. Lock stays off.'), findsOneWidget);
    expect(find.text('Ctrl+Shift+L to unlock'), findsNothing);
    allow = true;
    await tester.tap(find.byTooltip('Lock · Ctrl+Shift+L unlocks'));
    await tester.pump();
    expect(find.text('Ctrl+Shift+L to unlock'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

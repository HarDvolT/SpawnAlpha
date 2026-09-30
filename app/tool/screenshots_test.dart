// Renders the main screens to PNG files with real fonts, so the UI can be
// checked visually without a device (for example in a cloud container).
// It is not part of the test suite. Run it from app/ with:
//
//   flutter test tool/screenshots_test.dart --update-goldens
//
// Images land in app/tool/screenshots/ (git-ignored). Latin and Arabic text
// uses DejaVu Sans from /usr/share/fonts, or from SCREENSHOT_FONT_DIR.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/markup/local_markup_engine.dart';
import 'package:spawnalpha/src/markup/markup_engine.dart';
import 'package:spawnalpha/src/markup/providers.dart';
import 'package:spawnalpha/src/model/mark_editing.dart';
import 'package:spawnalpha/src/model/samples.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/prompter/prompter_view.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/ui/editor_screen.dart';
import 'package:spawnalpha/src/ui/library_screen.dart';
import 'package:spawnalpha/src/ui/settings_screen.dart';
import 'package:spawnalpha/src/ui/prompter_screen.dart';

Future<void> _loadFonts() async {
  final fontDir = Platform.environment['SCREENSHOT_FONT_DIR'] ?? '/usr/share/fonts/truetype/dejavu';
  final flutterRoot = Platform.resolvedExecutable.split('${Platform.pathSeparator}bin${Platform.pathSeparator}cache').first;
  Future<ByteData> bytes(String path) async => ByteData.sublistView(await File(path).readAsBytes());

  final text = FontLoader('Roboto')
    ..addFont(bytes('$fontDir/DejaVuSans.ttf'))
    ..addFont(bytes('$fontDir/DejaVuSans-Bold.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'));
  await Future.wait([text.load(), icons.load()]);
}

Future<ScriptDocument> _markedUp(ScriptDocument s, {bool accept = true}) async {
  final result = await const LocalMarkupEngine().markup(s);
  final marked = applyMarkup(s, result);
  return accept ? marked.acceptAllMarks() : marked;
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    // The prompter keeps the screen awake; there is no device here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  Future<AppServices> services(List<ScriptDocument> scripts) async {
    final library = ScriptLibrary(MemoryScriptStore());
    for (final s in scripts.reversed) {
      await library.save(s);
    }
    return AppServices(
      library: library,
      settings: Settings(secrets: MemorySecretStore()),
      recordingsDir: Directory.systemTemp,
    );
  }

  Future<void> shoot(WidgetTester tester, String name, Size size, Widget Function(AppServices) screen,
      List<ScriptDocument> scripts,
      {Future<void> Function(WidgetTester)? before}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await services(scripts);
    await tester.pumpWidget(AppScope(
      services: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6D4AFF))),
        home: screen(app),
      ),
    ));
    await tester.pumpAndSettle();
    if (before != null) await before(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
  }

  const phone = Size(430, 900);
  const desktop = Size(1280, 800);

  testWidgets('library', (tester) async {
    await shoot(tester, 'library', phone, (_) => const LibraryScreen(), sampleScripts());
  });

  for (final provider in [MarkupProvider.ollama, MarkupProvider.gemini]) {
    testWidgets('settings ${provider.name}', (tester) async {
      await shoot(tester, 'settings-${provider.name}', phone, (app) {
        app.settings.provider = provider;
        return const SettingsScreen();
      }, []);
    });
  }

  for (final (i, name) in ['en-presentation', 'fr-tutorial', 'ar-social'].indexed) {
    testWidgets('editor $name, marks pending', (tester) async {
      final script = await _markedUp(sampleScripts()[i], accept: false);
      await shoot(tester, 'editor-$name', desktop, (_) => EditorScreen(script: script), [script]);
    });

    testWidgets('editor $name on a phone', (tester) async {
      final script = await _markedUp(sampleScripts()[i]);
      await shoot(tester, 'editor-$name-phone', phone, (_) => EditorScreen(script: script), [script]);
    });

    testWidgets('prompter $name', (tester) async {
      final script = await _markedUp(sampleScripts()[i]);
      await shoot(tester, 'prompter-$name', phone, (_) => PrompterScreen(script: script), [script],
          before: (tester) async {
        // Play into the script so the scroll and a pause show.
        final controller = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
        controller.seekToToken(9);
        await tester.pumpAndSettle();
      });
    });
  }
}

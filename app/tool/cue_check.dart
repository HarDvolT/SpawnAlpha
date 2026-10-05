// Development-only launch target for the owner's cue and motion checks.
// Scripts, settings and secrets stay in memory. Any take made from the Home
// screen is saved under this project's build folder instead of Documents.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/home_screen.dart';
import 'package:spawnalpha/src/ui/prompter_screen.dart';

import 'fixtures/cue_check_scripts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = ScriptLibrary(MemoryScriptStore());
  await library.load();
  for (final language in ScriptLanguage.values.reversed) {
    await library.save(cueCheckScript(language));
  }
  final settings = Settings(secrets: MemorySecretStore())..kinetic = false;
  final services = AppServices(
    library: library,
    settings: settings,
    recordingsDir: Directory(
      '${Directory.current.path}${Platform.pathSeparator}build'
      '${Platform.pathSeparator}cue-check${Platform.pathSeparator}recordings',
    ),
  );
  runApp(
    AppScope(
      services: services,
      child: MaterialApp(
        title: 'SpawnAlpha',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        initialRoute: '/practice',
        routes: {
          '/': (_) => const HomeScreen(),
          '/practice': (_) =>
              PrompterScreen(script: library.byId('cue-check-en')!),
        },
      ),
    ),
  );
}

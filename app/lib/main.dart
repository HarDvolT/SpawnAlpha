import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/storage/script_store.dart';
import 'src/storage/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final root = Directory('${documents.path}${Platform.pathSeparator}SpawnAlpha');
  String under(String name) => '${root.path}${Platform.pathSeparator}$name';

  final library = ScriptLibrary(FileScriptStore(Directory(under('scripts'))));
  final settings = Settings(file: File(under('settings.json')));
  await Future.wait([library.load(), settings.load()]);

  runApp(SpawnAlphaApp(
    services: AppServices(
      library: library,
      settings: settings,
      recordingsDir: Directory(under('recordings')),
    ),
  ));
}

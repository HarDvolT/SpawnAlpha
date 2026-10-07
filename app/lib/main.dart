import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/storage/script_store.dart';
import 'src/storage/settings.dart';
import 'src/ui/floating_prompter_screen.dart';
import 'src/ui/recording_hud_screen.dart';
import 'src/ui/camera_bubble_screen.dart';

@pragma('vm:entry-point')
Future<void> floatingPrompterMain() => runFloatingPrompter();

@pragma('vm:entry-point')
Future<void> recordingHudMain() => runRecordingHud();

@pragma('vm:entry-point')
Future<void> cameraBubbleMain() => runCameraBubble();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final dataOverride = Platform.environment['SPAWNALPHA_DATA_DIR'];
  final documents = dataOverride == null
      ? await getApplicationDocumentsDirectory()
      : null;
  final root = Directory(
    dataOverride ?? '${documents!.path}${Platform.pathSeparator}SpawnAlpha',
  );
  String under(String name) => '${root.path}${Platform.pathSeparator}$name';

  final library = ScriptLibrary(FileScriptStore(Directory(under('scripts'))));
  final settings = Settings(file: File(under('settings.json')));
  await Future.wait([library.load(), settings.load()]);

  final services = AppServices(
    library: library,
    settings: settings,
    recordingsDir: Directory(under('recordings')),
  );
  runApp(SpawnAlphaApp(services: services));
  if (services.renderer.supported) {
    unawaited(services.videoExports.recover().catchError((Object _) => 0));
  }
  if (services.recorder.supported) {
    // Recover in the background. The store serializes recovery with new takes.
    unawaited(services.screenTakes.recover().catchError((Object error) => 0));
  }
}

/// The bundled fonts are under the SIL Open Font License, which asks for
/// the licence to travel with them; it shows in the app's licence page.
void _registerFontLicenses() {
  const fonts = {
    'Anybody': 'anybody',
    'Aref Ruqaa': 'arefruqaa',
    'Caveat': 'caveat',
    'Martian Mono': 'martianmono',
    'Readex Pro': 'readexpro',
    'Reem Kufi': 'reemkufi',
  };
  LicenseRegistry.addLicense(() async* {
    for (final name in ['whisper-cpp', 'whisper-model', 'speexdsp']) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/licenses/$name.txt'));
    }
    for (final MapEntry(key: family, value: file) in fonts.entries) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/OFL-$file.txt'));
    }
  });
}

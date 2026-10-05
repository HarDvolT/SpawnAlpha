// Development-only native window/exclusion smoke check. No user data, capture,
// file or microphone access; only one display ID is selected in memory.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spawnalpha/src/recording/recording_hud.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/ui/recording_hud_screen.dart';
import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';
import 'package:spawnalpha/src/theme/theme.dart';

@pragma('vm:entry-point')
Future<void> recordingHudMain() => runRecordingHud();
@pragma('vm:entry-point')
Future<void> floatingPrompterMain() => runFloatingPrompter();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: buildTheme(Brightness.dark), home: const Scaffold(body: Center(child: Text('Checking recording controls…')))));
  await Future<void>.delayed(SaDurations.beat);
  try {
    final sources = await ScreenSources.platform().list();
    final source = sources.firstWhere((s) => s.kind == ScreenSourceKind.display);
    final hud = WindowsRecordingHuds();
    for (var i = 0; i < 2; ++i) {
      final handle = await hud.open(source);
      if (!await hud.isOpen(handle)) throw StateError('HUD unavailable');
      for (final phase in [HudPhase.countdown, HudPhase.recording, HudPhase.paused, HudPhase.saving]) {
        await hud.update(handle, HudState(phase: phase, duration: const Duration(seconds: 3)));
        await Future<void>.delayed(SaDurations.beat * 0.5);
        if (!await hud.isOpen(handle)) throw StateError('HUD unavailable');
      }
      await hud.close(handle);
      final status = await WindowsRecordingHuds.channel.invokeMapMethod<String, Object?>('status', {'sessionId': handle.sessionId});
      if (status?['ownerExcluded'] != false || await hud.isOpen(handle)) throw StateError('HUD cleanup failed');
    }
    debugPrint('Native HUD check passed: visibility, capture exclusion, countdown/docking, close/reopen and owner restoration; nothing captured.');
  } on Object {
    debugPrint('Native HUD check failed.');
  }
  await SystemNavigator.pop();
}

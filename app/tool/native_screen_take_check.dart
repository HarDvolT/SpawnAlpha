// End-to-end check: only the generated fixture window, silent video, an in-memory
// script/library, and ignored test files. No private desktop, camera or mic.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/recording/recording_hud.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/recording/screen_take_controller.dart';
import 'package:spawnalpha/src/storage/screen_take_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';
import 'package:spawnalpha/src/ui/recording_hud_screen.dart';

@pragma('vm:entry-point')
Future<void> floatingPrompterMain() => runFloatingPrompter();
@pragma('vm:entry-point')
Future<void> recordingHudMain() => runRecordingHud();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: buildTheme(Brightness.dark), home: const Scaffold(body: Center(child: Text('Checking screen take…')))));
  Process? fixture;
  ScreenTakeController? owner;
  Timer? action;
  try {
    final root = Directory.current.path;
    fixture = await Process.start('$root/build/windows/x64/runner/Debug/recording_fixture_window.exe', []);
    ScreenSource? source;
    for (var i = 0; i < 20 && source == null; ++i) {
      await Future<void>.delayed(SaDurations.previewPoll);
      final sources = await ScreenSources.platform().list();
      source = sources.where((s) => s.kind == ScreenSourceKind.window && s.name == 'SpawnAlpha generated recording fixture').firstOrNull;
    }
    if (source == null) throw StateError('Fixture unavailable');
    final script = ScriptDocument.create(text: 'A generated fixture. Read one line. Keep recording after the last word.');
    final library = ScriptLibrary(MemoryScriptStore());
    await library.save(script);
    final directory = Directory('$root/build/screen-ui-fixtures/${DateTime.now().microsecondsSinceEpoch}');
    final store = ScreenTakeStore(directory, library, const WindowsRecordingInspector());
    owner = ScreenTakeController(recorder: const WindowsScreenRecordings(), huds: WindowsRecordingHuds(), floating: const WindowsFloatingPrompters(), store: store);
    final controller = owner;
    var step = 0;
    controller.addListener(() {
      if (controller.phase == ScreenTakePhase.recording && step == 0) {
        step = 1;
        action = Timer(SaDurations.beat, () => unawaited(controller.togglePause()));
      } else if (controller.phase == ScreenTakePhase.paused && step == 1) {
        step = 2;
        action = Timer(SaDurations.beat, () async {
          await controller.togglePrompter();
          if (controller.readerVisible) throw StateError('Hide failed');
          await controller.togglePrompter();
          if (!controller.readerVisible) throw StateError('Show failed');
          await controller.lockPrompter(); await controller.lockPrompter();
          await controller.togglePause();
        });
      } else if (controller.phase == ScreenTakePhase.recording && step == 2) {
        step = 3;
        action = Timer(SaDurations.beat, controller.stop);
      }
    });
    await controller.start(presentation: FloatingPresentation(script: script), source: source, recordAudio: false);
    action?.cancel();
    final take = controller.take;
    if (take == null || controller.problem != null || controller.busy || step != 3 ||
      take.duration < SaDurations.beat * 1.5 || take.duration > SaDurations.beat * 3.5 || library.scripts.single.takes.length != 1) {
      throw StateError('Take failed');
    }
    final hud = await WindowsRecordingHuds.channel.invokeMapMethod<String, Object?>('status', {'sessionId': 1});
    final reader = await WindowsFloatingPrompters.channel.invokeMapMethod<String, Object?>('status', {'sessionId': 1});
    if (hud?['ownerExcluded'] != false || reader?['visible'] != false) throw StateError('Cleanup failed');
    if (await store.recover() != 0 || library.scripts.single.takes.length != 1) throw StateError('Save retry failed');
    debugPrint('Native screen take check passed: protected countdown/reader/HUD, silent video, pause/resume, hide/show, one durable take, clean shutdown.');
    library.dispose();
  } on Object {
    debugPrint('Native screen take check failed.');
  } finally {
    action?.cancel(); owner?.dispose(); fixture?.kill();
  }
  await SystemNavigator.pop();
}

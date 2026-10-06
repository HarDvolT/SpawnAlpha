// End-to-end check: only the generated fixture window, silent video, an in-memory
// script/library, and ignored test files. No private desktop, camera or mic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/recording/recording_hud.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/recording/activity_trace.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/recording/screen_take_controller.dart';
import 'package:spawnalpha/src/storage/screen_take_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';
import 'package:spawnalpha/src/ui/recording_hud_screen.dart';
import 'package:spawnalpha/src/recording/camera_bubble.dart';
import 'package:spawnalpha/src/ui/camera_bubble_screen.dart';

@pragma('vm:entry-point')
Future<void> floatingPrompterMain() => runFloatingPrompter();
@pragma('vm:entry-point')
Future<void> recordingHudMain() => runRecordingHud();
@pragma('vm:entry-point')
Future<void> cameraBubbleMain() => runCameraBubble();
Future<void> main() => runGeneratedTake();
Future<void> runGeneratedTake({
  String? cameraFixture,
  bool generatedSystemAudio = false,
  bool generatedActivity = false,
  bool crashAfterRecord = false,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(body: Center(child: Text('Checking screen take…'))),
    ),
  );
  Process? fixture;
  ScreenTakeController? owner;
  Timer? action;
  try {
    if (crashAfterRecord && !generatedActivity) {
      throw StateError('Crash check requires generated activity');
    }
    if (generatedActivity &&
        await WindowsScreenRecordings.channel.invokeMethod<bool>(
              'activityFixture',
              const {},
            ) !=
            true) {
      throw StateError(
        'Generated activity requires the non-shipping fixture binary',
      );
    }
    if (generatedSystemAudio &&
        await WindowsScreenRecordings.channel.invokeMethod<bool>(
              'audioFixture',
              const {},
            ) !=
            true) {
      throw StateError(
        'Generated audio requires the non-shipping fixture binary',
      );
    }
    final root = Directory.current.path;
    fixture = await Process.start(
      '$root/build/windows/x64/runner/Debug/recording_fixture_window.exe',
      [],
    );
    ScreenSource? source;
    for (var i = 0; i < 20 && source == null; ++i) {
      await Future<void>.delayed(SaDurations.previewPoll);
      final sources = await ScreenSources.platform().list();
      source = sources
          .where(
            (s) =>
                s.kind == ScreenSourceKind.window &&
                s.name == 'SpawnAlpha generated recording fixture',
          )
          .firstOrNull;
    }
    if (source == null) throw StateError('Fixture unavailable');
    final script = ScriptDocument.create(
      text: 'A generated fixture. Read one line. Keep recording after the last word.',
    );
    final library = ScriptLibrary(MemoryScriptStore());
    await library.save(script);
    final directory = Directory(
      '$root/build/screen-ui-fixtures/${DateTime.now().microsecondsSinceEpoch}',
    );
    final store = ScreenTakeStore(
      directory,
      library,
      const WindowsRecordingInspector(),
    );
    owner = ScreenTakeController(
      recorder: const WindowsScreenRecordings(),
      huds: WindowsRecordingHuds(),
      floating: const WindowsFloatingPrompters(),
      store: store,
      bubbles: const WindowsCameraBubbles(),
    );
    final controller = owner;
    var step = 0;
    ScreenTakePhase? previousPhase;
    controller.addListener(() {
      if (cameraFixture != null && controller.phase != previousPhase) {
        previousPhase = controller.phase;
        debugPrint('Generated paired check: ${controller.phase.name}');
      }
      if (controller.phase == ScreenTakePhase.recording && step == 0) {
        step = 1;
        if (crashAfterRecord) {
          action = Timer(SaDurations.beat * 5, () => exit(42));
          return;
        }
        action = Timer(
          SaDurations.beat,
          () => unawaited(controller.togglePause()),
        );
      } else if (controller.phase == ScreenTakePhase.paused && step == 1) {
        step = 2;
        action = Timer(SaDurations.beat, () async {
          await controller.toggleCompanion();
          if (cameraFixture != null) {
            if (!controller.companionQuestion) {
              throw StateError('Camera choice missing');
            }
            await controller.chooseCompanion(false);
          }
          if (!controller.companion) throw StateError('Companion missing');
          Future<Map<String, Object?>?> placementStatus() =>
              WindowsFloatingPrompters.channel.invokeMapMethod<String, Object?>(
                'status',
                {'sessionId': 1},
              );
          var placement = await placementStatus();
          if (placement?['excluded'] != true ||
              placement?['visible'] != true ||
              placement?['companion'] != true ||
              (cameraFixture != null && placement?['sampling'] != false)) {
            throw StateError('Companion protection or camera docking failed');
          }
          if (cameraFixture != null) {
            await controller.askCompanion();
            await controller.chooseCompanion(true);
          }
          placement = await placementStatus();
          if (placement?['following'] == true &&
              (placement?['clickThrough'] != true ||
                  placement?['sampling'] != true)) {
            debugPrint(
              'Generated companion flags: visible=${placement?['visible']}, excluded=${placement?['excluded']}, sampling=${placement?['sampling']}, clickThrough=${placement?['clickThrough']}',
            );
            throw StateError('Companion input safety failed');
          }
          await const WindowsFloatingPrompters().placement(
            const FloatingHandle(1),
            const CompanionPlacement(
              enabled: true,
              follow: true,
              reduceMotion: true,
            ),
          );
          placement = await placementStatus();
          if (placement?['sampling'] != false ||
              placement?['following'] != false) {
            throw StateError('Reduced motion did not dock');
          }
          await controller.toggleCompanion();
          await controller.toggleCompanion();
          await controller.togglePrompter();
          if (controller.readerVisible) throw StateError('Hide failed');
          if ((await placementStatus())?['sampling'] != false) {
            throw StateError('Hidden pointer sampling');
          }
          await controller.togglePrompter();
          if (!controller.readerVisible) throw StateError('Show failed');
          placement = await placementStatus();
          if (placement?['following'] == true &&
              (placement?['clickThrough'] != true ||
                  placement?['sampling'] != true)) {
            throw StateError('Following safety lost after showing');
          }
          await controller.toggleCompanion();
          if ((await placementStatus())?['sampling'] != false) {
            throw StateError('Pointer sampling retained');
          }
          await controller.lockPrompter();
          await controller.lockPrompter();
          await controller.togglePause();
        });
      } else if (controller.phase == ScreenTakePhase.recording && step == 2) {
        step = 3;
        action = Timer(SaDurations.beat, controller.stop);
      }
    });
    await controller.start(
      presentation: FloatingPresentation(script: script),
      source: source,
      recordAudio: false,
      recordSystemAudio: generatedSystemAudio,
      recordActivity: generatedActivity,
      cameraId: cameraFixture,
      cameraName: cameraFixture == null ? null : 'Generated camera',
    );
    action?.cancel();
    final take = controller.take;
    if (take == null ||
        controller.problem != null ||
        controller.busy ||
        step != 3 ||
        take.duration < SaDurations.beat * 1.5 ||
        take.duration > SaDurations.beat * 3.5 ||
        library.scripts.single.takes.length != 1) {
      throw StateError('Take failed');
    }
    final hud = await WindowsRecordingHuds.channel
        .invokeMapMethod<String, Object?>('status', {'sessionId': 1});
    final reader = await WindowsFloatingPrompters.channel
        .invokeMapMethod<String, Object?>('status', {'sessionId': 1});
    if (hud?['ownerExcluded'] != false || reader?['visible'] != false) {
      throw StateError('Cleanup failed');
    }
    if (await store.recover() != 0 ||
        library.scripts.single.takes.length != 1) {
      throw StateError('Save retry failed');
    }
    if (generatedSystemAudio) {
      final metadata =
          jsonDecode(await File(take.metadataPath!).readAsString()) as Map;
      final info = await const WindowsRecordingInspector().inspect(take.path);
      if (!info.hasAudio ||
          metadata['recordSystemAudio'] != true ||
          metadata['recordAudio'] != false ||
          controller.status!.systemAudioFrames <= 0 ||
          controller.status!.loudestRmsDb != -100 ||
          controller.status!.loudestSystemRmsDb <= -40) {
        throw StateError('Generated sound missing or leaking into Voice');
      }
    }
    if (generatedActivity) {
      final activity = await inspectActivity(File(take.activityPath!));
      if (!activity.complete ||
          activity.events < 80 ||
          activity.events != controller.status!.activityEvents ||
          activity.durationUs != controller.status!.duration.inMicroseconds ||
          activity.events > 200) {
        throw StateError('Activity pause clock or durable count mismatch');
      }
      debugPrint(
        'Native generated activity take check passed: timing only, pause removed, protected controls, durable trace and clean shutdown.',
      );
    }
    if (cameraFixture != null) {
      if (take.mode != TakeMode.both || take.cameraPath == null) {
        throw StateError('Pair missing');
      }
      final cameraInfo = await const WindowsRecordingInspector().inspect(
        take.cameraPath!,
      );
      if (!cameraInfo.readable ||
          cameraInfo.hasAudio ||
          (cameraInfo.duration - take.duration).abs() >
              SaDurations.recordingPoll) {
        throw StateError('Pair clock mismatch');
      }
      final bubble = await WindowsCameraBubbles.channel
          .invokeMapMethod<String, Object?>('status', {'sessionId': 1});
      if (bubble?['excluded'] != false || bubble?['ready'] != false) {
        throw StateError('Bubble cleanup failed');
      }
      debugPrint(
        'Native paired take check passed: protected countdown/reader/HUD/camera bubble, separate generated videos, shared pause clock, one durable pair, clean shutdown.',
      );
    } else {
      debugPrint(
        generatedSystemAudio
            ? 'Native generated audio take check passed: protected controls, computer sound without microphone/Voice activity, shared pause, durable sound choice and clean shutdown.'
            : 'Native screen take check passed: protected countdown/reader/HUD, silent video, pause/resume, hide/show, one durable take, clean shutdown.',
      );
    }
    library.dispose();
  } on Object {
    debugPrint(
      generatedSystemAudio
          ? 'Native generated audio take check failed.'
          : cameraFixture == null
          ? 'Native screen take check failed.'
          : 'Native paired take check failed.',
    );
  } finally {
    action?.cancel();
    owner?.dispose();
    fixture?.kill();
  }
  await SystemNavigator.pop();
}

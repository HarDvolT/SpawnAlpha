// Build only with the explicit paired_ui_fixture CMake target. Its camera
// source is a generated MP4 argument, never a real camera or private desktop.
import 'package:spawnalpha/src/ui/camera_bubble_screen.dart';
import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';
import 'package:spawnalpha/src/ui/recording_hud_screen.dart';

import 'native_screen_take_check.dart' as check;

@pragma('vm:entry-point')
Future<void> floatingPrompterMain() => runFloatingPrompter();
@pragma('vm:entry-point')
Future<void> recordingHudMain() => runRecordingHud();
@pragma('vm:entry-point')
Future<void> cameraBubbleMain() => runCameraBubble();
Future<void> main(List<String> arguments) =>
    check.runGeneratedTake(cameraFixture: arguments.single);

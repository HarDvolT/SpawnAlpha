import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';
import 'package:spawnalpha/src/ui/recording_hud_screen.dart';
import 'package:spawnalpha/src/ui/camera_bubble_screen.dart';

import 'native_screen_take_check.dart';

@pragma('vm:entry-point')
Future<void> floatingPrompterMain() => runFloatingPrompter();
@pragma('vm:entry-point')
Future<void> recordingHudMain() => runRecordingHud();
@pragma('vm:entry-point')
Future<void> cameraBubbleMain() => runCameraBubble();
Future<void> main() => runGeneratedTake(notes: true, generatedActivity: true);

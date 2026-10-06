import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';
import 'package:spawnalpha/src/ui/recording_hud_screen.dart';
import 'package:spawnalpha/src/ui/camera_bubble_screen.dart';

import 'native_screen_take_check.dart';
import 'native_activity_recovery_check.dart';

@pragma('vm:entry-point')
Future<void> floatingPrompterMain() => runFloatingPrompter();
@pragma('vm:entry-point')
Future<void> recordingHudMain() => runRecordingHud();
@pragma('vm:entry-point')
Future<void> cameraBubbleMain() => runCameraBubble();
Future<void> main(List<String> args) =>
    args.length == 2 && args.first == 'recover'
    ? runGeneratedRecovery(args.last)
    : runGeneratedTake(
        generatedActivity: true,
        crashAfterRecord: args.length == 1 && args.single == 'crash',
      );

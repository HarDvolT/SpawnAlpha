// Development-only exclusion/lifetime check: no camera, microphone, capture,
// owner data or saved media. The child uses its pre-go state only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spawnalpha/src/recording/camera_bubble.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/ui/camera_bubble_screen.dart';
import 'package:spawnalpha/src/theme/theme.dart';

@pragma('vm:entry-point')
Future<void> cameraBubbleMain() => runCameraBubble();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(
        body: Center(child: Text('Checking hidden camera preview…')),
      ),
    ),
  );
  await Future<void>.delayed(SaDurations.beat);
  try {
    final sources = await ScreenSources.platform().list();
    final source = sources.firstWhere(
      (s) => s.kind == ScreenSourceKind.display,
    );
    const bubble = WindowsCameraBubbles();
    for (var i = 0; i < 2; ++i) {
      final handle = await bubble.open(source, 'Generated check');
      if (!await bubble.isSafe(handle)) throw StateError('Preview unsafe');
      await bubble.close(const CameraBubbleHandle(-1));
      if (!await bubble.isSafe(handle)) {
        throw StateError('Stale close changed preview');
      }
      await bubble.close(handle);
      if (await bubble.isSafe(handle)) throw StateError('Preview not closed');
    }
    debugPrint(
      'Native camera bubble check passed: excluded before visibility, stale-close guard and repeated close/reopen; no camera opened.',
    );
  } on Object {
    debugPrint('Native camera bubble check failed.');
  }
  await SystemNavigator.pop();
}

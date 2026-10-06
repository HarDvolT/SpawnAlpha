import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/recording_hud.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/recording_hud_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(recordingHudViewChannel, null),
  );
  testWidgets(
    'camera choice fits its protected panel and keeps Stop and Pause available',
    (tester) async {
      tester.view.physicalSize = Size(
        SaPrompter.hudWidth,
        SaPrompter.hudQuestionHeight,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final commands = <String>[];
      List? regions;
      messenger.setMockMethodCallHandler(recordingHudViewChannel, (call) async {
        if (call.method == 'command') commands.add(call.arguments as String);
        if (call.method == 'hitRegions') regions = call.arguments as List;
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const RecordingHudScreen(
            initial: HudState(
              phase: HudPhase.recording,
              camera: true,
              companionQuestion: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Keep docked'), findsOneWidget);
      for (final label in ['Keep docked', 'Follow anyway', 'Cancel']) {
        await tester.tap(find.text(label));
      }
      await tester.tap(find.byTooltip('Pause recording'));
      await tester.tap(find.byTooltip('Stop recording'));
      await tester.tap(find.byTooltip('Companion'));
      expect(commands, [
        'companionDocked',
        'companionFollow',
        'companionCancel',
        'pause',
        'stop',
        'companion',
      ]);
      expect(regions!.length, lessThanOrEqualTo(8));
    },
  );
  for (final name in [
    'Microphone with a long device name',
    'Microphone sans fil',
    'ميكروفون لاسلكي',
  ]) {
    testWidgets('recording HUD fits and sends controls: $name', (tester) async {
      tester.view.physicalSize = Size(
        SaPrompter.hudWidth,
        SaPrompter.hudHeight,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final commands = <String>[];
      messenger.setMockMethodCallHandler(recordingHudViewChannel, (call) async {
        if (call.method == 'command') commands.add(call.arguments as String);
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: RecordingHudScreen(
            initial: HudState(
              phase: HudPhase.recording,
              microphone: name,
              duration: const Duration(seconds: 8),
              peakDb: -9,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(name), findsOneWidget);
      await tester.tap(find.byTooltip('Pause recording'));
      await tester.tap(find.byTooltip('Stop recording'));
      await tester.tap(find.byTooltip('Hide prompter'));
      expect(commands, ['pause', 'stop', 'prompter']);
    });
  }
  testWidgets(
    'computer-only HUD names sound honestly and leaves mic meter empty',
    (tester) async {
      tester.view.physicalSize = Size(
        SaPrompter.hudWidth,
        SaPrompter.hudHeight,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      messenger.setMockMethodCallHandler(
        recordingHudViewChannel,
        (_) async => null,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const RecordingHudScreen(
            initial: HudState(
              phase: HudPhase.recording,
              recordAudio: false,
              recordSystemAudio: true,
              peakDb: -9,
            ),
          ),
        ),
      );
      expect(find.text('Computer sound only'), findsOneWidget);
      expect(find.text('Without sound'), findsNothing);
      expect(find.byTooltip('Computer sound on'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('countdown can be cancelled and saving disables controls', (
    tester,
  ) async {
    tester.view.physicalSize = Size.square(SaPrompter.countdownWindowSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? command;
    messenger.setMockMethodCallHandler(recordingHudViewChannel, (call) async {
      if (call.method == 'command') command = call.arguments as String?;
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const RecordingHudScreen(
          initial: HudState(phase: HudPhase.countdown, countdown: 3),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    expect(command, 'stop');
    tester.view.physicalSize = Size(SaPrompter.hudWidth, SaPrompter.hudHeight);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = Size(SaPrompter.hudWidth, SaPrompter.hudHeight);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const RecordingHudScreen(
          initial: HudState(phase: HudPhase.saving),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.onPressed, isNull);
    }
  });
}

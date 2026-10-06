import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/recording/audio_input.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/recording/screen_preview.dart';
import 'package:spawnalpha/src/recording/camera_bubble.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/record_screen.dart';
import 'package:spawnalpha/src/ui/record_setup.dart';
import 'package:spawnalpha/src/ui/recording_widgets.dart';

import '../../tool/fixtures/preview_camera.dart';

class FixtureSources implements ScreenSources {
  const FixtureSources();
  @override
  bool get supported => true;
  @override
  Future<List<ScreenSource>> list() async => const [
    ScreenSource(
      id: 'fixture',
      name: 'Generated window',
      kind: ScreenSourceKind.window,
      width: 640,
      height: 360,
    ),
  ];
}

class FixturePreview implements ScreenPreviews {
  int started = 0, stopped = 0;
  @override
  bool get supported => true;
  @override
  Future<PreviewHandle> start(ScreenSource source) async {
    ++started;
    return const PreviewHandle(
      sessionId: 1,
      textureId: 1,
      width: 640,
      height: 360,
    );
  }

  @override
  Future<PreviewStatus> status(PreviewHandle handle) async =>
      const PreviewStatus(closed: true);
  @override
  Future<void> stop(PreviewHandle handle) async {
    ++stopped;
  }
}

void main() {
  for (final language in ScriptLanguage.values) {
    testWidgets('Screen setup works without a camera in ${language.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
      final settings = Settings(secrets: MemorySecretStore())
        ..recordMode = TakeMode.screen;
      final preview = FixturePreview();
      final library = ScriptLibrary(MemoryScriptStore());
      final services = AppServices(
        library: library,
        settings: settings,
        recordingsDir: Directory.systemTemp,
        audio: const UnsupportedAudioInputs(),
        screens: const FixtureSources(),
        previews: preview,
        recorder: const WindowsScreenRecordings(),
      );
      final script = ScriptDocument.create(
        language: language,
        text: switch (language) {
          ScriptLanguage.en => 'A clear line.',
          ScriptLanguage.fr => 'Une phrase claire.',
          ScriptLanguage.ar => 'عبارة واضحة.',
        },
      );
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: RecordScreen(script: script),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<RecordModeTiles>(find.byType(RecordModeTiles)).mode,
        TakeMode.screen,
      );
      expect(find.text('No camera found.'), findsNothing);
      expect(
        find.text('Choose a display or window above to record.'),
        findsOneWidget,
      );
      expect(
        tester.widget<RecordButton>(find.byType(RecordButton)).enabled,
        isFalse,
      );
      await tester.tap(find.text('Choose screen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generated window'));
      await tester.pump();
      await tester.tap(find.text('Use this source'));
      await tester.pumpAndSettle();
      expect(preview.started, 1);
      expect(preview.stopped, 1);
      expect(
        find.text('No microphone found. Fix it above, or '),
        findsOneWidget,
      );
      await tester.tap(find.text('record without sound'));
      await tester.pump();
      expect(
        tester.widget<RecordButton>(find.byType(RecordButton)).enabled,
        isTrue,
      );
      expect(find.textContaining('System audio is off'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    });
  }
  for (final language in ScriptLanguage.values) {
    testWidgets(
      'Both setup previews the exact camera and preserves choices in ${language.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
        final originalCamera = CameraPlatform.instance;
        final name = switch (language) {
          ScriptLanguage.en => 'Chosen camera',
          ScriptLanguage.fr => 'Caméra choisie',
          ScriptLanguage.ar => 'الكاميرا المختارة',
        };
        final camera = PreviewCamera(name);
        // ignore: invalid_use_of_visible_for_testing_member
        CameraPlatform.instance = camera;
        addTearDown(() {
          // ignore: invalid_use_of_visible_for_testing_member
          CameraPlatform.instance = originalCamera;
        });
        final settings = Settings(secrets: MemorySecretStore())
          ..recordMode = TakeMode.both;
        final preview = FixturePreview();
        final library = ScriptLibrary(MemoryScriptStore());
        final services = AppServices(
          library: library,
          settings: settings,
          recordingsDir: Directory.systemTemp,
          audio: const UnsupportedAudioInputs(),
          screens: const FixtureSources(),
          previews: preview,
          recorder: const WindowsScreenRecordings(),
          bubbles: const WindowsCameraBubbles(),
        );
        final script = ScriptDocument.create(
          language: language,
          text: switch (language) {
            ScriptLanguage.en => 'A clear line.',
            ScriptLanguage.fr => 'Une phrase claire.',
            ScriptLanguage.ar => 'عبارة واضحة.',
          },
        );
        await tester.pumpWidget(
          AppScope(
            services: services,
            child: MaterialApp(
              theme: buildTheme(Brightness.dark),
              home: RecordScreen(script: script),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<RecordModeTiles>(find.byType(RecordModeTiles)).mode,
          TakeMode.both,
        );
        expect(find.text(name), findsOneWidget);
        expect(find.textContaining('generated-camera'), findsNothing);
        expect(camera.events, ['camera-preview']);
        expect(find.byType(ClipOval), findsOneWidget);
        await tester.tap(find.text('Choose screen').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generated window'));
        await tester.pump();
        await tester.tap(find.text('Use this source'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('record without sound'));
        await tester.pump();
        expect(
          tester.widget<RecordButton>(find.byType(RecordButton)).enabled,
          isTrue,
        );
        await tester.tap(find.text('Screen').first);
        await tester.pumpAndSettle();
        expect(camera.events.last, 'camera-dispose');
        expect(settings.recordMode, TakeMode.screen);
        await tester.tap(find.text('Both'));
        await tester.pumpAndSettle();
        expect(camera.events.last, 'camera-preview');
        expect(settings.recordMode, TakeMode.both);
        expect(find.text('Generated window'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        library.dispose();
      },
    );
  }
}

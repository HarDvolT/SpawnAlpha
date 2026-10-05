import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/recording/audio_input.dart';
import 'package:spawnalpha/src/recording/screen_preview.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/ui/screen_preview_screen.dart';
import 'package:spawnalpha/src/ui/record_screen.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';

import '../recording/screen_preview_test.dart' show FakeScreenPreviews;
import '../recording/screen_source_test.dart' show FakeScreenSources;

class _NoCameras extends CameraPlatform with MockPlatformInterfaceMixin {
  @override
  Future<List<CameraDescription>> availableCameras() async => [];
}

void main() {
  testWidgets('setup opens one preview on double tap, releases it and can reopen', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final originalCameras = CameraPlatform.instance;
    // ignore: invalid_use_of_visible_for_testing_member
    CameraPlatform.instance = _NoCameras();
    addTearDown(() {
      // ignore: invalid_use_of_visible_for_testing_member
      CameraPlatform.instance = originalCameras;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    final backend = FakeScreenPreviews();
    final services = AppServices(library: ScriptLibrary(MemoryScriptStore()),
      settings: Settings(secrets: MemorySecretStore())..recordMode = TakeMode.screen, recordingsDir: Directory.systemTemp,
      audio: const UnsupportedAudioInputs(), screens: FakeScreenSources(), previews: backend, recorder: const WindowsScreenRecordings());
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(
      home: RecordScreen(script: ScriptDocument.create(text: 'Hello there.')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose screen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display 1'));
    await tester.pump();
    await tester.tap(find.text('Use this source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview screen'));
    // The first push already covers the setup hit region; a second physical
    // tap is intentionally swallowed by that transition surface.
    await tester.tap(find.text('Preview screen'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(backend.nextId, 2);
    expect(find.byType(ScreenPreviewScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(backend.stopped, [1, 2]);
    await tester.tap(find.text('Preview screen'));
    await tester.pumpAndSettle();
    expect(backend.nextId, 4);
    await tester.pumpWidget(const SizedBox());
    expect(backend.stopped, [1, 2, 3, 4]);
  });
  for (final name in ['My presentation', 'Présentation française', 'عرض تقديمي']) {
    testWidgets('preview is local, sized correctly and releases when closed: $name', (tester) async {
      final backend = FakeScreenPreviews();
      await tester.pumpWidget(MaterialApp(home: ScreenPreviewScreen(previews: backend,
        source: ScreenSource(id: 'test', name: name, kind: ScreenSourceKind.window, width: 1920, height: 1080))));
      await tester.pump();
      expect(find.text(name), findsOneWidget);
      expect(find.text('Live preview only · nothing saved'), findsOneWidget);
      expect(find.byType(Texture), findsOneWidget);
      expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, closeTo(16 / 9, .001));
      await tester.pumpWidget(const SizedBox());
      expect(backend.stopped, [1]);
    });
  }
  testWidgets('a closed source shows a retry instead of a frozen live texture', (tester) async {
    final backend = FakeScreenPreviews()..current = const PreviewStatus(closed: true);
    await tester.pumpWidget(MaterialApp(home: ScreenPreviewScreen(previews: backend,
      source: const ScreenSource(id: 'test', name: 'Test window', kind: ScreenSourceKind.window, width: 1280, height: 720))));
    await tester.pumpAndSettle();
    expect(find.text('This source closed. Choose another.'), findsOneWidget);
    expect(find.byType(Texture), findsNothing);
    backend.current = const PreviewStatus(ready: true, width: 1280, height: 720);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byType(Texture), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

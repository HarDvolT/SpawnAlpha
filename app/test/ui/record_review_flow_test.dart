import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/recording/audio_input.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/record_screen.dart';
import 'package:spawnalpha/src/ui/recording_widgets.dart';
import 'package:spawnalpha/src/ui/take_review_screen.dart';

import '../../tool/fixtures/preview_camera.dart';
import '../playback/playback_controller_test.dart' show FakePlayback;
import '../transcription/speech_processor_test.dart' show FakeSpeech;

class SavedCamera extends PreviewCamera {
  SavedCamera(this.file) : super('Generated camera');
  final File file;
  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async =>
      events.add('camera-record');
  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    events.add('camera-stop');
    return XFile(file.path);
  }
}

class MeterAudio extends UnsupportedAudioInputs {
  bool metering = false, watching = false;
  @override
  bool get supported => true;
  @override
  Future<List<AudioInput>> list() async => const [
    AudioInput(id: 'generated', name: 'Generated microphone', isDefault: true),
  ];
  @override
  Future<void> startLevels(String? id) async {
    metering = true;
  }

  @override
  Future<void> stopLevels() async {
    metering = false;
  }

  @override
  Future<void> watchAll() async {
    watching = true;
  }

  @override
  Future<void> unwatchAll() async {
    watching = false;
  }

  @override
  Future<MicLevel> level() async => const MicLevel(peakDb: -12, rmsDb: -22);
}

void main() {
  testWidgets('save opens review, releases live input, then restores setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('spawnalpha-review-flow-'),
    );
    Future<void> drainIo(bool Function() ready) async {
      for (var i = 0; i < 30 && !ready(); ++i) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    final file = File('${root!.path}/generated.mp4');
    // Deliberately no audio track, so the saved warning must reach review.
    await tester.runAsync(
      () => file.writeAsBytes([0, 0, 0, 8, 0x6d, 0x6f, 0x6f, 0x76]),
    );
    final camera = SavedCamera(file), original = CameraPlatform.instance;
    // ignore: invalid_use_of_visible_for_testing_member
    CameraPlatform.instance = camera;
    final audio = MeterAudio(), library = ScriptLibrary(MemoryScriptStore());
    final script = ScriptDocument.create(text: 'Hello everyone.');
    await library.save(script);
    final services = AppServices(
      library: library,
      settings: Settings(secrets: MemorySecretStore())
        ..processAfterStop = false,
      recordingsDir: Directory('${root.path}/recordings'),
      audio: audio,
      playback: FakePlayback(),
      speechBackend: FakeSpeech('unused'),
    );
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: RecordScreen(script: script),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RecordButton).first);
    await tester.pump(const Duration(seconds: 3));
    await drainIo(() => camera.events.contains('camera-record'));
    expect(camera.events, contains('camera-record'));
    await tester.tap(find.byType(RecordButton).first);
    await tester.pump();
    await drainIo(() => find.byType(TakeReviewScreen).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(TakeReviewScreen), findsOneWidget);
    expect(find.textContaining('no sound track'), findsOneWidget);
    expect(audio.metering, isFalse);
    expect(audio.watching, isFalse);
    expect(camera.events.last, 'camera-dispose');
    expect(library.byId(script.id)!.takes, hasLength(1));
    await tester.tap(find.text('Record another'));
    await tester.pumpAndSettle();
    expect(find.byType(TakeReviewScreen), findsNothing);
    expect(audio.metering, isTrue);
    expect(audio.watching, isTrue);
    expect(camera.events.last, 'camera-audio');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // ignore: invalid_use_of_visible_for_testing_member
    CameraPlatform.instance = original;
    // camera's pending error listener expects an event before its stream closes.
    camera.errors.add(CameraErrorEvent(1, 'Generated cleanup'));
    await tester.pump();
    await camera.errors.close();
    library.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}

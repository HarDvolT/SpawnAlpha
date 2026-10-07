// Renders the main screens to PNG files with real fonts, so the UI can be
// checked visually without a device (for example in a cloud container).
// It is not part of the test suite. Run it from app/ with:
//
//   flutter test tool/screenshots_test.dart --update-goldens
//
// Images land in app/tool/screenshots/ (git-ignored). Text uses the app's
// bundled fonts (assets/fonts); anything asking for Roboto gets DejaVu Sans
// from /usr/share/fonts, or from SCREENSHOT_FONT_DIR.

import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/markup/local_markup_engine.dart';
import 'package:spawnalpha/src/markup/markup_engine.dart';
import 'package:spawnalpha/src/markup/providers.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/mark_editing.dart';
import 'package:spawnalpha/src/model/samples.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/render/room_tone.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/prompter/guide.dart';
import 'package:spawnalpha/src/prompter/prompter_controller.dart';
import 'package:spawnalpha/src/prompter/prompter_view.dart';
import 'package:spawnalpha/src/recording/audio_input.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/recording/screen_preview.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/editor_screen.dart';
import 'package:spawnalpha/src/ui/home_screen.dart';
import 'package:spawnalpha/src/ui/library_screen.dart';
import 'package:spawnalpha/src/ui/settings_screen.dart';
import 'package:spawnalpha/src/ui/prompter_screen.dart';
import 'package:spawnalpha/src/ui/record_screen.dart';
import 'package:spawnalpha/src/ui/record_setup.dart';
import 'package:spawnalpha/src/ui/recording_widgets.dart';
import 'package:spawnalpha/src/ui/script_page.dart';
import 'package:spawnalpha/src/ui/screen_source_picker.dart';
import 'package:spawnalpha/src/ui/screen_preview_screen.dart';
import 'package:spawnalpha/src/ui/floating_prompter_screen.dart';
import 'package:spawnalpha/src/ui/recording_hud_screen.dart';
import 'package:spawnalpha/src/recording/recording_hud.dart';
import 'package:spawnalpha/src/recording/camera_bubble.dart';
import 'package:spawnalpha/src/ui/camera_bubble_screen.dart';
import 'package:spawnalpha/src/ui/notes_editor_screen.dart';
import 'package:spawnalpha/src/ui/notes_practice_screen.dart';
import 'package:spawnalpha/src/ui/take_review_screen.dart';
import 'package:spawnalpha/src/ui/cut_editor_screen.dart';
import 'package:spawnalpha/src/ui/publishing_screen.dart';
import 'package:spawnalpha/src/review/publishing_text.dart';
import 'package:spawnalpha/src/storage/publishing_store.dart';
import 'package:spawnalpha/src/ui/clean_cut_panel.dart';
import 'package:spawnalpha/src/ui/retake_review_panel.dart';
import 'package:spawnalpha/src/review/repeated_sections.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/transcription/speech_models.dart';
import '../test/cut/clean_plan_test.dart' show cleanFixture, gap;
import '../test/cut/cut_editor_test.dart' show editorFixture, range;
import '../test/review/publishing_text_test.dart' show publishingScript, publishingWords, publishingPlan;
import '../test/review/repeated_sections_test.dart' show repeatedScript, repeatedSpeech;
import '../test/cut/retake_review_test.dart' show retakeWords, retakeScript, retakePlan;
import '../test/cut/filler_review_test.dart' show fillerFixture, fillerPlan, fillerScript;
import '../test/model/note_deck_test.dart' show fixtureNotes;
import '../test/ui/take_review_test.dart' show reviewFixture;
import '../test/playback/playback_controller_test.dart' show FakePlayback;
import 'package:spawnalpha/src/ui/take_player.dart';
import 'package:spawnalpha/src/ui/video_export_panel.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/model/caption_style.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/transcription/take_processing.dart';
import 'package:spawnalpha/src/playback/local_playback.dart';
import 'package:spawnalpha/src/ui/word_review_panel.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

import 'fixtures/cue_check_scripts.dart';
import 'fixtures/preview_camera.dart';

class _ScreenCandidates implements ScreenSources {
  const _ScreenCandidates(this.name);
  final String name;
  @override
  bool get supported => true;
  @override
  Future<List<ScreenSource>> list() async => [
    const ScreenSource(id: 'display:main', name: 'Display 1', kind: ScreenSourceKind.display,
      width: 1920, height: 1080, primary: true),
    ScreenSource(id: 'window:presentation', name: name, kind: ScreenSourceKind.window, width: 1280, height: 720),
  ];
}

class _ClosedScreenPreview implements ScreenPreviews {
  const _ClosedScreenPreview();
  @override
  bool get supported => true;
  @override
  Future<PreviewHandle> start(ScreenSource source) async => const PreviewHandle(
    sessionId: 1, textureId: 1, width: 1280, height: 720);
  @override
  Future<PreviewStatus> status(PreviewHandle handle) async => const PreviewStatus(closed: true);
  @override
  Future<void> stop(PreviewHandle handle) async {}
}

Future<void> _loadFonts() async {
  final fontDir = Platform.environment['SCREENSHOT_FONT_DIR'] ?? '/usr/share/fonts/truetype/dejavu';
  final flutterRoot = Platform.resolvedExecutable.split('${Platform.pathSeparator}bin${Platform.pathSeparator}cache').first;
  Future<ByteData> bytes(String path) async => ByteData.sublistView(await File(path).readAsBytes());

  final text = FontLoader('Roboto');
  if (Platform.isWindows && Platform.environment['SCREENSHOT_FONT_DIR'] == null) {
    // Use the bundled reading font on Windows; no system font download is needed.
    text.addFont(bytes('assets/fonts/ReadexPro-Variable.ttf'));
  } else {
    text
      ..addFont(bytes('$fontDir/DejaVuSans.ttf'))
      ..addFont(bytes('$fontDir/DejaVuSans-Bold.ttf'));
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'));
  // The design language's type voices, as bundled in pubspec.yaml.
  const bundled = {
    'Anybody': ['Anybody-Variable.ttf'],
    'Readex Pro': ['ReadexPro-Variable.ttf'],
    'Martian Mono': ['MartianMono-Variable.ttf'],
    'Caveat': ['Caveat-Variable.ttf'],
    'Aref Ruqaa': ['ArefRuqaa-Regular.ttf', 'ArefRuqaa-Bold.ttf'],
    'Reem Kufi': ['ReemKufi-Variable.ttf'],
  };
  final voices = [
    for (final MapEntry(key: family, value: files) in bundled.entries)
      files.fold(FontLoader(family), (loader, file) => loader..addFont(bytes('assets/fonts/$file'))),
  ];
  await Future.wait([text.load(), icons.load(), for (final v in voices) v.load()]);
}

/// A microphone for screenshots: two inputs, and someone talking.
class _TalkingMic implements AudioInputs {
  _TalkingMic({this.denied = false});

  /// Windows refuses access (the privacy switches are off).
  final bool denied;

  @override
  bool get supported => true;

  @override
  Future<List<AudioInput>> list() async => const [
        AudioInput(id: 'headset', name: 'Headset microphone', isDefault: true),
        AudioInput(id: 'webcam', name: 'Webcam microphone', isDefault: false),
      ];

  @override
  Future<void> select(String? id) async {}

  @override
  Future<void> startLevels(String? id) async {}

  @override
  Future<void> stopLevels() async {}

  @override
  Future<MicLevel> level() async => denied
      ? const MicLevel(peakDb: -100, rmsDb: -100, failed: true, denied: true)
      : const MicLevel(peakDb: -12, rmsDb: -22);

  @override
  Future<void> watchAll() async {}

  @override
  Future<Map<String, MicLevel>> levels() async => {
        'headset': await level(),
        'webcam': MicLevel(peakDb: -100, rmsDb: -100, failed: denied, denied: denied),
      };

  @override
  Future<void> unwatchAll() async {}
}

/// No camera in a container: the record screen shows its chrome and says so.
// This file runs under `flutter test`, but lives in tool/ rather than test/.
// ignore: invalid_use_of_visible_for_testing_member
class _NoCameras extends CameraPlatform with MockPlatformInterfaceMixin {
  @override
  Future<List<CameraDescription>> availableCameras() async => [];
}

Future<ScriptDocument> _markedUp(ScriptDocument s, {bool accept = true}) async {
  final result = await const LocalMarkupEngine().markup(s);
  final marked = applyMarkup(s, result);
  return accept ? marked.acceptAllMarks() : marked;
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    // The prompter keeps the screen awake; there is no device here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  Future<AppServices> services(List<ScriptDocument> scripts, {AudioInputs? audio}) async {
    final library = ScriptLibrary(MemoryScriptStore());
    for (final s in scripts.reversed) {
      await library.save(s);
    }
    return AppServices(
      library: library,
      settings: Settings(secrets: MemorySecretStore()),
      recordingsDir: Directory.systemTemp,
      audio: audio ?? const UnsupportedAudioInputs(),
      playback: FakePlayback(),
    );
  }

  Future<void> shoot(WidgetTester tester, String name, Size size, Widget Function(AppServices) screen,
      List<ScriptDocument> scripts,
      {Future<void> Function(WidgetTester)? before,
      Brightness brightness = Brightness.light,
      bool settle = true,
      AudioInputs? audio}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await services(scripts, audio: audio);
    await tester.pumpWidget(AppScope(
      services: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness),
        home: screen(app),
      ),
    ));
    // Animations that should be caught mid-way skip settling.
    settle ? await tester.pumpAndSettle() : await tester.pump();
    if (before != null) await before(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
  }

  const phone = Size(430, 900);
  const desktop = Size(1280, 800);

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final portrait in [false, true]) {
      testWidgets('local player $brightness portrait=$portrait', (tester) async {
        final playback = FakePlayback()..value = PlaybackStatus(
          ready: true, width: portrait ? 1080 : 1920, height: portrait ? 1920 : 1080,
          duration: const Duration(minutes: 1));
        await shoot(tester, 'take-player-${brightness.name}-${portrait ? 'portrait' : 'landscape'}',
          portrait ? phone : desktop, (_) => Scaffold(appBar: AppBar(title: const Text('Your take')),
            body: Padding(padding: const EdgeInsets.all(SaSpace.s5), child: TakePlayer(backend: playback, path: 'generated'))),
          [], brightness: brightness);
      });
    }
  }

  for (final language in ScriptLanguage.values) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final state in ['kept', 'chosen', 'unsafe']) {
        testWidgets('retake selection $language $brightness $state', (tester) async {
          final words = retakeWords(language), script = retakeScript(language);
          final base = retakePlan(words, quiet: state == 'unsafe' ? [] : null).restoreAll();
          final plan = state == 'chosen' ? base.withAttempt(base.retakes.single.id, 1) : base;
          await shoot(tester, 'retake-selection-${language.name}-${brightness.name}-$state', phone,
            (_) => Scaffold(appBar: AppBar(title: const Text('Your take')), body: ListView(
              padding: const EdgeInsets.all(SaSpace.s5), children: [
                RetakeReviewPanel(sections: repeatedSections(script, words), busy: false,
                  plan: plan, onSelect: (_, _) {}, onListen: (_) {}),
              ])), [script], brightness: brightness);
        });
      }
    }
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final partial in [false, true]) {
        testWidgets('attempt comparison $language $brightness partial=$partial', (tester) async {
          final script = repeatedScript(language);
          final sections = repeatedSections(script, repeatedSpeech(script, partial: partial,
            confidence: partial ? null : .9));
          await shoot(tester, 'attempt-comparison-${language.name}-${brightness.name}-${partial ? 'partial' : 'full'}', phone,
            (_) => Scaffold(appBar: AppBar(title: const Text('Your take')), body: ListView(
              padding: const EdgeInsets.all(SaSpace.s5), children: [
                RetakeReviewPanel(sections: sections, busy: false, onListen: (_) {}),
              ])), [script], brightness: brightness);
        });
      }
    }
    final correctedText = switch (language) { ScriptLanguage.en => 'Today', ScriptLanguage.fr => 'Demain', ScriptLanguage.ar => 'غدا' };
    final wordTake = Take(path: 'generated.mp4', recordedAt: DateTime(2026), duration: const Duration(seconds: 3));
    final reviewWords = reviewFixture(language, wordTake).transcript;
    final originalWord = reviewWords.words.first;
    final correctedWords = WordTranscript(language: language, duration: reviewWords.duration, words: [
      SpokenWord(text: correctedText, start: originalWord.start, end: originalWord.end,
        confidence: .3, recognizedText: originalWord.text), ...reviewWords.words.skip(1)]);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('word review $language $brightness', (tester) async {
        await shoot(tester, 'word-review-${language.name}-${brightness.name}', phone,
          (_) => Scaffold(appBar: AppBar(title: const Text('Spoken words')), body: SingleChildScrollView(
            padding: const EdgeInsets.all(SaSpace.s5), child: WordReviewPanel(transcript: correctedWords,
              busy: false, onCorrect: (_, _) async {}))), [], brightness: brightness,
          before: (tester) async { await tester.tap(find.text('Review wording')); await tester.pumpAndSettle(); });
      });
    }
    testWidgets('word correction dialog $language', (tester) async {
      await shoot(tester, 'word-correction-${language.name}', phone, (_) => Scaffold(body:
        CorrectWordDialog(word: correctedWords.words.first, rtl: language.isRtl)), []);
    });
    for (final processing in [false, true]) {
      testWidgets('after stop $language processing=$processing', (tester) async {
        final take = Take(path: 'generated.mp4', recordedAt: DateTime(2026), duration: const Duration(seconds: 3));
        final spoken = reviewFixture(language, take);
        await shoot(tester, 'after-stop-${language.name}-${processing ? 'progress' : 'setup'}', desktop, (app) {
          app.processing.source = take.path;
          app.processing.phase = processing ? TakeProcessPhase.cut : TakeProcessPhase.needsSetup;
          if (processing) { app.speechModels.phase = SpeechModelPhase.ready; app.speech.result = spoken; }
          return TakeReviewScreen(script: spoken.snapshot!, take: take, fromRecording: true,
            recordingNotice: 'The camera stopped early. The screen recording is safe.');
        }, [spoken.snapshot!], settle: !processing);
      });
    }
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final captionStyle in CaptionStyle.values) {
      for (final working in [false, true]) {
        testWidgets('video export $language $brightness $captionStyle working=$working', (tester) async {
          final script = sampleScripts().firstWhere((s) => s.language == language);
          await shoot(tester, 'video-export-${language.name}-${brightness.name}-${working ? 'progress' : 'saved'}${captionStyle == CaptionStyle.readable ? '' : '-${captionStyle.name}'}',
            phone, (app) {
              if (working) { app.exports.phase = ExportPhase.rendering; app.exports.progress = .6; }
              return Scaffold(appBar: AppBar(title: const Text('Your take')), body: ListView(
                padding: const EdgeInsets.all(SaSpace.s5), children: [
                  Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Text(script.displayTitle, style: SaType.body)),
                  const SizedBox(height: SaSpace.s5),
                  VideoExportPanel(format: VideoFormat.portrait, onFormat: (_) {}, onExport: () {},
                    job: app.exports, busy: working, supported: true, hasCamera: true, hasCaptions: true,
                    captionStyle: captionStyle, hasAudioJoins: true, hasScreenActivity: true, hasScreen: true, hasCameraEmphasis: true,
                    videos: [VideoExport(id: 'generated', format: VideoFormat.portrait,
                      captions: true, burnedCaptions: true, softAudioJoins: true, zoomCount: 3, clickCount: 8, shortcutCount: 4, screenFrame: true, cameraPunchCount: 2,
                      captionStyle: captionStyle,
                      duration: const Duration(seconds: 25), createdAt: DateTime(2026, 10, 6, 18, 30))],
                    onView: (_) {}, onShow: (_) {}),
                ]));
            }, [script], brightness: brightness, settle: !working);
        });
      }
      }
    }
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('screen motion blur export $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        await shoot(tester, 'screen-blur-${language.name}-${brightness.name}', phone, (app) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
            Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(script.displayTitle, style: SaType.body)),
            const SizedBox(height: SaSpace.s5),
            VideoExportPanel(format: VideoFormat.portrait, onFormat: (_) {}, onExport: () {}, job: app.exports,
              busy: false, supported: true, hasMotionBlur: true, onMotionBlur: (_) {}, hasScreen: true, hasScreenActivity: true,
              videos: [VideoExport(id: 'generated', format: VideoFormat.portrait, motionBlur: true, zoomCount: 2,
                duration: const Duration(seconds: 4), createdAt: DateTime(2026, 10, 7, 10, 30))], onView: (_) {}, onShow: (_) {}),
          ])), [script], brightness: brightness);
      });
      testWidgets('sound balance export $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        await shoot(tester, 'sound-balance-${language.name}-${brightness.name}', phone, (app) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
            Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(script.displayTitle, style: SaType.body)),
            const SizedBox(height: SaSpace.s5),
            VideoExportPanel(format: VideoFormat.portrait, onFormat: (_) {}, onExport: () {}, job: app.exports,
              busy: false, supported: true, onBalanceSound: (_) {},
              videos: [VideoExport(id: 'generated', format: VideoFormat.portrait, balanceSound: true,
                duration: const Duration(seconds: 4), createdAt: DateTime(2026, 10, 7, 10, 30))], onView: (_) {}, onShow: (_) {}),
          ])), [script], brightness: brightness);
      });
      testWidgets('gentle S sound export $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        await shoot(tester, 'sound-softening-${language.name}-${brightness.name}', phone, (app) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
            Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(script.displayTitle, style: SaType.body)),
            const SizedBox(height: SaSpace.s5),
            VideoExportPanel(format: VideoFormat.portrait, onFormat: (_) {}, onExport: () {}, job: app.exports,
              busy: false, supported: true, onBalanceSound: (_) {}, onSoftenSharpSound: (_) {},
              videos: [VideoExport(id: 'generated', format: VideoFormat.portrait, balanceSound: true, softenSharpSound: true,
                duration: const Duration(seconds: 4), createdAt: DateTime(2026, 10, 7, 10, 30))], onView: (_) {}, onShow: (_) {}),
          ])), [script], brightness: brightness);
      });
      testWidgets('noise reduction export $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        await shoot(tester, 'sound-noise-${language.name}-${brightness.name}', phone, (app) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
            Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(script.displayTitle, style: SaType.body)),
            const SizedBox(height: SaSpace.s5),
            VideoExportPanel(format: VideoFormat.portrait, onFormat: (_) {}, onExport: () {}, job: app.exports,
              busy: false, supported: true, onBalanceSound: (_) {}, onSoftenSharpSound: (_) {}, onReduceNoise: (_) {},
              videos: [VideoExport(id: 'generated', format: VideoFormat.portrait, balanceSound: true, softenSharpSound: true, reduceNoise: true,
                duration: const Duration(seconds: 4), createdAt: DateTime(2026, 10, 7, 10, 30))], onView: (_) {}, onShow: (_) {}),
          ])), [script], brightness: brightness);
      });
      testWidgets('room tone export $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        await shoot(tester, 'sound-room-${language.name}-${brightness.name}', phone, (app) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
            Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(script.displayTitle, style: SaType.body)),
            const SizedBox(height: SaSpace.s5),
            VideoExportPanel(format: VideoFormat.portrait, onFormat: (_) {}, onExport: () {}, job: app.exports,
              busy: false, supported: true, hasAudioJoins: true, onSoftAudioJoins: (_) {}, hasRoomTone: true, onRoomToneJoins: (_) {}, onBalanceSound: (_) {},
              videos: [VideoExport(id: 'generated', format: VideoFormat.portrait, balanceSound: true, softAudioJoins: true,
                roomTone: RoomTone(SourceRange(start: Duration.zero, end: const Duration(milliseconds: 100))),
                duration: const Duration(milliseconds: 2600), createdAt: DateTime(2026, 10, 7, 11, 30))], onView: (_) {}, onShow: (_) {}),
          ])), [script], brightness: brightness);
      });
      testWidgets('batch export $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        await shoot(tester, 'batch-export-${language.name}-${brightness.name}', phone, (app) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
            Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(script.displayTitle, style: SaType.body)),
            const SizedBox(height: SaSpace.s5),
            VideoExportPanel(format: VideoFormat.portrait, onFormat: (_) {}, onExport: () {}, job: app.exports,
              busy: false, supported: true, moreFormats: true, onMoreFormats: (_) {},
              extraFormats: const {VideoFormat.landscape, VideoFormat.feed}, onExtraFormat: (_, _) {},
              videos: const [], onView: (_) {}, onShow: (_) {}),
          ])), [script], brightness: brightness);
      });
      testWidgets('gap editor $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        final plan = editorFixture(language).withRange('quiet-0', range(1000, 2300));
        await shoot(tester, 'gap-editor-${language.name}-${brightness.name}', phone,
          (_) => CutEditorScreen(plan: plan, title: script.displayTitle,
            take: Take(path: 'generated', recordedAt: DateTime(2026), duration: plan.sourceDuration), playback: FakePlayback()),
          [script], brightness: brightness);
      });
      testWidgets('publishing text $language $brightness', (tester) async {
        final script = publishingScript(language);
        final draft = publishingFromSpeech(source: publishingWords(language), plan: publishingPlan(language), snapshot: script, aligned: true);
        await shoot(tester, 'publishing-text-${language.name}-${brightness.name}', phone,
          (_) => PublishingScreen(draft: draft, store: PublishingStore(Directory.systemTemp)),
          [script], brightness: brightness);
      });
      testWidgets('camera placement export $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        await shoot(tester, 'camera-placement-${language.name}-${brightness.name}', phone, (app) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
            Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(script.displayTitle, style: SaType.body)),
            const SizedBox(height: SaSpace.s5),
            VideoExportPanel(format: VideoFormat.feed, onFormat: (_) {}, onExport: () {},
              job: app.exports, busy: false, supported: true, hasCamera: true, hasScreenActivity: true,
              hasScreen: true, onCameraClear: (_) {}, videos: [VideoExport(id: 'generated', format: VideoFormat.feed,
                camera: true, cameraClear: true, duration: const Duration(seconds: 4), createdAt: DateTime(2026, 10, 7, 9, 30))],
              onView: (_) {}, onShow: (_) {}),
          ])), [script], brightness: brightness);
      });
      testWidgets('camera emphasis export $language $brightness', (tester) async {
        final script = sampleScripts().firstWhere((s) => s.language == language);
        await shoot(tester, 'camera-emphasis-${language.name}-${brightness.name}', phone, (app) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
            Directionality(textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(script.displayTitle, style: SaType.body)),
            const SizedBox(height: SaSpace.s5),
            VideoExportPanel(format: VideoFormat.portrait, onFormat: (_) {}, onExport: () {},
              job: app.exports, busy: false, supported: true, hasCameraEmphasis: true, onCameraPunch: (_) {},
              videos: [VideoExport(id: 'generated', format: VideoFormat.portrait, cameraPunchCount: 2,
                duration: const Duration(seconds: 25), createdAt: DateTime(2026, 10, 7, 8, 30))], onView: (_) {}, onShow: (_) {}),
          ])), [script], brightness: brightness);
      });
    }
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final chosen in [false, true]) {
        testWidgets('filler review $language $brightness chosen=$chosen', (tester) async {
          final words = fillerFixture(language);
          final base = fillerPlan(words);
          final plan = chosen ? base.withEnabled(base.changes.single.id, true) : base;
          await shoot(tester, 'filler-review-${language.name}-${brightness.name}-${chosen ? 'removed' : 'kept'}', phone,
            (_) => Scaffold(appBar: AppBar(title: const Text('Your take')), body: ListView(padding: const EdgeInsets.all(SaSpace.s5), children: [
              CleanCutPanel(plan: plan, busy: false, onChanged: (_, _) {}, onRestore: () {}, onListen: (_) {}),
            ])), [fillerScript(words)], brightness: brightness);
        });
      }
      testWidgets('cut changes $language $brightness', (tester) async {
        final spoken = cleanFixture(language);
        final notes = ScriptDocument.create(language: language).copyWith(recordingAid: RecordingAid.notes);
        final clean = planQuietCut(takeId: 'generated', transcript: spoken, quiet: [gap()], snapshot: notes);
        await shoot(tester, 'cut-changes-${language.name}-${brightness.name}', desktop, (_) => Scaffold(
          appBar: AppBar(title: const Text('Your take')), body: Padding(padding: const EdgeInsets.all(SaSpace.s5),
            child: CleanCutPanel(plan: clean, busy: false, onChanged: (_, _) {}, onRestore: () {}))), [notes], brightness: brightness);
      });
    }
    for (final (name, size, brightness) in [('desktop', desktop, Brightness.light), ('dark', desktop, Brightness.dark), ('phone', phone, Brightness.light)]) {
      testWidgets('take review $language $name', (tester) async {
        final take = Take(path: 'generated.mp4', recordedAt: DateTime(2026), duration: const Duration(seconds: 3));
        final spoken = reviewFixture(language, take);
        await shoot(tester, 'take-review-${language.name}-$name', size, (app) {
          app.speech.result = spoken; app.speechModels.phase = SpeechModelPhase.ready;
          return TakeReviewScreen(script: spoken.snapshot!, take: take);
        }, [spoken.snapshot!], brightness: brightness);
      });
    }
  }

  for (final language in ScriptLanguage.values) {
    final notes = ScriptDocument.create(language: language, title: language == ScriptLanguage.ar ? 'حديثي القادم' : 'My next talk')
      .copyWith(recordingAid: RecordingAid.notes, notes: fixtureNotes(language));
    for (final (name, size) in [('desktop', desktop), ('phone', phone)]) {
      testWidgets('notes editor $language $name', (tester) async {
        await shoot(tester, 'notes-editor-${language.name}-$name', size, (_) => NotesEditorScreen(script: notes), [notes]);
      });
    }
    testWidgets('notes practice $language', (tester) async {
      await shoot(tester, 'notes-practice-${language.name}', phone, (_) => NotesPracticeScreen(script: notes), [notes]);
    });
    for (final (name, size) in [('default', const Size(720, 360)), ('minimum', const Size(640, 280))]) {
      testWidgets('notes floating $language $name', (tester) async {
        await shoot(tester, 'notes-floating-${language.name}-$name', size,
          (_) => FloatingPrompterScreen(presentation: FloatingPresentation(script: notes)), [notes]);
      });
    }
    testWidgets('notes setup $language', (tester) async {
      CameraPlatform.instance = _NoCameras();
      await shoot(tester, 'notes-record-${language.name}', desktop, (_) => RecordScreen(script: notes), [notes], settle: false,
        before: (tester) async { await tester.pump(const Duration(milliseconds: 300)); });
    });
  }

  // The Home screen: a director's desk, with scripts marked up and a few takes.
  Future<List<ScriptDocument>> desk() async {
    final now = DateTime.now();
    final scripts = [for (final s in sampleScripts()) await _markedUp(s)];
    return [
      scripts[0].copyWith(takes: [
        Take(path: 'take1.mp4', recordedAt: now.subtract(const Duration(days: 2)), duration: const Duration(seconds: 40)),
        Take(path: 'take2.mp4', recordedAt: now.subtract(const Duration(hours: 3)), duration: const Duration(seconds: 36)),
      ]),
      scripts[1].copyWith(takes: [
        Take(path: 'take3.mp4', recordedAt: now.subtract(const Duration(days: 1)), duration: const Duration(minutes: 1, seconds: 12)),
      ]),
      scripts[2],
    ];
  }

  for (final (name, size, brightness) in [
    ('home', desktop, Brightness.light),
    ('home-dark', desktop, Brightness.dark),
    ('home-phone', phone, Brightness.light),
  ]) {
    testWidgets('home ($name)', (tester) async {
      final scripts = await desk();
      await shoot(tester, name, size, (_) => const HomeScreen(), scripts, brightness: brightness);
    });
  }

  testWidgets('home, first run', (tester) async {
    await shoot(tester, 'home-empty', phone, (_) => const HomeScreen(), []);
  });

  testWidgets('library', (tester) async {
    await shoot(tester, 'library', phone, (_) => const LibraryScreen(), sampleScripts());
  });

  testWidgets('library, empty', (tester) async {
    await shoot(tester, 'library-empty', phone, (_) => const LibraryScreen(), []);
  });

  testWidgets('mark sheet', (tester) async {
    final script = await _markedUp(sampleScripts()[0]);
    await shoot(tester, 'mark-sheet', phone, (_) => EditorScreen(script: script), [script], before: (tester) async {
      // "12,000": a stressed word whose mark carries the director's note.
      final page = tester.renderObject<RenderScriptPage>(find.byType(ScriptPage));
      final start = page.plainText.indexOf('12,000');
      await tester.tapAt(page.localToGlobal(page.rectOf(start, start + 6)!.center));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('prompter, voice pacing with the word guide', (tester) async {
    final script = await _markedUp(sampleScripts()[0]);
    await shoot(tester, 'prompter-en-voice', phone, (_) => PrompterScreen(script: script), [script],
        audio: _TalkingMic(), settle: false, before: (tester) async {
      await tester.pump(const Duration(milliseconds: 300));
      final controller = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
      expect(controller.mode, ScrollMode.voice);
      controller.seekToToken(12);
      controller.play();
      await tester.pump();
      // Half-way through the word.
      final word = controller.timeline.endOf(12) - controller.timeline.startOf(12);
      await tester.pump(word * 0.5);
      controller.pause();
      await tester.pump(const Duration(milliseconds: 250));
    });
  });

  testWidgets('prompter, still', (tester) async {
    final script = await _markedUp(sampleScripts()[0]);
    await shoot(tester, 'prompter-en-still', phone, (app) {
      app.settings.kinetic = false;
      return PrompterScreen(script: script);
    }, [script], before: (tester) async {
      tester.widget<PrompterView>(find.byType(PrompterView)).controller.seekToToken(9);
      await tester.pumpAndSettle();
    });
  });

  // Each guide on a Windows-sized window, half-way through the word before
  // "12,000", with the whole control bar.
  for (final guide in PrompterGuide.values) {
    testWidgets('prompter, ${guide.name} guide', (tester) async {
      final script = await _markedUp(sampleScripts()[0]);
      await shoot(tester, 'prompter-guide-${guide.name}', desktop, (app) {
        app.settings.guide = guide;
        return PrompterScreen(script: script);
      }, [script], settle: false, before: (tester) async {
        await tester.pump(const Duration(milliseconds: 300));
        final controller = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
        final word = controller.tokens.indexWhere((t) => t.text == '12,000') - 1;
        controller.seekToToken(word);
        controller.play();
        await tester.pump();
        await tester.pump((controller.timeline.startOf(word + 1) - controller.timeline.startOf(word)) * 0.5);
        controller.pause();
        await tester.pump(const Duration(milliseconds: 250));
      });
    });
  }

  // One phrase motion, in English on a desktop and in Arabic on a phone.
  for (final language in ScriptLanguage.values) {
    for (final alignment in PrompterAlignment.values) {
      testWidgets('prompter, alignment ${language.name} ${alignment.name}', (tester) async {
        final script = cueCheckScript(language);
        await shoot(tester, 'prompter-align-${language.name}-${alignment.name}', desktop, (app) {
          app.settings.alignment = alignment;
          return PrompterScreen(script: script);
        }, [script]);
      });
    }
  }

  for (final language in ScriptLanguage.values) {
    for (final arriving in [false, true]) {
      final side = arriving ? 'arrive' : 'leave';
      testWidgets('prompter, line return ${language.name} $side', (tester) async {
        final script = cueCheckScript(language);
        await shoot(tester, 'prompter-line-${language.name}-$side', desktop,
            (_) => PrompterScreen(script: script), [script], settle: false, before: (tester) async {
          await tester.pump(const Duration(milliseconds: 300));
          final c = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
          final last = c.tokens.indexWhere((t) => t.endsParagraph);
          c.seekToToken(last);
          await tester.pumpAndSettle();
          final target = c.timeline.startOf(last + 1) + Duration(milliseconds: arriving ? 60 : -60);
          c.play();
          await tester.pump();
          await tester.pump(target - c.position);
          c.pause();
          await tester.pump();
        });
      });
    }
  }

  for (final (name, index, size) in [('en', 0, desktop), ('ar', 2, phone)]) {
    testWidgets('prompter, one phrase ($name)', (tester) async {
      final script = await _markedUp(sampleScripts()[index]);
      await shoot(tester, 'prompter-phrase-$name', size, (app) {
        app.settings.motion = PrompterMotion.phrase;
        return PrompterScreen(script: script);
      }, [script], settle: false, before: (tester) async {
        await tester.pump(const Duration(milliseconds: 300));
        final controller = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
        controller.seekToToken(6);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        controller.play();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        controller.pause();
        await tester.pump();
      });
    });
  }

  for (final language in ScriptLanguage.values) {
    testWidgets('prompter, one phrase stays bright ${language.name}', (tester) async {
      final script = cueCheckScript(language);
      await shoot(tester, 'prompter-phrase-bright-${language.name}', desktop, (app) {
        app.settings.motion = PrompterMotion.phrase;
        app.settings.alignment = PrompterAlignment.center;
        return PrompterScreen(script: script);
      }, [script], before: (tester) async {
        final c = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
        c.play();
        await tester.pump();
        await tester.pump(c.timeline.startOf(2));
        c.pause();
        await tester.pumpAndSettle();
      });
    });
  }

  // The dot acting out each cue in the English sample: landing on a
  // stressed word, as the pause sign, inhaling, and announcing a run.
  final dotMoments = <String, Duration Function(PrompterController)>{
    'stress': (c) => c.timeline.startOf(c.tokens.indexWhere((t) => t.text == '12,000')) + const Duration(milliseconds: 60),
    'pause': (c) {
      final m = c.marks.firstWhere((m) => m.kind == MarkKind.pauseShort || m.kind == MarkKind.pauseLong);
      return c.timeline.endOf(m.end) + const Duration(milliseconds: 260);
    },
    'breath': (c) {
      final m = c.marks.firstWhere((m) => m.kind == MarkKind.breath);
      final (start, end) = c.timeline.holdAt(c.timeline.endOf(m.end) + const Duration(milliseconds: 1))!;
      return start + (end - start) * 0.5;
    },
    'announce': (c) {
      final m = c.marks.firstWhere((m) => m.kind == MarkKind.energy);
      return c.timeline.startOf(m.start) + const Duration(milliseconds: 180);
    },
  };
  for (final moment in dotMoments.entries) {
    testWidgets('prompter, the dot acts out: ${moment.key}', (tester) async {
      var script = await _markedUp(sampleScripts()[0]);
      if (!script.marks.any((m) => m.kind == MarkKind.breath)) {
        // The sample has no breath: add one after "before,".
        final after = script.tokens.indexWhere((t) => t.text == 'before,');
        script = script.copyWith(
          marks: normalizeMarks([...script.marks, Mark.gap(id: 'breath', kind: MarkKind.breath, after: after)], script.tokens.length),
        );
      }
      await shoot(tester, 'prompter-dot-${moment.key}', phone, (_) => PrompterScreen(script: script), [script],
          settle: false, before: (tester) async {
        await tester.pump(const Duration(milliseconds: 300));
        final controller = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
        final target = moment.value(controller);
        // Start a little before, so the view has settled on the line.
        final token = controller.timeline.tokenAt(target);
        controller.seekToToken(token);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        controller.play();
        await tester.pump();
        await tester.pump(target - controller.position);
        controller.pause();
        await tester.pump();
      });
    });
  }

  // The record set-up on a Windows-sized window: every microphone metered,
  // and the panel that appears when Windows blocks the microphone.
  for (final (name, denied) in [('record-desktop', false), ('record-desktop-blocked', true)]) {
    testWidgets('record screen, desktop set-up ($name)', (tester) async {
      CameraPlatform.instance = _NoCameras();
      final script = await _markedUp(sampleScripts()[0]);
      await shoot(tester, name, desktop, (_) => RecordScreen(script: script), [script],
          audio: _TalkingMic(denied: denied), settle: false, before: (tester) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      });
    });
  }

  for (final (index, language) in [(0, 'en'), (1, 'fr'), (2, 'ar')]) {
    for (final (computerSound, activity) in [(false, false), (true, false), (false, true)]) {
    testWidgets('Screen recording setup $language computerSound=$computerSound activity=$activity', (tester) async {
      final script = await _markedUp(sampleScripts()[index]);
      await shoot(tester, 'record-screen-setup-$language${computerSound ? '-computer-sound' : ''}${activity ? '-activity' : ''}', desktop, (services) {
        services.settings.recordMode = TakeMode.screen;
        // No native recorder command is made by this setup-only screenshot.
        return AppScope(services: AppServices(library: services.library, settings: services.settings,
          recordingsDir: Directory.systemTemp, audio: _TalkingMic(), recorder: const WindowsScreenRecordings(),
          screens: _ScreenCandidates(script.displayTitle)), child: RecordScreen(script: script));
      }, [script], settle: false, before: (tester) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        if (activity) {
          await tester.scrollUntilVisible(find.byType(ActivityChoice), 200,
            scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
          await tester.pumpAndSettle();
          await tester.tap(find.descendant(of: find.byType(ActivityChoice), matching: find.byType(Switch)));
          await tester.pumpAndSettle();
        }
        if (computerSound) {
          await tester.scrollUntilVisible(find.byType(ComputerSoundChoice), 200,
            scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
          await tester.pumpAndSettle();
          await tester.tap(find.descendant(of: find.byType(ComputerSoundChoice), matching: find.byType(Switch)));
          await tester.pumpAndSettle();
        }
      });
    });
    }
  }

  for (final (language, name) in [('en', 'My presentation'), ('fr', 'Présentation française'), ('ar', 'عرض تقديمي')]) {
    testWidgets('screen source picker $language', (tester) async {
      await shoot(tester, 'screen-sources-$language', desktop,
        (_) => ScreenSourcePicker(sources: _ScreenCandidates(name)), []);
    });
  }

  for (final (index, language, name) in [(0, 'en', 'Chosen camera'), (1, 'fr', 'Caméra choisie'), (2, 'ar', 'الكاميرا المختارة')]) {
    testWidgets('Both recording setup $language', (tester) async {
      final original = CameraPlatform.instance;
      // ignore: invalid_use_of_visible_for_testing_member
      CameraPlatform.instance = PreviewCamera(name);
      addTearDown(() {
        // ignore: invalid_use_of_visible_for_testing_member
        CameraPlatform.instance = original;
      });
      final script = await _markedUp(sampleScripts()[index]);
      await shoot(tester, 'record-both-setup-$language', desktop, (services) {
        services.settings.recordMode = TakeMode.both;
        return AppScope(services: AppServices(library: services.library, settings: services.settings,
          recordingsDir: Directory.systemTemp, audio: _TalkingMic(), recorder: const WindowsScreenRecordings(),
          bubbles: const WindowsCameraBubbles(), previews: const _ClosedScreenPreview(),
          screens: _ScreenCandidates(script.displayTitle)), child: RecordScreen(script: script));
      }, [script], settle: false, before: (tester) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Choose screen').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(script.displayTitle));
        await tester.pump();
        await tester.tap(find.text('Use this source'));
        await tester.pumpAndSettle();
      });
    });
  }

  for (final (language, name) in [('en', 'My presentation'), ('fr', 'Présentation française'), ('ar', 'عرض تقديمي')]) {
    testWidgets('screen preview, closed source $language', (tester) async {
      await shoot(tester, 'screen-preview-closed-$language', desktop,
        (_) => ScreenPreviewScreen(previews: const _ClosedScreenPreview(), source: ScreenSource(
          id: 'window:test', name: name, kind: ScreenSourceKind.window, width: 1280, height: 720)), []);
    });
  }

  for (final language in ScriptLanguage.values) {
    for (final (sizeName, size) in [
      ('default', Size(SaPrompter.floatingWidth, SaPrompter.floatingHeight)),
      ('minimum', Size(SaPrompter.floatingMinWidth, SaPrompter.floatingMinHeight)),
    ]) {
      testWidgets('floating prompter ${language.name}, $sizeName', (tester) async {
        final script = cueCheckScript(language);
        await shoot(tester, 'floating-prompter-${language.name}-$sizeName', size,
          (_) => FloatingPrompterScreen(presentation: FloatingPresentation(script: script)), [script]);
      });
    }
    for (final camera in [false, true]) {
      testWidgets('cursor companion ${language.name}, camera $camera', (tester) async {
        final script = cueCheckScript(language);
        await shoot(tester, 'cursor-companion-${language.name}-${camera ? 'camera' : 'screen'}',
          Size(SaPrompter.companionWidth, SaPrompter.companionHeight),
          (_) => FloatingPrompterScreen(presentation: FloatingPresentation(script: script),
            initialPlacement: CompanionPlacement(enabled: true, follow: true, camera: camera)), [script]);
      });
    }
    testWidgets('docked companion ${language.name}', (tester) async {
      final script = cueCheckScript(language);
      await shoot(tester, 'cursor-companion-${language.name}-docked',
        Size(SaPrompter.companionWidth, SaPrompter.companionHeight),
        (_) => FloatingPrompterScreen(presentation: FloatingPresentation(script: script),
          initialPlacement: const CompanionPlacement(enabled: true, camera: true)), [script]);
    });
  }

  for (final (language, microphone) in [('en', 'Wireless microphone'), ('fr', 'Microphone sans fil'), ('ar', 'ميكروفون لاسلكي')]) {
    testWidgets('camera companion choice $language', (tester) async {
      await shoot(tester, 'companion-choice-$language', Size(SaPrompter.hudWidth, SaPrompter.hudQuestionHeight),
        (_) => RecordingHudScreen(initial: HudState(phase: HudPhase.recording, camera: true,
          companionQuestion: true, microphone: microphone)), []);
    });
    for (final phase in [HudPhase.recording, HudPhase.paused, HudPhase.countdown]) {
      testWidgets('recording HUD $language ${phase.name}', (tester) async {
        final size = phase == HudPhase.countdown ? Size.square(SaPrompter.countdownWindowSize)
          : Size(SaPrompter.hudWidth, SaPrompter.hudHeight);
        await shoot(tester, 'recording-hud-$language-${phase.name}', size,
          (_) => RecordingHudScreen(initial: HudState(phase: phase, microphone: microphone,
            duration: const Duration(seconds: 8), peakDb: -9)), []);
      });
    }
  }

  testWidgets('recording HUD with computer sound only', (tester) async {
    await shoot(tester, 'recording-hud-computer-sound-only', Size(SaPrompter.hudWidth, SaPrompter.hudHeight),
      (_) => const RecordingHudScreen(initial: HudState(phase: HudPhase.recording,
        recordAudio: false, recordSystemAudio: true, duration: Duration(seconds: 8))), []);
  });

  testWidgets('record screen, no camera', (tester) async {
    CameraPlatform.instance = _NoCameras();
    final script = await _markedUp(sampleScripts()[0]);
    await shoot(tester, 'record-no-camera', phone, (_) => RecordScreen(script: script), [script]);
  });

  for (final (language, name) in [('en', 'Chosen camera'), ('fr', 'Caméra choisie'), ('ar', 'الكاميرا المختارة')]) {
    for (final live in [false, true]) {
      testWidgets('camera bubble $language $live', (tester) async {
        await shoot(tester, 'camera-bubble-$language-${live ? 'live' : 'waiting'}',
          Size.square(SaPrompter.cameraBubbleSize),
          (_) => CameraBubbleScreen(initial: CameraBubbleState(name: name,
            live: live, textureId: 1, width: 1280, height: 720),
            preview: ColoredBox(color: SaPalette.dark.stageTintSlower)), []);
      });
    }
  }

  for (final (name, at) in [('countdown-landing', 70), ('countdown', 700)]) {
    testWidgets(name, (tester) async {
      await shoot(tester, name, const Size(300, 260), (_) {
        return Scaffold(backgroundColor: SaPalette.dark.stage, body: const Center(child: CountdownNumeral(value: 3)));
      }, [], settle: false, before: (tester) async => tester.pump(Duration(milliseconds: at)));
    });
  }

  testWidgets('library dark', (tester) async {
    await shoot(tester, 'library-dark', phone, (_) => const LibraryScreen(), sampleScripts(),
        brightness: Brightness.dark);
  });

  for (final provider in [MarkupProvider.ollama, MarkupProvider.gemini]) {
    testWidgets('settings ${provider.name}', (tester) async {
      await shoot(tester, 'settings-${provider.name}', phone, (app) {
        app.settings.provider = provider;
        return const SettingsScreen();
      }, []);
    });
  }

  for (final (i, name) in ['en-presentation', 'fr-tutorial', 'ar-social'].indexed) {
    testWidgets('editor $name, marks pending', (tester) async {
      final script = await _markedUp(sampleScripts()[i], accept: false);
      await shoot(tester, 'editor-$name', desktop, (_) => EditorScreen(script: script), [script]);
    });

    testWidgets('editor $name, dark', (tester) async {
      final script = await _markedUp(sampleScripts()[i]);
      await shoot(tester, 'editor-$name-dark', desktop, (_) => EditorScreen(script: script), [script],
          brightness: Brightness.dark);
    });

    testWidgets('editor $name on a phone', (tester) async {
      final script = await _markedUp(sampleScripts()[i]);
      await shoot(tester, 'editor-$name-phone', phone, (_) => EditorScreen(script: script), [script]);
    });

    testWidgets('prompter $name, kinetic in a hold', (tester) async {
      final script = await _markedUp(sampleScripts()[i]);
      await shoot(tester, 'prompter-$name-hold', phone, (_) => PrompterScreen(script: script), [script],
          before: (tester) async {
        final controller = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
        // The second pause or breath: play into it, so its glyph hits and the ring runs.
        final gaps = controller.marks.where((m) => m.kind.isGap).toList();
        final gap = gaps[gaps.length > 1 ? 1 : 0];
        controller.seekToToken(gap.end);
        controller.play();
        await tester.pump();
        await tester.pump(controller.timeline.endOf(gap.end) - controller.timeline.startOf(gap.end) +
            const Duration(milliseconds: 120));
        controller.pause();
        // Let the hold badge fade in.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      });
    });

    testWidgets('prompter $name', (tester) async {
      final script = await _markedUp(sampleScripts()[i]);
      await shoot(tester, 'prompter-$name', phone, (_) => PrompterScreen(script: script), [script],
          before: (tester) async {
        // Play into the script so the scroll and a pause show.
        final controller = tester.widget<PrompterView>(find.byType(PrompterView)).controller;
        controller.seekToToken(9);
        await tester.pumpAndSettle();
      });
    });
  }
}

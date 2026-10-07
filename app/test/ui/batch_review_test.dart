import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/caption_style.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/take_review_screen.dart';
import 'package:spawnalpha/src/ui/video_export_panel.dart';

import '../render/export_batch_test.dart' show BatchRenderer;
import '../storage/screen_take_store_test.dart' show FakeInspector;
import '../transcription/speech_processor_test.dart' show FakeSpeech;
import '../playback/playback_controller_test.dart' show FakePlayback;
import 'take_review_test.dart' show reviewFixture;

class AttachInspector extends FakeInspector {
  bool hold = false;
  final attaching = Completer<void>(), release = Completer<void>();
  @override
  Future<RecordingInfo> inspect(String path) async {
    if (hold &&
        path.contains('exports${Platform.pathSeparator}') &&
        path.endsWith('.mp4')) {
      if (!attaching.isCompleted) attaching.complete();
      await release.future;
    }
    return super.inspect(path);
  }
}

void main() {
  for (final language in ScriptLanguage.values) {
    for (final outcome in ['done', 'cancel', 'saving', 'failed']) {
      testWidgets('saved review batch $outcome $language', (tester) async {
        tester.view.physicalSize = const Size(1280, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late Directory root;
        late ScriptLibrary library;
        late AppServices services;
        late ScriptDocument script;
        late Take take;
        late BatchRenderer renderer;
        late AttachInspector inspector;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp(
            'spawnalpha-batch-review-',
          );
          library = ScriptLibrary(MemoryScriptStore());
          inspector = AttachInspector()..hold = outcome == 'saving';
          renderer = BatchRenderer(inspector);
          if (outcome == 'cancel') renderer.holdAt = 2;
          if (outcome == 'failed') renderer.failAt = 2;
          services = AppServices(
            library: library,
            settings: Settings(secrets: MemorySecretStore()),
            recordingsDir: Directory('${root.path}/recordings'),
            inspector: inspector,
            playback: FakePlayback(),
            speechBackend: FakeSpeech('unused'),
            renderer: renderer,
          );
          await services.speech.results.create(recursive: true);
          final source = File('${root.path}/generated.mp4');
          await source.writeAsString('generated source bytes');
          take = Take(
            path: source.path,
            wordsPath: '${services.speech.results.path}/generated.json',
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 4),
          );
          final words = reviewFixture(
            language,
            take,
            notes: language == ScriptLanguage.fr,
          );
          script = words.snapshot!.copyWith(takes: [take]);
          await File(take.wordsPath!).writeAsString(jsonEncode(words.toJson()));
          await library.save(script);
          services.speech.result = words;
          await tester.pumpWidget(
            AppScope(
              services: services,
              child: MaterialApp(
                theme: buildTheme(Brightness.light),
                home: TakeReviewScreen(script: script, take: take),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        final more = find.widgetWithText(
          CheckboxListTile,
          'Also save other formats',
        );
        await tester.ensureVisible(more);
        await tester.tap(more);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilterChip, VideoFormat.feed.label),
        );
        await tester.pumpAndSettle();
        expect(find.text('Save 2 videos'), findsOneWidget);
        final panel = tester.widget<VideoExportPanel>(
          find.byType(VideoExportPanel),
        );
        expect(panel.extraFormats, {VideoFormat.feed});
        expect(panel.captionStyle, CaptionStyle.cue);
        await tester.runAsync(() async {
          await tester.tap(find.text('Save 2 videos'));
          if (outcome == 'cancel') {
            await renderer.held.future;
          } else if (outcome == 'saving') {
            await inspector.attaching.future;
          } else {
            for (var i = 0; i < 100 && panel.batch!.busy; ++i) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          }
        });
        if (outcome == 'cancel' || outcome == 'saving') {
          await tester.pump();
          expect(tester.widget<CheckboxListTile>(more).onChanged, isNull);
          expect(
            find.textContaining(
              outcome == 'saving'
                  ? 'Saving video 1 of 2'
                  : 'Making video 2 of 2',
            ),
            findsOneWidget,
          );
          await tester.runAsync(() async {
            await tester.tap(
              find.text(
                outcome == 'saving' ? 'Stop after this video' : 'Cancel export',
              ),
            );
            if (outcome == 'saving') inspector.release.complete();
            for (var i = 0; i < 100 && panel.batch!.busy; ++i) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          });
        }
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        final count = outcome == 'done' ? 2 : 1;
        expect(
          find.textContaining('$count of 2 videos saved.'),
          findsOneWidget,
        );
        expect(
          tester.widget<VideoExportPanel>(find.byType(VideoExportPanel)).videos,
          hasLength(count),
        );
        expect(renderer.requests, hasLength(outcome == 'saving' ? 1 : 2));
        expect(
          renderer.requests.every((r) => r.captionStyle == CaptionStyle.cue),
          isTrue,
        );
        expect(renderer.maximum, 1);
        await tester.runAsync(() async {
          expect(
            await services.videoExports.load(
              library.byId(script.id)!.takes.single,
            ),
            hasLength(count),
          );
          expect(
            await File(take.path).readAsString(),
            'generated source bytes',
          );
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        services.processing.dispose();
        services.speech.dispose();
        services.speechModels.dispose();
        services.exports.dispose();
        library.dispose();
        await tester.runAsync(() => root.delete(recursive: true));
      });
    }
  }
}

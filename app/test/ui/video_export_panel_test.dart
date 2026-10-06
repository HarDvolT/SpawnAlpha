import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/video_export_panel.dart';

import '../render/export_processor_test.dart' show FakeRenderer;
import '../storage/screen_take_store_test.dart' show FakeInspector;

void main() {
  testWidgets('format, camera and saved-video controls fit a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = ScriptLibrary(MemoryScriptStore()),
        inspector = FakeInspector();
    final job = ExportProcessor(
      FakeRenderer(inspector),
      VideoExportStore(Directory.systemTemp, library, inspector),
      CleanCutStore(Directory.systemTemp, library),
      (_) async => null,
    );
    final video = VideoExport(
      id: 'generated',
      format: VideoFormat.feed,
      duration: const Duration(seconds: 3),
      createdAt: DateTime(2026),
    );
    var viewed = false, shown = false, saved = false, camera = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: VideoExportPanel(
            format: VideoFormat.portrait,
            onFormat: (_) {},
            onExport: () => saved = true,
            job: job,
            busy: false,
            supported: true,
            videos: [video],
            onView: (_) => viewed = true,
            onShow: (_) => shown = true,
            hasCamera: true,
            onCamera: (value) => camera = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save video'));
    await tester.tap(find.text('Watch saved video'));
    await tester.tap(find.text('Show saved files'));
    await tester.tap(find.byType(Checkbox));
    expect(camera, isFalse);
    expect([saved, viewed, shown], everyElement(isTrue));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    job.dispose();
    library.dispose();
  });
  testWidgets('older exports stay accessible during a new export', (
    tester,
  ) async {
    final library = ScriptLibrary(MemoryScriptStore()),
        inspector = FakeInspector();
    final job =
        ExportProcessor(
            FakeRenderer(inspector),
            VideoExportStore(Directory.systemTemp, library, inspector),
            CleanCutStore(Directory.systemTemp, library),
            (_) async => null,
          )
          ..phase = ExportPhase.rendering
          ..progress = .4;
    final videos = [
      for (var i = 0; i < 9; ++i)
        VideoExport(
          id: 'generated-$i',
          format: VideoFormat.landscape,
          duration: const Duration(seconds: 3),
          createdAt: DateTime(2026),
        ),
    ];
    String? viewed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: VideoExportPanel(
              format: VideoFormat.landscape,
              onFormat: (_) {},
              onExport: () {},
              job: job,
              busy: true,
              supported: true,
              videos: videos,
              onView: (video) => viewed = video.id,
              onShow: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Cancel export'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .4,
    );
    await tester.ensureVisible(find.text('Earlier saved videos'));
    await tester.tap(find.text('Earlier saved videos'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Watch saved video').last);
    await tester.tap(find.text('Watch saved video').last);
    expect(viewed, 'generated-8');
    await tester.pumpWidget(const SizedBox());
    job.dispose();
    library.dispose();
  });
}

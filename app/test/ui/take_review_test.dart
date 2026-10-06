import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/app.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/settings.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/transcription/speech_models.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';
import 'package:spawnalpha/src/transcription/take_processing.dart';
import 'package:spawnalpha/src/ui/take_review_screen.dart';
import 'package:spawnalpha/src/playback/local_playback.dart';

import '../cut/filler_review_test.dart'
    show fillerFixture, fillerPlan, fillerScript;
import '../playback/playback_controller_test.dart' show FakePlayback;

import '../transcription/speech_processor_test.dart' show FakeSpeech;
import '../review/repeated_sections_test.dart'
    show repeatedScript, repeatedSpeech;
import '../cut/retake_review_test.dart'
    show retakeWords, retakeScript, retakeQuiet;

SavedTranscript reviewFixture(
  ScriptLanguage language,
  Take take, {
  bool notes = false,
}) {
  final text = switch (language) {
    ScriptLanguage.en => 'Hello everyone.',
    ScriptLanguage.fr => 'Bonjour à tous.',
    ScriptLanguage.ar => 'مرحبا بكم اليوم.',
  };
  final script = ScriptDocument.create(
    text: text,
    language: language,
  ).copyWith(recordingAid: notes ? RecordingAid.notes : RecordingAid.script);
  var start = 200000;
  return SavedTranscript(
    sourcePath: take.path,
    snapshot: script,
    transcript: WordTranscript(
      language: language,
      duration: take.duration,
      words: [
        for (final word in text.split(' '))
          SpokenWord(
            text: word,
            start: Duration(microseconds: start),
            end: Duration(microseconds: start += 300000),
          ),
      ],
    ),
    alignment: notes
        ? null
        : {
            'missedTokens': [1],
            'words': [
              {'match': 'changed'},
            ],
          },
  );
}

void main() {
  for (final language in ScriptLanguage.values) {
    testWidgets(
      'whole review persists and restores a retake choice $language',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late Directory root;
        late ScriptLibrary library;
        late AppServices services;
        late ScriptDocument script;
        late Take take;
        final words = retakeWords(language), frozen = retakeScript(language);
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp(
            'spawnalpha-retake-review-',
          );
          library = ScriptLibrary(MemoryScriptStore());
          take = Take(
            path: '${root.path}/generated.mp4',
            recordedAt: DateTime(2026),
            duration: words.duration,
            wordsPath: '${root.path}/words.json',
          );
          script = frozen.copyWith(takes: [take]);
          await library.save(script);
          services = AppServices(
            library: library,
            settings: Settings(secrets: MemorySecretStore()),
            recordingsDir: root,
            playback: FakePlayback(),
            speechBackend: FakeSpeech('unused'),
          );
          services.speech.result = SavedTranscript(
            sourcePath: take.path,
            transcript: words,
            snapshot: frozen,
            quiet: retakeQuiet(words),
            alignment: {'attemptCount': 2},
          );
          final plan = await services.cuts.create(
            script,
            take,
            services.speech.result!,
          );
          take = library.byId(script.id)!.takes.single;
          expect(plan.retakes.single.selected, isNull);
        });
        await tester.runAsync(() async {
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
        for (
          var i = 0;
          i < 40 && find.text('Keep attempt 2').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
        }
        expect(find.text('Keep attempt 2'), findsOneWidget);
        await tester.ensureVisible(find.text('Keep attempt 2'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Keep attempt 2'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.text('Removed from cut'), findsOneWidget);
        expect(
          (await tester.runAsync(
            () => services.cuts.load(library.byId(script.id)!.takes.single),
          ))!.retakes.single.selected,
          1,
        );
        await tester.ensureVisible(find.text('Restore all changes'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Restore all changes'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(
          (await tester.runAsync(
            () => services.cuts.load(library.byId(script.id)!.takes.single),
          ))!.retakes.single.selected,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        services.processing.dispose();
        services.speech.dispose();
        services.speechModels.dispose();
        library.dispose();
        await tester.runAsync(() => root.delete(recursive: true));
      },
    );
    testWidgets(
      'comparison uses the frozen script and hears an original attempt $language',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final snapshot = repeatedScript(language),
            words = repeatedSpeech(repeatedScript(language));
        final take = Take(
          path: 'generated.mp4',
          recordedAt: DateTime(2026),
          duration: words.duration,
        );
        final script = snapshot
            .withText('A later library edit.')
            .copyWith(takes: [take]);
        final library = ScriptLibrary(MemoryScriptStore());
        await library.save(script);
        final backend = FakePlayback()
          ..value = PlaybackStatus(
            ready: true,
            width: 640,
            height: 360,
            duration: words.duration,
          );
        final services = AppServices(
          library: library,
          settings: Settings(secrets: MemorySecretStore()),
          recordingsDir: Directory.systemTemp,
          playback: backend,
          speechBackend: FakeSpeech('unused'),
        );
        services.speech.result = SavedTranscript(
          sourcePath: take.path,
          snapshot: snapshot,
          transcript: words,
          alignment: {'attemptCount': 2, 'words': []},
        );
        await tester.pumpWidget(
          AppScope(
            services: services,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: TakeReviewScreen(script: script, take: take),
            ),
          ),
        );
        for (
          var i = 0;
          i < 40 && find.text('Compare attempts').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
        }
        expect(find.text('Compare attempts'), findsOneWidget);
        expect(find.text(snapshot.text), findsWidgets);
        expect(backend.commands, isEmpty);
        await tester.ensureVisible(find.text('Hear attempt 2'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hear attempt 2'));
        await tester.pumpAndSettle();
        expect(backend.commands, [
          'pause',
          'seek:2100000',
          'mute:false',
          'play',
        ]);
        expect(find.text('Original take · Phrase preview'), findsOneWidget);
        expect(library.byId(script.id)!.takes.single.cutPath, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        services.processing.dispose();
        services.speech.dispose();
        services.speechModels.dispose();
        library.dispose();
      },
    );
    for (final notes in [false, true]) {
      testWidgets(
        'free speech never gets script attempt comparison $language Notes=$notes',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final snapshot = repeatedScript(language).copyWith(
            recordingAid: notes ? RecordingAid.notes : RecordingAid.script,
          );
          final words = repeatedSpeech(snapshot);
          final take = Take(
            path: 'generated.mp4',
            recordedAt: DateTime(2026),
            duration: words.duration,
          );
          final library = ScriptLibrary(MemoryScriptStore());
          final script = snapshot.copyWith(takes: [take]);
          await library.save(script);
          final services = AppServices(
            library: library,
            settings: Settings(secrets: MemorySecretStore()),
            recordingsDir: Directory.systemTemp,
            speechBackend: FakeSpeech('unused'),
          );
          services.speech.result = SavedTranscript(
            sourcePath: take.path,
            snapshot: snapshot,
            transcript: words,
            alignment: notes ? {'attemptCount': 2} : null,
          );
          await tester.pumpWidget(
            AppScope(
              services: services,
              child: MaterialApp(
                theme: buildTheme(Brightness.light),
                home: TakeReviewScreen(script: script, take: take),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Compare attempts'), findsNothing);
          expect(find.text('Comparing repeated sections…'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          services.processing.dispose();
          services.speech.dispose();
          services.speechModels.dispose();
          library.dispose();
        },
      );
    }
    testWidgets(
      'hearing a filler reveals original player without changing the cut $language',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final words = fillerFixture(language),
            plan = fillerPlan(fillerFixture(language));
        final backend = FakePlayback();
        late ScriptLibrary library;
        late Directory root;
        late Take take;
        late ScriptDocument script;
        late AppServices services;
        await tester.runAsync(() async {
          library = ScriptLibrary(MemoryScriptStore());
          root = await Directory.systemTemp.createTemp('spawnalpha-listen-');
          take = Take(
            path: '${root.path}/generated.mp4',
            recordedAt: DateTime(2026),
            duration: words.duration,
            wordsPath: '${root.path}/words.json',
          );
          script = fillerScript(words).copyWith(takes: [take]);
          await library.save(script);
          services = AppServices(
            library: library,
            settings: Settings(secrets: MemorySecretStore()),
            recordingsDir: root,
            playback: backend,
            speechBackend: FakeSpeech('unused'),
          );
          services.speech.result = SavedTranscript(
            sourcePath: take.path,
            transcript: words,
            snapshot: script,
          );
          await services.cuts.save(script.id, take, plan);
          take = library.byId(script.id)!.takes.single;
          expect(await services.cuts.load(take), isNotNull);
        });
        await tester.runAsync(() async {
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
        await tester.scrollUntilVisible(
          find.text('Hear this phrase'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Hear this phrase'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hear this phrase'));
        await tester.pumpAndSettle();
        expect(backend.commands, [
          'pause',
          'seek:200000',
          'mute:false',
          'play',
        ]);
        expect(find.text('Original take · Phrase preview'), findsOneWidget);
        expect(
          tester.getCenter(find.text('Original take · Phrase preview')).dy,
          inInclusiveRange(0, 900),
        );
        await tester.scrollUntilVisible(
          find.text('Hear this phrase'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          backend.closed,
          isEmpty,
          reason: 'The player survives scrolling',
        );
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.text('Original take · Phrase preview'), findsOneWidget);
        expect(
          backend.commands,
          hasLength(4),
          reason: 'Scrolling must not repeat a previous request',
        );
        expect(library.byId(script.id)!.takes.single.cutPath, take.cutPath);
        expect(plan.changes.single.enabled, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        services.processing.dispose();
        services.speech.dispose();
        services.speechModels.dispose();
        library.dispose();
        await tester.runAsync(() => root.delete(recursive: true));
      },
    );
    testWidgets('new take starts processing and keeps warning $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final take = Take(
        path: 'generated.mp4',
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 3),
      );
      final spoken = reviewFixture(language, take);
      final script = spoken.snapshot!.copyWith(takes: [take]);
      final library = ScriptLibrary(MemoryScriptStore());
      await library.save(script);
      final backend = FakeSpeech('unused')
        ..deferred = Completer<List<Object?>>();
      final services = AppServices(
        library: library,
        settings: Settings(secrets: MemorySecretStore()),
        recordingsDir: Directory.systemTemp,
        speechBackend: backend,
      );
      services.speechModels.phase = SpeechModelPhase.ready;
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: TakeReviewScreen(
              script: script,
              take: take,
              processAfterStop: true,
              fromRecording: true,
              recordingNotice:
                  'The camera stopped early. The screen recording is safe.',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(backend.started.isCompleted, isTrue);
      expect(find.textContaining('camera stopped early'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Record another'),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Cancel processing'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Cancel processing'));
      await tester.pumpAndSettle();
      expect(services.processing.phase, TakeProcessPhase.cancelled);
      expect(library.byId(script.id)!.takes.single.wordsPath, isNull);
      await tester.pumpWidget(const SizedBox());
      services.processing.dispose();
      services.speech.dispose();
      services.speechModels.dispose();
      library.dispose();
    });
    for (final notes in [false, true]) {
      testWidgets(
        'review keeps actual speech and aid policy $language Notes=$notes',
        (tester) async {
          tester.view.physicalSize = const Size(430, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final take = Take(
            path: 'generated.mp4',
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 3),
          );
          final spoken = reviewFixture(language, take, notes: notes),
              library = ScriptLibrary(MemoryScriptStore());
          final services = AppServices(
            library: library,
            settings: Settings(secrets: MemorySecretStore()),
            recordingsDir: Directory.systemTemp,
            speechBackend: FakeSpeech('unused'),
          );
          services.speech.result = spoken;
          services.speechModels.phase = SpeechModelPhase.ready;
          await tester.pumpWidget(
            AppScope(
              services: services,
              child: MaterialApp(
                theme: buildTheme(Brightness.light),
                home: TakeReviewScreen(script: spoken.snapshot!, take: take),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final transcript = find.byType(SelectableText);
          await tester.scrollUntilVisible(
            transcript,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            tester.widget<SelectableText>(transcript).data,
            spoken.transcript.words.map((w) => w.text).join(' '),
          );
          final direction = tester.widget<Directionality>(
            find
                .ancestor(of: transcript, matching: find.byType(Directionality))
                .first,
          );
          expect(
            direction.textDirection,
            language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          );
          expect(
            find.textContaining('differ from the script'),
            notes ? findsNothing : findsOneWidget,
          );
          expect(
            find.textContaining('script words were not found'),
            notes ? findsNothing : findsOneWidget,
          );
          expect(
            find.textContaining('free speech from Notes'),
            notes ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          services.speech.dispose();
          services.speechModels.dispose();
          library.dispose();
        },
      );
    }
  }
  testWidgets('cancel is visible during a job and preserves the original', (
    tester,
  ) async {
    final take = Take(
      path: 'generated.mp4',
      recordedAt: DateTime(2026),
      duration: const Duration(seconds: 3),
    );
    final library = ScriptLibrary(MemoryScriptStore());
    final services = AppServices(
      library: library,
      settings: Settings(secrets: MemorySecretStore()),
      recordingsDir: Directory.systemTemp,
      speechBackend: FakeSpeech('unused'),
    );
    services.speech.phase = SpeechPhase.running;
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: TakeReviewScreen(script: ScriptDocument.create(), take: take),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Cancel processing'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cancel processing'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(LinearProgressIndicator),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Find spoken words'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Find spoken words'),
          )
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.text('Cancel processing'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Cancel processing'));
    await tester.pump();
    expect(take.wordsPath, isNull);
    await tester.pumpWidget(const SizedBox());
    services.speech.dispose();
    services.speechModels.dispose();
    library.dispose();
  });
}

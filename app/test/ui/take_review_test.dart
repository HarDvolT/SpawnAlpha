import 'dart:io';

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
import 'package:spawnalpha/src/ui/take_review_screen.dart';

import '../transcription/speech_processor_test.dart' show FakeSpeech;

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
          await tester.scrollUntilVisible(transcript, 250, scrollable: find.byType(Scrollable).first);
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
    await tester.scrollUntilVisible(find.text('Cancel processing'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Cancel processing'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(LinearProgressIndicator), 150, scrollable: find.byType(Scrollable).first);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Cancel processing'), -150, scrollable: find.byType(Scrollable).first);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Find spoken words'),
          )
          .onPressed,
      isNull,
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

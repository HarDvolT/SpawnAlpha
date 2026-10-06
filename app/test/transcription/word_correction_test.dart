import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/transcription/captions.dart';
import 'package:spawnalpha/src/transcription/speech_models.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

import 'speech_processor_test.dart' show FakeSpeech;

(String, String, String) wording(ScriptLanguage language) => switch (language) {
  ScriptLanguage.en => ('Hullo', 'Hello', 'everyone.'),
  ScriptLanguage.fr => ('Salut', 'Bonjour', 'demain.'),
  ScriptLanguage.ar => ('مرحبا', 'أهلا', 'بالجميع.'),
};

class CorrectionStore extends MemoryScriptStore {
  bool fail = false;
  @override
  Future<void> save(ScriptDocument script) async {
    if (fail) throw const FileSystemException('Generated save failure');
    await super.save(script);
  }
}

void main() {
  for (final language in ScriptLanguage.values) {
    final (wrong, right, next) = wording(language);
    test(
      'correction preserves evidence and restores first spelling $language',
      () {
        final word = SpokenWord(
          text: wrong,
          start: const Duration(milliseconds: 100),
          end: const Duration(milliseconds: 400),
          confidence: .3,
        );
        final words = WordTranscript(
          language: language,
          duration: const Duration(seconds: 3),
          words: [word],
        );
        final fixed = words.withWord(0, right), twice = fixed.withWord(0, next);
        expect(words.words.single.text, wrong);
        expect(fixed.words.single.recognizedText, wrong);
        expect(twice.words.single.recognizedText, wrong);
        expect(twice.words.single.start, word.start);
        expect(twice.words.single.end, word.end);
        expect(twice.words.single.confidence, .3);
        final loaded = WordTranscript.fromJson(twice.toJson());
        expect(loaded.words.single.recognizedText, wrong);
        final output = speechOnCut(
          loaded,
          CutPlan(
            takeId: 'generated',
            language: language,
            sourceDuration: loaded.duration,
            ranges: [SourceRange(start: Duration.zero, end: loaded.duration)],
          ),
        );
        expect(output.words.single.recognizedText, wrong);
        final restored = loaded.withWord(0, wrong);
        expect(restored.words.single.corrected, isFalse);
        expect(restored.toJson(), words.toJson());
        expect(SpokenWord.fromJson(word.toJson()).corrected, isFalse);
        expect(() => words.withWord(-1, right), throwsFormatException);
        expect(() => words.withWord(1, right), throwsFormatException);
        for (final bad in [
          '',
          '$right $next',
          ' $right',
          '\n$right',
          '.',
          'x' * 1025,
          '\uD800',
        ]) {
          expect(() => words.withWord(0, bad), throwsFormatException);
        }
      },
    );
    for (final notes in [false, true]) {
      test(
        'durable correction has frozen policy and no recognizer $language Notes=$notes',
        () async {
          final fixture = await correctionFixture(language, notes: notes);
          addTearDown(fixture.dispose);
          final oldBytes = await File(fixture.take.wordsPath!).readAsBytes();
          final corrected = await fixture.speech.correctWord(
            fixture.doc.id,
            fixture.take,
            0,
            right,
          );
          expect(corrected, isNotNull);
          expect(corrected!.transcript.words.first.text, right);
          expect(corrected.transcript.words.first.recognizedText, wrong);
          expect(corrected.transcript.words.first.confidence, .3);
          expect(
            corrected.quiet.single.toJson(),
            fixture.saved.quiet.single.toJson(),
          );
          expect(corrected.snapshot!.text, '$right $next');
          expect(corrected.alignment, notes ? isNull : isNotNull);
          if (!notes) {
            expect(
              (corrected.alignment!['words'] as List).first['match'],
              'exact',
            );
          }
          final latest = fixture.library.byId(fixture.doc.id)!.takes.single;
          expect(latest.wordsPath, isNot(fixture.take.wordsPath));
          expect(latest.cutPath, isNull);
          expect(latest.exportsPath, fixture.take.exportsPath);
          expect(
            fixture.library.byId(fixture.doc.id)!.text,
            'Later edit survives.',
          );
          expect(await File(fixture.take.wordsPath!).readAsBytes(), oldBytes);
          expect(fixture.backend.started.isCompleted, isFalse);
          final loaded = (await fixture.speech.load(latest))!;
          final captions = captionsFromSpeech(loaded.transcript);
          expect(captions.first.text, contains(right));
          expect(
            captions.first.start,
            fixture.saved.transcript.words.first.start,
          );
          await fixture.library.load();
          expect(
            fixture.library.byId(fixture.doc.id)!.takes.single.wordsPath,
            latest.wordsPath,
          );
          final restored = await fixture.speech.correctWord(
            fixture.doc.id,
            latest,
            0,
            wrong,
          );
          expect(restored!.transcript.words.first.corrected, isFalse);
        },
      );
    }
  }
  test('computer-sound-only correction never creates script scoring', () async {
    final fixture = await correctionFixture(
      ScriptLanguage.en,
      alignment: false,
    );
    addTearDown(fixture.dispose);
    final corrected = await fixture.speech.correctWord(
      fixture.doc.id,
      fixture.take,
      0,
      'Hello',
    );
    expect(corrected!.alignment, isNull);
    expect(corrected.notice, 'Computer sound has no speaker score.');
  });
  test(
    'invalid, concurrent and stale correction preserve saved revisions',
    () async {
      final fixture = await correctionFixture(ScriptLanguage.fr);
      addTearDown(fixture.dispose);
      expect(
        await fixture.speech.correctWord(
          fixture.doc.id,
          fixture.take,
          0,
          'deux mots',
        ),
        isNull,
      );
      expect(
        fixture.library.byId(fixture.doc.id)!.takes.single.wordsPath,
        fixture.take.wordsPath,
      );
      final active = fixture.speech.correctWord(
        fixture.doc.id,
        fixture.take,
        0,
        'Bonjour',
      );
      expect(
        await fixture.speech.correctWord(
          fixture.doc.id,
          fixture.take,
          0,
          'Autre',
        ),
        isNull,
      );
      expect(await active, isNotNull);
      final latest = fixture.library.byId(fixture.doc.id)!.takes.single;
      expect(
        await fixture.speech.correctWord(
          fixture.doc.id,
          fixture.take,
          0,
          'Ancien',
        ),
        isNull,
      );
      expect(
        fixture.library.byId(fixture.doc.id)!.takes.single.wordsPath,
        latest.wordsPath,
      );
      expect(fixture.speech.problem, isNot(contains('Ancien')));
      expect(fixture.backend.started.isCompleted, isFalse);
    },
  );
  test(
    'library write failure restores the prior attachment and allows retry',
    () async {
      final fixture = await correctionFixture(ScriptLanguage.ar);
      addTearDown(fixture.dispose);
      fixture.store.fail = true;
      expect(
        await fixture.speech.correctWord(
          fixture.doc.id,
          fixture.take,
          0,
          'أهلا',
        ),
        isNull,
      );
      expect(
        fixture.library.byId(fixture.doc.id)!.takes.single.toJson(),
        fixture.take.toJson(),
      );
      expect(
        (await fixture.speech.load(fixture.take))!.transcript.words.first.text,
        'مرحبا',
      );
      fixture.store.fail = false;
      expect(
        await fixture.speech.correctWord(
          fixture.doc.id,
          fixture.take,
          0,
          'أهلا',
        ),
        isNotNull,
      );
      expect(fixture.speech.phase, SpeechPhase.ready);
    },
  );
}

class CorrectionFixture {
  CorrectionFixture(
    this.directory,
    this.store,
    this.library,
    this.backend,
    this.speech,
    this.doc,
    this.take,
    this.saved,
  );
  final Directory directory;
  final CorrectionStore store;
  final ScriptLibrary library;
  final FakeSpeech backend;
  final SpeechProcessor speech;
  final ScriptDocument doc;
  final Take take;
  final SavedTranscript saved;
  Future<void> dispose() async {
    speech.dispose();
    speech.models.dispose();
    library.dispose();
    await directory.delete(recursive: true);
  }
}

Future<CorrectionFixture> correctionFixture(
  ScriptLanguage language, {
  bool notes = false,
  bool alignment = true,
}) async {
  final root = await Directory(
    '${Directory.current.path}/build/word-correction-tests',
  ).create(recursive: true);
  final dir = await root.createTemp('fixture-'),
      recordings = Directory('${dir.path}/recordings');
  await recordings.create();
  final store = CorrectionStore();
  final ownedLibrary = ScriptLibrary(store),
      backend = FakeSpeech('must not run');
  final speech = SpeechProcessor(
    backend,
    SpeechModels(Directory('${dir.path}/models'), backend),
    ownedLibrary,
    recordings,
  );
  await speech.results.create();
  final (wrong, right, next) = wording(language);
  final frozen = ScriptDocument.create(text: '$right $next', language: language)
      .copyWith(
        recordingAid: notes ? RecordingAid.notes : RecordingAid.script,
        notes: NoteDeck([NoteCard(id: 'a', body: 'Private reminder')]),
      );
  final words = WordTranscript(
    language: language,
    duration: const Duration(seconds: 3),
    words: [
      SpokenWord(
        text: wrong,
        start: const Duration(milliseconds: 100),
        end: const Duration(milliseconds: 400),
        confidence: .3,
      ),
      SpokenWord(
        text: next,
        start: const Duration(seconds: 2),
        end: const Duration(milliseconds: 2400),
        confidence: .9,
      ),
    ],
  );
  final take = Take(
    path: '${recordings.path}/generated.wav',
    recordedAt: DateTime(2026),
    duration: words.duration,
    wordsPath: '${speech.results.path}/old.json',
    cutPath: '${recordings.path}/old-cut.json',
    exportsPath: '${dir.path}/old-history.json',
  );
  final saved = SavedTranscript(
    sourcePath: take.path,
    transcript: words,
    snapshot: frozen,
    alignment: !notes && alignment ? {'attemptCount': 1} : null,
    notice: alignment ? null : 'Computer sound has no speaker score.',
    quiet: [
      SourceRange(
        start: const Duration(seconds: 1),
        end: const Duration(milliseconds: 1900),
      ),
    ],
  );
  await File(take.wordsPath!)
      .writeAsString(jsonEncode(saved.toJson()), flush: true);
  final doc = frozen.withText('Later edit survives.').copyWith(takes: [take]);
  await ownedLibrary.save(doc);
  return CorrectionFixture(
    dir,
    store,
    ownedLibrary,
    backend,
    speech,
    doc,
    take,
    saved,
  );
}

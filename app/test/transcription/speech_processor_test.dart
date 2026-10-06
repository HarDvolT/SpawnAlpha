import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/camera_take_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/transcription/speech_backend.dart';
import 'package:spawnalpha/src/transcription/speech_models.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';

class FakeSpeech extends SpeechBackend {
  FakeSpeech(this.text);
  final String text;
  bool valid = true;
  String? vocabulary;
  Completer<List<Object?>>? deferred;
  final started = Completer<void>();
  @override
  bool get supported => true;
  @override
  Future<bool> verify(String model) async => valid;
  @override
  Future<void> cancel() async {
    if (deferred != null && !deferred!.isCompleted) {
      deferred!.completeError(const SpeechCancelled());
    }
  }

  @override
  Future<List<Object?>> transcribe({
    required String model,
    required String media,
    required ScriptLanguage language,
    required String vocabulary,
    required Duration duration,
    required void Function(double) progress,
  }) async {
    this.vocabulary = vocabulary;
    if (!started.isCompleted) started.complete();
    if (deferred != null) return deferred!.future;
    progress(1);
    var position = 100000;
    return [
      {
        'offsetUs': 0,
        'keepStartUs': 0,
        'keepEndUs': duration.inMicroseconds,
        'durationUs': duration.inMicroseconds,
        'pieces': [
          for (final word in text.split(' '))
            {
              'bytes': utf8.encode(' $word'),
              'startUs': position,
              'endUs': position += 300000,
              'probability': 0.9,
            },
        ],
      },
    ];
  }
}

void main() {
  for (final language in ScriptLanguage.values) {
    for (final notes in [false, true]) {
      test(
        'durable speech follows frozen aid $language Notes=$notes',
        () async {
          final dir = await Directory.systemTemp.createTemp(
            'spawnalpha-speech-',
          );
          addTearDown(() => dir.delete(recursive: true));
          final text = switch (language) {
            ScriptLanguage.en => 'Hello everyone.',
            ScriptLanguage.fr => 'Bonjour à tous.',
            ScriptLanguage.ar => 'مرحبا بكم اليوم.',
          };
          final backend = FakeSpeech(text),
              library = ScriptLibrary(MemoryScriptStore());
          final models = SpeechModels(Directory('${dir.path}/models'), backend);
          await models.directory.create();
          await models.file.writeAsString('mock model');
          final recordings = Directory('${dir.path}/recordings');
          await recordings.create();
          var doc =
              ScriptDocument.create(
                text: notes ? 'Unrelated script' : text,
                language: language,
              ).copyWith(
                recordingAid: notes ? RecordingAid.notes : RecordingAid.script,
                notes: NoteDeck([NoteCard(id: 'a', body: 'Private reminder')]),
              );
          final snapshot = await CameraTakeSnapshot.reserve(recordings, doc);
          final take = Take(
            path: '${recordings.path}/generated.wav',
            recordedAt: DateTime.now(),
            duration: const Duration(seconds: 3),
            metadataPath: snapshot.file.path,
          );
          await snapshot.finish(take);
          doc = doc.withText('Later edits').copyWith(takes: [take]);
          await library.save(doc);
          final processor = SpeechProcessor(
            backend,
            models,
            library,
            recordings,
          );
          await processor.process(doc, take);
          expect(processor.phase, SpeechPhase.ready);
          expect(
            processor.result!.snapshot!.text,
            notes ? 'Unrelated script' : text,
          );
          expect(
            processor.result!.transcript.words.map((w) => w.text).join(' '),
            text,
          );
          expect(processor.result!.alignment, notes ? isNull : isNotNull);
          expect(
            backend.vocabulary,
            notes ? contains('Private reminder') : text,
          );
          final stored = library.byId(doc.id)!.takes.single;
          expect(stored.wordsPath, isNotNull);
          final loaded = await processor.load(stored);
          expect(loaded!.transcript.language, language);
          expect(loaded.snapshot!.usesNotes, notes);
          expect(library.byId(doc.id)!.text, 'Later edits');
          expect(Take.fromJson(stored.toJson())!.wordsPath, stored.wordsPath);
          processor.dispose();
          models.dispose();
          library.dispose();
        },
      );
    }
  }
  test('cancelled jobs never attach results or change the original', () async {
    final dir = await Directory.systemTemp.createTemp('spawnalpha-speech-');
    addTearDown(() => dir.delete(recursive: true));
    final backend = FakeSpeech('Hello')..deferred = Completer<List<Object?>>();
    final models = SpeechModels(dir, backend);
    await models.file.writeAsString('mock model');
    final library = ScriptLibrary(MemoryScriptStore()),
        recordings = Directory('${dir.path}/recordings');
    await recordings.create();
    final original = File('${recordings.path}/generated.wav');
    await original.writeAsString('untouched');
    final take = Take(
      path: original.path,
      recordedAt: DateTime.now(),
      duration: const Duration(seconds: 3),
    );
    final doc = ScriptDocument.create(text: 'Hello').copyWith(takes: [take]);
    await library.save(doc);
    final processor = SpeechProcessor(backend, models, library, recordings);
    final run = processor.process(doc, take);
    await backend.started.future;
    await processor.cancel();
    await run;
    expect(processor.phase, SpeechPhase.cancelled);
    expect(library.byId(doc.id)!.takes.single.wordsPath, isNull);
    expect(await original.readAsString(), 'untouched');
    processor.dispose();
    models.dispose();
    library.dispose();
  });
  test(
    'failed or oversized downloads do not replace an existing model',
    () async {
      final dir = await Directory.systemTemp.createTemp('spawnalpha-speech-');
      addTearDown(() => dir.delete(recursive: true));
      final backend = FakeSpeech('Hello')..valid = false;
      for (final status in [500, 200]) {
        final model = SpeechModels(
          dir,
          backend,
          client: () => MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.body, isEmpty);
            return http.Response(
              'short download',
              status,
              headers: {'content-length': '${SpeechModels.expectedBytes + 1}'},
            );
          }),
        );
        await model.file.writeAsString('preserve existing');
        await model.prepare();
        expect(model.phase, SpeechModelPhase.failed);
        expect(await model.file.readAsString(), 'preserve existing');
        expect(await File('${model.file.path}.partial').exists(), isFalse);
        model.dispose();
      }
    },
  );
}

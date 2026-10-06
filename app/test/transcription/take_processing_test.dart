import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/camera_take_store.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/transcription/speech_models.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/take_processing.dart';

import 'speech_processor_test.dart' show FakeSpeech;

class QuietSpeech extends FakeSpeech {
  QuietSpeech(super.text);
  int calls = 0;
  @override
  Future<List<Object?>> transcribe({
    required String model,
    required String media,
    required ScriptLanguage language,
    required String vocabulary,
    required Duration duration,
    required void Function(double) progress,
  }) async {
    ++calls;
    final windows = await super.transcribe(
      model: model,
      media: media,
      language: language,
      vocabulary: vocabulary,
      duration: duration,
      progress: progress,
    );
    (windows.first! as Map)['quiet'] = [
      {'startUs': 1500000, 'endUs': 2700000},
    ];
    return windows;
  }
}

void main() {
  late Directory root, recordings;
  late ScriptLibrary library;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('spawnalpha-after-stop-');
    recordings = Directory('${root.path}/recordings');
    await recordings.create();
    library = ScriptLibrary(MemoryScriptStore());
  });
  tearDown(() async {
    library.dispose();
    await root.delete(recursive: true);
  });

  for (final language in ScriptLanguage.values) {
    for (final notes in [false, true]) {
      test(
        'after-stop uses frozen $language Notes=$notes and reuses restored cut',
        () async {
          final text = switch (language) {
            ScriptLanguage.en => 'Hello everyone.',
            ScriptLanguage.fr => 'Bonjour à tous.',
            ScriptLanguage.ar => 'مرحبا بكم اليوم.',
          };
          final backend = QuietSpeech(text),
              models = SpeechModels(Directory('${root.path}/models'), backend);
          // Both use a fake verified installed model; no network/native device.
          await models.directory.create();
          await models.file.writeAsString('mock model');
          final speech = SpeechProcessor(backend, models, library, recordings);
          final cuts = CleanCutStore(
            Directory('${recordings.path}/cuts'),
            library,
          );
          final processing = TakeProcessing(speech, cuts);
          var doc = ScriptDocument.create(text: text, language: language)
              .copyWith(
                recordingAid: notes ? RecordingAid.notes : RecordingAid.script,
                notes: NoteDeck([NoteCard(id: 'a', body: text)]),
              );
          final snapshot = await CameraTakeSnapshot.reserve(recordings, doc);
          final original = File('${recordings.path}/generated.mp4');
          await original.writeAsString('original');
          final take = Take(
            path: original.path,
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 3),
            metadataPath: snapshot.file.path,
          );
          await snapshot.finish(take);
          doc = doc.withText('Later edits').copyWith(takes: [take]);
          await library.save(doc);
          final plan = await processing.run(doc, take, automatic: true);
          expect(processing.phase, TakeProcessPhase.ready);
          expect(plan!.changes, isNotEmpty);
          expect(speech.result!.snapshot!.text, text);
          expect(speech.result!.alignment, notes ? isNull : isNotNull);
          expect(library.byId(doc.id)!.text, 'Later edits');
          final saved = library.byId(doc.id)!.takes.single;
          expect(saved.wordsPath, isNotNull);
          expect(saved.cutPath, isNotNull);
          await cuts.save(doc.id, saved, plan.restoreAll());
          final restored = library.byId(doc.id)!.takes.single;
          final again = await processing.run(doc, restored, automatic: true);
          expect(again!.changes.every((c) => !c.enabled), isTrue);
          expect(backend.calls, 1);
          expect(library.byId(doc.id)!.takes.single.cutPath, restored.cutPath);
          expect(await original.readAsString(), 'original');
          processing.dispose();
          speech.dispose();
          models.dispose();
        },
      );
    }
  }

  test(
    'missing model waits for explicit setup without a network request',
    () async {
      var requests = 0;
      final backend = FakeSpeech('Hello');
      final models = SpeechModels(
        Directory('${root.path}/models'),
        backend,
        client: () => MockClient((_) async {
          ++requests;
          return http.Response('', 500);
        }),
      );
      final speech = SpeechProcessor(backend, models, library, recordings);
      final processing = TakeProcessing(
        speech,
        CleanCutStore(Directory('${recordings.path}/cuts'), library),
      );
      final take = Take(
        path: '${recordings.path}/generated.mp4',
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 3),
      );
      final doc = ScriptDocument.create(text: 'Hello').copyWith(takes: [take]);
      await library.save(doc);
      expect(await processing.run(doc, take, automatic: true), isNull);
      expect(processing.phase, TakeProcessPhase.needsSetup);
      expect(requests, 0);
      expect(backend.started.isCompleted, isFalse);
      expect(library.byId(doc.id)!.takes.single.wordsPath, isNull);
      final explicit = models.prepare();
      await models.cancel();
      await explicit;
      expect(
        requests,
        0,
        reason: 'cancel before the scheduled setup prevents download',
      );
      processing.dispose();
      speech.dispose();
      models.dispose();
    },
  );

  test(
    'one active pipeline; cancelled recognition attaches no words or cut',
    () async {
      final backend = FakeSpeech('Hello')
        ..deferred = Completer<List<Object?>>();
      final models = SpeechModels(root, backend);
      await models.file.writeAsString('mock model');
      final speech = SpeechProcessor(backend, models, library, recordings);
      final processing = TakeProcessing(
        speech,
        CleanCutStore(Directory('${recordings.path}/cuts'), library),
      );
      final take = Take(
        path: '${recordings.path}/generated.mp4',
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 3),
      );
      final doc = ScriptDocument.create(text: 'Hello').copyWith(takes: [take]);
      await library.save(doc);
      final first = processing.run(doc, take, automatic: true);
      await backend.started.future;
      expect(await processing.run(doc, take), isNull);
      await processing.cancel();
      await first;
      expect(processing.phase, TakeProcessPhase.cancelled);
      expect(library.byId(doc.id)!.takes.single.wordsPath, isNull);
      expect(library.byId(doc.id)!.takes.single.cutPath, isNull);
      processing.dispose();
      speech.dispose();
      models.dispose();
    },
  );
}

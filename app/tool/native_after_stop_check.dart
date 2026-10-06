// Generated SAPI speech only. Never records input or opens owner media.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/storage/camera_take_store.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/transcription/speech_backend.dart';
import 'package:spawnalpha/src/transcription/speech_models.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/take_processing.dart';

void require(bool value) {
  if (!value) throw StateError('Generated after-stop check failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Checking processing after Stop…')),
      ),
    ),
  );
  var stage = 'check generated inputs';
  try {
    final root = Directory.current.path;
    final backend = WindowsSpeechBackend();
    final models = SpeechModels(Directory('$root/build/asr'), backend);
    require(await models.checkInstalled());
    final source = File('$root/build/asr/generated-speech.wav');
    require(await source.exists());
    final directory = await Directory('$root/build/asr')
        .createTemp('after-stop-');
    final library = ScriptLibrary(
      FileScriptStore(Directory('${directory.path}/scripts')),
    );
    for (final notes in [false, true]) {
      stage = notes
          ? 'automatic Notes speech and cut'
          : 'automatic Script speech and cut';
      final file = await source.copy(
        '${directory.path}/${notes ? 'notes' : 'script'}.wav',
      );
      final doc =
          ScriptDocument.create(
            text: 'We launch today. This is a local speech timing test. We launch today.',
          ).copyWith(
            recordingAid: notes ? RecordingAid.notes : RecordingAid.script,
            notes: NoteDeck([NoteCard(id: 'a', body: 'Talk about the launch')]),
          );
      final frozen = await CameraTakeSnapshot.reserve(directory, doc);
      final take = Take(
        path: file.path,
        recordedAt: DateTime(2026),
        duration: const Duration(seconds: 8),
        metadataPath: frozen.file.path,
      );
      await frozen.finish(take);
      final edited = doc
          .withText('Later edits stay separate.')
          .copyWith(takes: [take]);
      await library.save(edited);
      final speech = SpeechProcessor(backend, models, library, directory);
      final cuts = CleanCutStore(Directory('${directory.path}/cuts'), library);
      final processing = TakeProcessing(speech, cuts);
      final plan = await processing.run(edited, take, automatic: true);
      require(processing.phase == TakeProcessPhase.ready && plan != null);
      final saved = library.byId(doc.id)!.takes.single;
      require(saved.wordsPath != null && saved.cutPath != null);
      final spoken = (await speech.load(saved))!;
      require(
        spoken.transcript.words.length >= 10 &&
            spoken.snapshot!.text == doc.text,
      );
      require(notes ? spoken.alignment == null : spoken.alignment != null);
      require(library.byId(doc.id)!.text == 'Later edits stay separate.');
      stage = 'reuse saved result';
      require(await processing.run(edited, saved, automatic: true) != null);
      require(library.byId(doc.id)!.takes.single.wordsPath == saved.wordsPath);
      require(library.byId(doc.id)!.takes.single.cutPath == saved.cutPath);
      require(await source.length() == await file.length());
      processing.dispose();
      speech.dispose();
    }
    await library.load();
    require(library.scripts.every((s) => s.takes.single.cutPath != null));
    library.dispose();
    models.dispose();
    // ignore: avoid_print
    print(
      'After-stop check passed: verified installed model, real offline Script/Notes speech, frozen aid, preserved later edits, saved reversible cuts, idempotent reopening and library reload.',
    );
  } on Object {
    // Fixed stage only; no private media text, paths or platform errors.
    // ignore: avoid_print
    print('After-stop check failed at $stage.');
  }
}

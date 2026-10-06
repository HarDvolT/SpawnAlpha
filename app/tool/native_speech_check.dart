// Generated local speech only. No live microphone, camera, owner take or network.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/storage/camera_take_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/transcription/speech_backend.dart';
import 'package:spawnalpha/src/transcription/speech_models.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/speech_windows.dart';
import 'package:spawnalpha/src/transcription/captions.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';

void require(bool condition) {
  if (!condition) throw StateError('Generated speech check failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Checking offline speech…'))),
    ),
  );
  try {
    final root = Directory.current.path;
    final backend = CheckingBackend(),
        models = SpeechModels(
          Directory('$root/build/asr'),
          WindowsSpeechBackend(),
        );
    // Use one backend owner for both verification and recognition.
    final ownedModels = SpeechModels(models.directory, backend);
    final cancelled = backend.verify(models.file.path);
    await backend.cancel();
    var cancelledCorrectly = false;
    try {
      await cancelled;
    } on SpeechCancelled {
      cancelledCorrectly = true;
    }
    require(cancelledCorrectly);
    require(await backend.verify(models.file.path));
    final directory = Directory(
      '$root/build/asr/app-check-${DateTime.now().microsecondsSinceEpoch}',
    );
    await directory.create();
    final wrong = File('${directory.path}/wrong.bin');
    await wrong.writeAsString('generated invalid model');
    require(!await backend.verify(wrong.path));
    final library = ScriptLibrary(MemoryScriptStore());
    final source = File('$root/build/asr/generated-speech.wav');
    for (final notes in [false, true]) {
      final wave = await source.copy(
        '${directory.path}/${notes ? 'notes' : 'script'}.wav',
      );
      final script =
          ScriptDocument.create(
            text: 'We launch today. This is a local speech timing test. We launch today.',
          ).copyWith(
            recordingAid: notes ? RecordingAid.notes : RecordingAid.script,
            notes: NoteDeck([
              NoteCard(
                id: 'a',
                title: 'Opening',
                body: 'Talk about the launch',
              ),
            ]),
          );
      final frozen = await CameraTakeSnapshot.reserve(directory, script);
      final take = Take(
        path: wave.path,
        recordedAt: DateTime.now(),
        duration: const Duration(seconds: 8),
        metadataPath: frozen.file.path,
      );
      await frozen.finish(take);
      final edited = script
          .withText('Later edits must not change the old take.')
          .copyWith(takes: [take]);
      await library.save(edited);
      final processor = SpeechProcessor(
        backend,
        ownedModels,
        library,
        directory,
      );
      await processor.process(edited, take);
      if (processor.phase != SpeechPhase.ready) {
        debugPrint('Generated speech check stage: ${processor.failure}');
      }
      require(processor.phase == SpeechPhase.ready && processor.result != null);
      final spoken = processor.result!;
      require(
        spoken.transcript.words.length >= 10 &&
            spoken.snapshot!.text == script.text,
      );
      require(notes ? spoken.alignment == null : spoken.alignment != null);
      final reloaded = await processor.load(
        library.byId(script.id)!.takes.single,
      );
      require(
        reloaded != null &&
            reloaded.transcript.words.length == spoken.transcript.words.length,
      );
      require(
        subtitleText(
          captionsFromSpeech(spoken.transcript),
          vtt: true,
        ).startsWith('WEBVTT'),
      );
      processor.dispose();
    }
    final longFile = await longFixture(source, directory);
    final windows = await backend.transcribe(
      model: models.file.path,
      media: longFile.path,
      language: ScriptLanguage.en,
      vocabulary: 'We launch today. This is a local speech timing test.',
      duration: const Duration(seconds: 70),
      progress: (_) {},
    );
    final words = transcriptFromWindows(
      ScriptLanguage.en,
      const Duration(seconds: 70),
      windows,
    );
    require(windows.length == 3 && words.words.length >= 30);
    require(words.words.any((w) => w.start >= const Duration(seconds: 57)));
    final quiet = quietFromWindows(words.duration, windows);
    final cut = planQuietCut(
      takeId: 'generated',
      transcript: words,
      quiet: quiet,
      snapshot: ScriptDocument.create().copyWith(
        recordingAid: RecordingAid.notes,
      ),
    );
    require(
      cut.changes.length >= 2 && cut.asCutPlan().duration < words.duration,
    );
    require(
      speechOnCut(words, cut.asCutPlan()).words.length == words.words.length,
    );
    debugPrint(
      'Native speech app check passed: verified model, cancellation, frozen Script/Notes, durable words, captions, three bounded windows, measured quiet gaps and reversible cuts that keep every spoken word.',
    );
    library.dispose();
    ownedModels.dispose();
    models.dispose();
  } on Object {
    debugPrint(
      'Native speech app check failed. Originals and generated fixtures are preserved.',
    );
  }
  await SystemNavigator.pop();
}

class CheckingBackend extends WindowsSpeechBackend {
  @override
  Future<List<Object?>> transcribe({
    required String model,
    required String media,
    required ScriptLanguage language,
    required String vocabulary,
    required Duration duration,
    required void Function(double) progress,
  }) async {
    final windows = await super.transcribe(
      model: model,
      media: media,
      language: language,
      vocabulary: vocabulary,
      duration: duration,
      progress: progress,
    );
    // This target only receives generated fixtures. Keep text out of diagnostics.
    await File('${File(media).parent.path}/generated-windows.json')
        .writeAsString(jsonEncode(windows), flush: true);
    try {
      transcriptFromWindows(language, duration, windows);
    } on FormatException catch (error) {
      const messages = {
        'Invalid speech window',
        'Invalid spoken word',
        'Invalid word timing',
        'Invalid speech fragment',
        'Invalid speech fragment time',
        'Invalid speech encoding',
        'Invalid speech word',
      };
      debugPrint(
        'Generated timing validation: ${messages.contains(error.message) ? error.message : 'invalid output'}',
      );
    }
    return windows;
  }
}

Future<File> longFixture(File source, Directory directory) async {
  final raw = await source.readAsBytes(),
      data = ByteData.sublistView(await source.readAsBytes());
  var at = 12;
  Uint8List? pcm;
  while (at + 8 <= raw.length) {
    final id = ascii.decode(raw.sublist(at, at + 4)),
        size = data.getUint32(at + 4, Endian.little);
    require(at + 8 + size <= raw.length);
    if (id == 'fmt ') {
      require(
        data.getUint16(at + 8, Endian.little) == 1 &&
            data.getUint16(at + 10, Endian.little) == 1 &&
            data.getUint32(at + 12, Endian.little) == 16000 &&
            data.getUint16(at + 22, Endian.little) == 16,
      );
    }
    if (id == 'data') pcm = raw.sublist(at + 8, at + 8 + size);
    at += 8 + size + size % 2;
  }
  require(pcm != null && pcm.length < 16000 * 2 * 10);
  final body = Uint8List(16000 * 2 * 70);
  for (final second in [0, 27, 58]) {
    body.setRange(second * 32000, second * 32000 + pcm!.length, pcm);
  }
  final header = ByteData(44);
  void label(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      header.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  label(0, 'RIFF');
  header.setUint32(4, 36 + body.length, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  label(36, 'data');
  header.setUint32(40, body.length, Endian.little);
  final file = File('${directory.path}/long-generated.wav');
  final sink = file.openWrite();
  sink.add(header.buffer.asUint8List());
  sink.add(body);
  await sink.flush();
  await sink.close();
  return file;
}

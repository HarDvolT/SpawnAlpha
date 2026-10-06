// Generated colour/tone islands and labelled words only. No owner speech,
// input, model download or recording device. Native fixture has actual silence.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/render/export_processor.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/storage/clean_cut_store.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/video_export_store.dart';
import 'package:spawnalpha/src/transcription/script_alignment.dart';
import 'package:spawnalpha/src/transcription/speech_backend.dart';
import 'package:spawnalpha/src/transcription/speech_models.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

void require(bool value) {
  if (!value) throw StateError('Generated filler check failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Checking reversible filler choices…')),
      ),
    ),
  );
  var stage = 'generated input';
  ScriptLibrary? library;
  ExportProcessor? exports;
  SpeechProcessor? speech;
  SpeechModels? models;
  try {
    final prefix = (await File(
      'build/filler-fixture-prefix.txt',
    ).readAsString()).trim();
    final fixture = File('$prefix-filler-source.mp4');
    require(
      prefix.startsWith(
            '${Directory.current.path}\\build\\exports\\fillers-',
          ) &&
          await fixture.exists(),
    );
    final root = await Directory('build/exports').createTemp('filler-app-');
    final wordsFolder = await Directory('${root.absolute.path}/words').create();
    library = ScriptLibrary(
      FileScriptStore(Directory('${root.absolute.path}/scripts')),
    );
    final backend = WindowsSpeechBackend();
    models = SpeechModels(Directory('${root.absolute.path}/models'), backend);
    speech = SpeechProcessor(backend, models, library, root.absolute);
    final cuts = CleanCutStore(
      Directory('${root.absolute.path}/cuts'),
      library,
    );
    final store = VideoExportStore(
      Directory('${root.absolute.path}/exports'),
      library,
      const WindowsRecordingInspector(),
    );
    exports = ExportProcessor(WindowsVideoRenderer(), store, cuts, speech.load);
    for (final language in ScriptLanguage.values) {
      stage = 'save labelled words';
      final source = await fixture.copy(
        '${root.absolute.path}/${language.name}.mp4',
      );
      final before = await source.readAsBytes();
      final text = switch (language) {
        ScriptLanguage.en => ['Hello', 'um,', 'everyone.'],
        ScriptLanguage.fr => ['Bonjour', 'euh,', 'tous.'],
        ScriptLanguage.ar => ['مرحبا', 'إيه،', 'بالجميع.'],
      };
      final transcript = WordTranscript(
        language: language,
        duration: const Duration(seconds: 4),
        words: [
          SpokenWord(
            text: text[0],
            start: const Duration(milliseconds: 200),
            end: const Duration(milliseconds: 500),
            confidence: .9,
          ),
          SpokenWord(
            text: text[1],
            start: const Duration(milliseconds: 1100),
            end: const Duration(milliseconds: 1250),
            confidence: .9,
          ),
          SpokenWord(
            text: text[2],
            start: const Duration(seconds: 2),
            end: const Duration(milliseconds: 2300),
            confidence: .9,
          ),
        ],
      );
      final frozen = ScriptDocument.create(
        language: language,
        text: '${text.first} ${text.last}',
      );
      final wordsFile = File('${wordsFolder.path}/${newId()}.json');
      final take = Take(
        path: source.path,
        recordedAt: DateTime(2026),
        duration: transcript.duration,
        wordsPath: wordsFile.path,
      );
      final document = frozen.copyWith(takes: [take]);
      await library.save(document);
      final spoken = SavedTranscript(
        sourcePath: source.path,
        transcript: transcript,
        snapshot: frozen,
        alignment: {
          'attemptCount': alignTranscript(frozen, transcript).attemptCount,
        },
        quiet: [
          SourceRange(
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 1100),
          ),
          SourceRange(
            start: const Duration(milliseconds: 1250),
            end: const Duration(seconds: 2),
          ),
        ],
      );
      await wordsFile.writeAsString(jsonEncode(spoken.toJson()), flush: true);
      require((await speech.load(take))!.transcript.words.length == 3);
      stage = 'propose without removing';
      final plan = await cuts.create(document, take, spoken);
      final filler = plan.changes.single;
      require(
        filler.kind == CutChangeKind.filler &&
            !filler.enabled &&
            plan.asCutPlan().duration == take.duration,
      );
      final format = language == ScriptLanguage.ar
          ? VideoFormat.portrait
          : language == ScriptLanguage.fr
          ? VideoFormat.feed
          : VideoFormat.landscape;
      for (final chosen in [false, true, false]) {
        stage = chosen
            ? 'export chosen filler'
            : 'export kept or restored filler';
        var latest = library.byId(document.id)!.takes.single;
        final current = plan.withEnabled(filler.id, chosen);
        await cuts.save(document.id, latest, current);
        latest = library.byId(document.id)!.takes.single;
        final video = await exports.export(
          document,
          latest,
          format,
          clean: current,
        );
        require(
          video != null &&
              video.burnedCaptions &&
              exports.phase == ExportPhase.done,
        );
        require(video!.duration == current.asCutPlan().duration);
        final captions = await store.file(video, 'srt').readAsString();
        require(
          captions.contains(text.first) &&
              captions.contains(text.last) &&
              captions.contains(text[1]) == !chosen,
        );
        require(
          speechOnCleanCut(transcript, current).words.length ==
              (chosen ? 2 : 3),
        );
      }
      stage = 'reload choices and original';
      await library.load();
      final latest = library.byId(document.id)!.takes.single;
      require((await cuts.load(latest))!.changes.single.enabled == false);
      require(
        (await store.load(latest)).length == 3 &&
            (await speech.load(latest))!.transcript.words.length == 3,
      );
      final after = await source.readAsBytes();
      require(
        after.length == before.length &&
            List.generate(
              before.length,
              (i) => before[i] == after[i],
            ).every((v) => v),
      );
    }
    // Fixed diagnostic only. Labelled tone fixtures do not prove ASR quality.
    // ignore: avoid_print
    print(
      'Local filler check passed: EN/FR/AR frozen scripts, measured fixture silence, choices kept by default, chosen/restored video captions, exact cut clock, durable revisions/history/reload and original bytes.',
    );
  } on Object {
    // ignore: avoid_print
    print('Local filler check failed at $stage.');
  } finally {
    exports?.dispose();
    speech?.dispose();
    models?.dispose();
    library?.dispose();
  }
}

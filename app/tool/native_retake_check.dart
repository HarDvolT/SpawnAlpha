// Generated tone islands with labelled word timings only. No owner speech,
// microphone, private script, model setup or network request.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spawnalpha/src/cut/clean_plan.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/caption_style.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/mark.dart';
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
  if (!value) throw StateError('Generated retake check failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Checking reversible retakes…'))),
    ),
  );
  var stage = 'generated input';
  const styleName = String.fromEnvironment(
    'SPAWNALPHA_CAPTION_STYLE',
    defaultValue: 'readable',
  );
  final style = const bool.fromEnvironment('SPAWNALPHA_KARAOKE_CHECK')
      ? CaptionStyle.karaoke
      : CaptionStyle.values.where((s) => s.name == styleName).single;
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
    final root = await Directory('build/exports').createTemp('retake-app-');
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
      stage = 'save frozen labelled words';
      final source = await fixture.copy(
        '${root.absolute.path}/${language.name}.mp4',
      );
      final before = await source.readAsBytes();
      final scriptText = switch (language) {
        ScriptLanguage.en => 'We launch today.',
        ScriptLanguage.fr => 'Nous lançons demain.',
        ScriptLanguage.ar => 'نحن نبدأ الآن.',
      };
      final filler = switch (language) {
        ScriptLanguage.en => 'um,',
        ScriptLanguage.fr => 'euh,',
        ScriptLanguage.ar => 'إيه،',
      };
      final frozen = ScriptDocument.create(language: language, text: scriptText)
          .copyWith(
            marks: [
              const Mark(id: 'stress', kind: MarkKind.stress, start: 1, end: 1),
              const Mark(id: 'pace', kind: MarkKind.slower, start: 2, end: 2),
            ],
          );
      final said = [
        ...frozen.tokens.map((t) => t.text),
        filler,
        ...frozen.tokens.map((t) => t.text),
      ];
      final starts = [200, 300, 400, 1100, 2000, 2100, 2200];
      final ends = [280, 380, 500, 1250, 2080, 2180, 2300];
      final words = WordTranscript(
        language: language,
        duration: const Duration(seconds: 4),
        words: [
          for (final (i, text) in said.indexed)
            SpokenWord(
              text: text,
              start: Duration(milliseconds: starts[i]),
              end: Duration(milliseconds: ends[i]),
              confidence: .9,
            ),
        ],
      );
      final wordsFile = File('${wordsFolder.path}/${newId()}.json');
      final take = Take(
        path: source.path,
        recordedAt: DateTime(2026),
        duration: words.duration,
        wordsPath: wordsFile.path,
      );
      final document = frozen.copyWith(takes: [take]);
      await library.save(document);
      final spoken = SavedTranscript(
        sourcePath: source.path,
        transcript: words,
        snapshot: frozen,
        alignment: {
          'attemptCount': alignTranscript(frozen, words).attemptCount,
        },
        quiet: [
          SourceRange(
            start: Duration.zero,
            end: const Duration(milliseconds: 200),
          ),
          SourceRange(
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 1100),
          ),
          SourceRange(
            start: const Duration(milliseconds: 1250),
            end: const Duration(seconds: 2),
          ),
          SourceRange(
            start: const Duration(milliseconds: 2300),
            end: words.duration,
          ),
        ],
      );
      await wordsFile.writeAsString(jsonEncode(spoken.toJson()), flush: true);
      stage = 'build reversible retake choices';
      final base = (await cuts.create(document, take, spoken)).restoreAll();
      require(
        base.retakes.single.selected == null &&
            base.retakes.single.canSelect(1),
      );
      final format = language == ScriptLanguage.ar
          ? VideoFormat.portrait
          : language == ScriptLanguage.fr
          ? VideoFormat.feed
          : VideoFormat.landscape;
      for (final selection in <int?>[null, 1, null]) {
        stage = 'save and export choice';
        var latest = library.byId(document.id)!.takes.single;
        final plan = base.withAttempt(base.retakes.single.id, selection);
        await cuts.save(document.id, latest, plan);
        latest = library.byId(document.id)!.takes.single;
        final video = await exports.export(
          document,
          latest,
          format,
          clean: plan,
          captionStyle: style,
          captionMotion: selection == null,
          softAudioJoins: selection != null,
        );
        require(
          video != null &&
              video.burnedCaptions &&
              video.captionStyle == style &&
              video.captionMotion == (selection == null) &&
              video.softAudioJoins == (selection != null) &&
              exports.phase == ExportPhase.done,
        );
        final changed = selection != null;
        require(
          video!.duration ==
              (changed ? const Duration(milliseconds: 2425) : words.duration),
        );
        final text = await store.file(video, 'srt').readAsString();
        require(
          RegExp(RegExp.escape(frozen.tokens.first.text))
                  .allMatches(text)
                  .length ==
              (changed ? 1 : 2),
        );
        require(text.contains(filler) == !changed);
        require(
          speechOnCleanCut(words, plan).words.length == (changed ? 3 : 7),
        );
      }
      stage = 'reload choices and original';
      await library.load();
      final latest = library.byId(document.id)!.takes.single;
      require(
        (await store.load(latest)).where((v) => v.softAudioJoins).length == 1,
      );
      require((await cuts.load(latest))!.retakes.single.selected == null);
      require(
        (await store.load(latest)).length == 3 &&
            (await store.load(latest)).every((v) => v.captionStyle == style) &&
            (await store.load(latest)).where((v) => !v.captionMotion).length ==
                1 &&
            (await speech.load(latest))!.transcript.words.length == 7,
      );
      final after = await source.readAsBytes();
      require(
        before.length == after.length &&
            List.generate(
              before.length,
              (i) => before[i] == after[i],
            ).every((v) => v),
      );
    }
    // Fixed diagnostics only. Labelled tones do not prove ASR accuracy.
    // ignore: avoid_print
    print(
      'Local retake check passed: EN/FR/AR frozen scripts, quiet boundaries, initial keep-all, selection/restore, ${style.name} video captions/subtitles, exact cut clock, history/reload and unchanged original bytes.',
    );
  } on Object {
    // ignore: avoid_print
    print('Local retake check failed at $stage.');
  } finally {
    exports?.dispose();
    speech?.dispose();
    models?.dispose();
    library?.dispose();
  }
}

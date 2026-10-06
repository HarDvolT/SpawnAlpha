import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/mark.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../storage/script_store.dart';
import 'script_alignment.dart';
import 'speech_backend.dart';
import 'speech_models.dart';
import 'speech_windows.dart';
import 'word_timing.dart';

class SavedTranscript {
  SavedTranscript({
    required this.sourcePath,
    required this.transcript,
    this.snapshot,
    this.alignment,
    this.notice,
  });
  final String sourcePath;
  final WordTranscript transcript;
  final ScriptDocument? snapshot;
  final Map<String, Object?>? alignment;
  final String? notice;
  Map<String, Object?> toJson() => {
    'version': 1,
    'sourcePath': sourcePath,
    'transcript': transcript.toJson(),
    'snapshot': ?snapshot?.toJson(),
    'alignment': ?alignment,
    'notice': ?notice,
  };
  factory SavedTranscript.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1 ||
        json['sourcePath'] is! String ||
        json['transcript'] is! Map<String, Object?>) {
      throw const FormatException('Unreadable spoken words');
    }
    final snapshot = json['snapshot'] is Map<String, Object?>
        ? ScriptDocument.fromJson(json['snapshot']! as Map<String, Object?>)
        : null;
    return SavedTranscript(
      sourcePath: json['sourcePath']! as String,
      transcript: WordTranscript.fromJson(
        json['transcript']! as Map<String, Object?>,
      ),
      snapshot: snapshot,
      alignment: snapshot?.usesNotes == true
          ? null
          : json['alignment'] as Map<String, Object?>?,
      notice: json['notice'] as String?,
    );
  }
}

SavedTranscript _parseResult(String text) =>
    SavedTranscript.fromJson(jsonDecode(text) as Map<String, Object?>);

SavedTranscript _assemble(Map<String, Object?> args) {
  final transcript = transcriptFromWindows(
    ScriptLanguage.fromName(args['language']! as String),
    Duration(microseconds: args['durationUs']! as int),
    args['windows']! as List<Object?>,
  );
  final snapshot = args['snapshot'] is Map<String, Object?>
      ? ScriptDocument.fromJson(args['snapshot']! as Map<String, Object?>)
      : null;
  Map<String, Object?>? alignment;
  String? notice;
  if (snapshot == null) {
    notice = 'This older take has no frozen script. Captions follow the spoken words.';
  } else if (args['microphone'] == false) {
    notice = 'This take recorded computer sound without a microphone. Captions follow that sound; delivery is not scored.';
  } else if (!snapshot.usesNotes && transcript.words.isNotEmpty) {
    try {
      final matched = alignTranscript(snapshot, transcript);
      alignment = {
        'missedTokens': matched.missedTokens,
        'attemptCount': matched.attemptCount,
        'words': [
          for (final word in matched.words)
            {
              'spokenIndex': word.spokenIndex,
              'tokenIndex': word.tokenIndex,
              'match': word.match.name,
              'attempt': word.attempt,
            },
        ],
      };
    } on FormatException {
      notice = 'Spoken words are saved. This script needs review in smaller sections.';
    }
  }
  if (transcript.words.isEmpty) {
    notice = 'No speech found. Keep the original and check your microphone.';
  }
  return SavedTranscript(
    sourcePath: args['sourcePath']! as String,
    transcript: transcript,
    snapshot: snapshot,
    alignment: alignment,
    notice: notice,
  );
}

enum SpeechPhase { idle, preparing, running, saving, ready, cancelled, failed }

/// One local job. Native recognition and Dart alignment both stay off the UI
/// thread; originals never change. Results refer to the exact take snapshot.
class SpeechProcessor extends ChangeNotifier {
  SpeechProcessor(this.backend, this.models, this.library, this.recordings);
  final SpeechBackend backend;
  final SpeechModels models;
  final ScriptLibrary library;
  final Directory recordings;
  Directory get results =>
      Directory('${recordings.path}${Platform.pathSeparator}words');
  SpeechPhase phase = SpeechPhase.idle;
  double progress = 0;
  String? problem;
  String? failure;
  SavedTranscript? result;
  bool _cancelled = false;
  bool get busy =>
      phase == SpeechPhase.preparing ||
      phase == SpeechPhase.running ||
      phase == SpeechPhase.saving;
  void _phase(SpeechPhase value) {
    phase = value;
    notifyListeners();
  }

  Future<SavedTranscript?> load(Take take) async {
    if (take.wordsPath == null) return null;
    try {
      final file = File(take.wordsPath!);
      final root = await results.resolveSymbolicLinks();
      final resolved = await file.resolveSymbolicLinks();
      if (!resolved.toLowerCase().startsWith(
            '${root.toLowerCase()}${Platform.pathSeparator}',
          ) ||
          await file.length() > 32 * 1024 * 1024) {
        return null;
      }
      final saved = await compute(_parseResult, await file.readAsString());
      return saved.sourcePath == take.path ? saved : null;
    } on Object {
      return null;
    }
  }

  Future<({ScriptDocument script, bool? microphone})?> _snapshot(
    Take take,
  ) async {
    if (take.metadataPath == null) return null;
    try {
      final file = File(take.metadataPath!);
      final root = await recordings.resolveSymbolicLinks(),
          resolved = await file.resolveSymbolicLinks();
      if (!resolved.toLowerCase().startsWith(
            '${root.toLowerCase()}${Platform.pathSeparator}',
          ) ||
          await file.length() > 32 * 1024 * 1024) {
        return null;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final savedPath = json['mode'] == 'camera' && json['take'] is Map
          ? (json['take'] as Map)['path']
          : '${file.parent.path}${Platform.pathSeparator}${json['video']}';
      if (savedPath != take.path || json['script'] is! Map<String, Object?>) {
        return null;
      }
      return (
        script: ScriptDocument.fromJson(
          json['script']! as Map<String, Object?>,
        ),
        microphone: json['recordAudio'] is bool
            ? json['recordAudio']! as bool
            : null,
      );
    } on Object {
      return null;
    }
  }

  Future<void> process(ScriptDocument document, Take take) async {
    if (busy) return;
    _cancelled = false;
    result = null;
    problem = null;
    failure = null;
    progress = 0;
    var operation = 'setup';
    _phase(SpeechPhase.preparing);
    try {
      await models.prepare();
      if (_cancelled) throw const SpeechCancelled();
      if (!models.ready) throw StateError('Speech model unavailable');
      final context = await _snapshot(take);
      final snapshot = context?.script;
      final language = snapshot?.language ?? document.language;
      final text = snapshot == null
          ? ''
          : snapshot.usesNotes
          ? snapshot.notes.cards.map((c) => '${c.title}\n${c.body}').join('\n')
          : snapshot.text;
      // Keep UTF-8 intact while bounding the local vocabulary prompt.
      final bytes = <int>[];
      for (final rune in text.runes) {
        final encoded = utf8.encode(String.fromCharCode(rune));
        if (bytes.length + encoded.length > 8192) break;
        bytes.addAll(encoded);
      }
      _phase(SpeechPhase.running);
      operation = 'recognition';
      final windows = await backend.transcribe(
        model: models.file.path,
        media: take.path,
        language: language,
        vocabulary: utf8.decode(bytes),
        duration: take.duration,
        progress: (value) {
          progress = value;
          notifyListeners();
        },
      );
      if (_cancelled) throw const SpeechCancelled();
      operation = 'timing';
      final spoken = await compute(_assemble, {
        'windows': windows,
        'language': language.name,
        'durationUs': take.duration.inMicroseconds,
        'snapshot': snapshot?.toJson(),
        'microphone': context?.microphone,
        'sourcePath': take.path,
      });
      if (_cancelled) throw const SpeechCancelled();
      _phase(SpeechPhase.saving);
      operation = 'saving';
      await results.create(recursive: true);
      final file = File(
        '${results.path}${Platform.pathSeparator}${newId()}.json',
      );
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(spoken.toJson()), flush: true);
      await temp.rename(file.path);
      final current = library.byId(document.id);
      if (current == null || !current.takes.any((t) => t.path == take.path)) {
        throw StateError('Take unavailable');
      }
      await library.save(
        current.copyWith(
          takes: [
            for (final t in current.takes)
              t.path == take.path ? t.withWords(file.path) : t,
          ],
        ),
      );
      result = spoken;
      _phase(SpeechPhase.ready);
    } on SpeechCancelled {
      _phase(SpeechPhase.cancelled);
    } on Object {
      failure = operation;
      problem = switch (operation) {
        'timing' => 'Some word times need review. Your original is safe; no words or cuts were invented. Try speech again.',
        'saving' => 'Spoken words could not be saved. Your original is safe. Check free space, then try again.',
        _ => 'Speech processing could not finish. Your original is safe. Check the model and sound, then try again.',
      };
      _phase(SpeechPhase.failed);
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    if (phase == SpeechPhase.preparing) {
      await models.cancel();
    } else {
      await backend.cancel();
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../cut/clean_plan.dart';
import '../model/mark.dart';
import '../model/script_document.dart';
import '../transcription/script_alignment.dart';
import '../transcription/speech_processor.dart';
import 'script_store.dart';

CleanPlan _build(Map<String, Object?> args) {
  final spoken = SavedTranscript.fromJson(
    args['spoken']! as Map<String, Object?>,
  );
  final snapshot = spoken.snapshot;
  final alignment =
      spoken.alignment != null && snapshot != null && !snapshot.usesNotes
      ? alignTranscript(snapshot, spoken.transcript)
      : null;
  final plan = planQuietCut(
    takeId: args['id']! as String,
    transcript: spoken.transcript,
    quiet: spoken.quiet,
    snapshot: snapshot,
    alignment: alignment,
    screenContext: args['screen'] == true,
  );
  speechOnCut(spoken.transcript, plan.asCutPlan());
  return plan;
}

/// Durable, revision-bound plans. Originals and earlier plan files never change.
class CleanCutStore {
  CleanCutStore(this.directory, this.library);
  final Directory directory;
  final ScriptLibrary library;
  Future<void> _queue = Future.value();

  Future<CleanPlan> create(
    ScriptDocument document,
    Take take,
    SavedTranscript spoken,
  ) async {
    if (spoken.sourcePath != take.path ||
        spoken.transcript.duration != take.duration) {
      throw const FormatException('Take words mismatch');
    }
    final plan = await compute(_build, {
      'spoken': spoken.toJson(),
      'id': newId(),
      'screen': take.mode != TakeMode.camera,
    });
    await save(document.id, take, plan);
    return plan;
  }

  Future<void> save(String documentId, Take take, CleanPlan plan) async {
    final job = _queue.then((_) async {
      final document = library.byId(documentId);
      final current = document?.takes
          .where((t) => t.path == take.path)
          .firstOrNull;
      if (document == null ||
          current == null ||
          current.wordsPath == null ||
          current.wordsPath != take.wordsPath ||
          plan.sourceDuration != take.duration) {
        throw const FormatException('Take changed. Rebuild the cut');
      }
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}${Platform.pathSeparator}${newId()}.json',
      );
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'sourcePath': take.path,
          'wordsPath': take.wordsPath,
          'plan': plan.toJson(),
        }),
        flush: true,
      );
      await temp.rename(file.path);
      final latest = library.byId(documentId);
      final latestTake = latest?.takes
          .where((t) => t.path == take.path)
          .firstOrNull;
      if (latest == null || latestTake?.wordsPath != take.wordsPath) {
        throw const FormatException('Take changed. Rebuild the cut');
      }
      await library.save(
        latest.copyWith(
          takes: [
            for (final t in latest.takes)
              t.path == take.path ? t.withCut(file.path) : t,
          ],
        ),
      );
    });
    _queue = job.then((_) {}, onError: (Object _) {});
    await job;
  }

  Future<CleanPlan?> load(Take take) async {
    if (take.cutPath == null || take.wordsPath == null) return null;
    try {
      final file = File(take.cutPath!);
      final root = await directory.resolveSymbolicLinks(),
          path = await file.resolveSymbolicLinks();
      if (!path.toLowerCase().startsWith(
            '${root.toLowerCase()}${Platform.pathSeparator}',
          ) ||
          await file.length() > 8 * 1024 * 1024) {
        return null;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      if (json['version'] != 1 ||
          json['sourcePath'] != take.path ||
          json['wordsPath'] != take.wordsPath ||
          json['plan'] is! Map<String, Object?>) {
        return null;
      }
      final plan = CleanPlan.fromJson(json['plan']! as Map<String, Object?>);
      return plan.sourceDuration == take.duration ? plan : null;
    } on Object {
      return null;
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../cut/clean_plan.dart';
import '../cut/filler_review.dart';
import '../cut/retake_review.dart';
import '../model/mark.dart';
import '../model/script_document.dart';
import '../transcription/script_alignment.dart';
import '../transcription/speech_processor.dart';
import 'script_store.dart';

Map<String, Object?> _proposalIdentity(CutChange change) => change.toJson()
  ..remove('enabled')
  ..remove('originalRange')
  ..['range'] = change.bounds.toJson();

CleanPlan _build(Map<String, Object?> args) {
  final spoken = SavedTranscript.fromJson(
    args['spoken']! as Map<String, Object?>,
  );
  final snapshot = spoken.snapshot;
  final alignment =
      spoken.alignment != null && snapshot != null && !snapshot.usesNotes
      ? alignTranscript(snapshot, spoken.transcript)
      : null;
  final base = args['base'] is Map<String, Object?>
      ? CleanPlan.fromJson(args['base']! as Map<String, Object?>)
      : planQuietCut(
          takeId: args['id']! as String,
          transcript: spoken.transcript,
          quiet: spoken.quiet,
          snapshot: snapshot,
          alignment: alignment,
          screenContext: args['screen'] == true,
        );
  final fillers = withFillerReview(
    base: base,
    transcript: spoken.transcript,
    quiet: spoken.quiet,
    snapshot: snapshot,
    alignment: alignment,
    screenContext: args['screen'] == true,
  );
  final plan = withRetakeReview(
    base: fillers,
    transcript: spoken.transcript,
    quiet: spoken.quiet,
    snapshot: snapshot,
    alignment: alignment,
    screenContext: args['screen'] == true,
  );
  speechOnCleanCut(spoken.transcript, plan);
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
    SavedTranscript spoken, {
    CleanPlan? base,
  }) async {
    if (spoken.sourcePath != take.path ||
        spoken.transcript.duration != take.duration) {
      throw const FormatException('Take words mismatch');
    }
    if (base != null) {
      final saved = await load(take);
      if (saved == null ||
          jsonEncode(saved.toJson()) != jsonEncode(base.toJson())) {
        throw const FormatException('Cut changed');
      }
    }
    final plan = await compute(_build, {
      'spoken': spoken.toJson(),
      'id': newId(),
      'screen': take.mode != TakeMode.camera,
      'base': base?.toJson(),
    });
    await _save(document.id, take, plan, enrichRetakes: true);
    return plan;
  }

  Future<void> save(String documentId, Take take, CleanPlan plan) =>
      _save(documentId, take, plan);
  Future<void> _save(
    String documentId,
    Take take,
    CleanPlan plan, {
    bool enrichRetakes = false,
  }) async {
    final job = _queue.then((_) async {
      final document = library.byId(documentId);
      final current = document?.takes
          .where((t) => t.path == take.path)
          .firstOrNull;
      if (document == null ||
          current == null ||
          current.wordsPath == null ||
          current.wordsPath != take.wordsPath ||
          current.cutPath != take.cutPath ||
          plan.sourceDuration != take.duration) {
        throw const FormatException('Take changed. Rebuild the cut');
      }
      if (!enrichRetakes) {
        final before = await load(take);
        if (before != null &&
            (before.takeId != plan.takeId ||
                before.language != plan.language ||
                before.fillersReviewed != plan.fillersReviewed ||
                before.retakesReviewed != plan.retakesReviewed ||
                jsonEncode(before.changes.map(_proposalIdentity).toList()) !=
                    jsonEncode(plan.changes.map(_proposalIdentity).toList()))) {
          throw const FormatException('Cut proposals changed');
        }
        // Public switch saves may change selections, never their provenance.
        if ((before?.retakes.isNotEmpty == true || plan.retakes.isNotEmpty) &&
            (before == null ||
                jsonEncode(
                      before.retakes
                          .map((r) => r.withSelected(null).toJson())
                          .toList(),
                    ) !=
                    jsonEncode(
                      plan.retakes
                          .map((r) => r.withSelected(null).toJson())
                          .toList(),
                    ))) {
          throw const FormatException('Retake choices changed');
        }
      }
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}${Platform.pathSeparator}${newId()}.json',
      );
      final temp = File('${file.path}.tmp');
      final data = jsonEncode({
        'version': 1,
        'sourcePath': take.path,
        'wordsPath': take.wordsPath,
        'plan': plan.toJson(),
      });
      if (utf8.encode(data).length > 8 * 1024 * 1024) {
        throw const FormatException('Cut needs smaller sections');
      }
      await temp.writeAsString(data, flush: true);
      await temp.rename(file.path);
      final latest = library.byId(documentId);
      final latestTake = latest?.takes
          .where((t) => t.path == take.path)
          .firstOrNull;
      if (latest == null ||
          latestTake?.wordsPath != take.wordsPath ||
          latestTake?.cutPath != take.cutPath) {
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

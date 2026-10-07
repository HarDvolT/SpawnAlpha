import 'dart:convert';
import 'dart:io';

import '../model/cut_plan.dart';
import '../cut/clean_plan.dart';
import '../model/note_timeline.dart';
import '../model/script_document.dart';
import '../transcription/speech_processor.dart';
import 'publishing_text.dart';

class PublishingJob {
  const PublishingJob(this.spoken, this.plan, this.take, {this.clean});
  final SavedTranscript spoken;
  final CutPlan plan;
  final Take take;
  final CleanPlan? clean;
}

Future<PublishingText> loadPublishingText(PublishingJob job) async {
  String key(String path) =>
      Platform.isWindows ? path.toLowerCase().replaceAll('/', '\\') : path;
  final snapshot = job.spoken.snapshot;
  var moments = const <NoteMoment>[];
  if (snapshot?.usesNotes == true && job.take.metadataPath != null) {
    try {
      final file = File(job.take.metadataPath!);
      if (Platform.isWindows &&
          [file.path, job.take.path].any(
            (path) =>
                !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
                path.substring(2).contains(':') ||
                path.contains('\u0000'),
          )) {
        throw const FormatException('Local metadata required');
      }
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > 16 * 1024 * 1024) {
        throw const FormatException('Invalid take metadata');
      }
      final source = File(job.take.path),
          sourceFolder = await File(job.take.path).parent
              .resolveSymbolicLinks();
      final metadataFolder = await file.parent.resolveSymbolicLinks();
      if (key(sourceFolder) != key(metadataFolder)) {
        throw const FormatException('Invalid metadata location');
      }
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?> ||
          json['version'] != 1 ||
          json['mode'] != job.take.mode.name ||
          json['script'] is! Map<String, Object?>) {
        throw const FormatException('Invalid take metadata');
      }
      final frozen = ScriptDocument.fromJson(
        json['script']! as Map<String, Object?>,
      );
      if (!frozen.usesNotes ||
          frozen.id != snapshot!.id ||
          frozen.language != snapshot.language ||
          jsonEncode(frozen.notes.toJson()) !=
              jsonEncode(snapshot.notes.toJson())) {
        throw const FormatException('Frozen cards mismatch');
      }
      final path = job.take.mode == TakeMode.camera && json['take'] is Map
          ? (json['take'] as Map)['path']
          : json['video'] is String &&
                RegExp(r'^[a-zA-Z0-9_-]+\.mp4$')
                    .hasMatch(json['video'] as String)
          ? '${file.parent.path}${Platform.pathSeparator}${json['video']}'
          : null;
      if (path is! String ||
          key(File(path).absolute.path) != key(source.absolute.path)) {
        throw const FormatException('Take metadata mismatch');
      }
      moments = chapterNoteMoments(
        json['noteChanges'],
        snapshot,
        job.plan.sourceDuration,
      );
    } on Object {
      // Missing or substituted metadata never supplies invented card anchors.
    }
  }
  if (job.spoken.sourcePath != job.take.path ||
      job.take.duration != job.plan.sourceDuration) {
    throw const FormatException('Publishing source mismatch');
  }
  return publishingFromSpeech(
    source: job.spoken.transcript,
    plan: job.plan,
    snapshot: snapshot,
    aligned: job.spoken.alignment != null,
    noteMoments: moments,
    clean: job.clean,
  );
}

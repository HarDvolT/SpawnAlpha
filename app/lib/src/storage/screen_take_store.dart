import 'dart:convert';
import 'dart:io';

import '../model/mark.dart';
import '../model/script_document.dart';
import '../recording/floating_prompter.dart';
import '../recording/recording_inspector.dart';
import '../recording/screen_recording.dart';
import '../recording/screen_source.dart';
import 'script_store.dart';

class PendingScreenTake {
  const PendingScreenTake({
    required this.id,
    required this.videoPath,
    required this.metadataPath,
    required this.snapshot,
    required this.recordedAt,
  });
  final String id, videoPath, metadataPath;
  final ScriptDocument snapshot;
  final DateTime recordedAt;
}

/// A flushed local manifest exists before recording starts. It holds the exact
/// script/presentation, never keys or volatile native handles. Pending files are
/// recoverable after a crash, and a failed library save keeps the manifest.
class ScreenTakeStore {
  ScreenTakeStore(this.directory, this.library, this.inspector);
  final Directory directory;
  final ScriptLibrary library;
  final RecordingInspector inspector;
  Future<void> _tail = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }

  Future<PendingScreenTake> reserve({
    required FloatingPresentation presentation,
    required ScreenSource source,
    required bool recordAudio,
    String? microphoneName,
    required String pace,
  }) => _exclusive(() async {
    await directory.create(recursive: true);
    var id = newId();
    String under(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';
    while (await File(under('$id.json')).exists() ||
        await File(under('$id-screen.mp4')).exists()) {
      id = newId();
    }
    final at = DateTime.now();
    final videoPath = under('$id-screen.mp4');
    final metadataPath = under('$id.json');
    final snapshot = presentation.script.copyWith(
      takes: const [],
      suggestions: const [],
    );
    await _write(File(metadataPath), {
      'version': 1,
      'state': 'pending',
      'id': id,
      'mode': 'screen',
      'video': '$id-screen.mp4',
      'recordedAt': at.toIso8601String(),
      'script': snapshot.toJson(),
      'presentation': presentation.encode(),
      'pace': pace,
      'source': {
        'kind': source.kind.name,
        'name': source.name,
        'width': source.width,
        'height': source.height,
      },
      'recordAudio': recordAudio,
      'microphoneName': ?microphoneName,
    });
    return PendingScreenTake(
      id: id,
      videoPath: videoPath,
      metadataPath: metadataPath,
      snapshot: snapshot,
      recordedAt: at,
    );
  });

  Future<Take> finish(
    PendingScreenTake pending,
    ScreenRecordingStatus status,
  ) => _exclusive(() async {
    final info = await inspector.inspect(pending.videoPath);
    if (!info.readable) {
      throw const FormatException('No readable video in this take');
    }
    return _save(
      pending,
      info,
      recovered: false,
      reason: status.reason.name,
      loudestRmsDb: status.loudestRmsDb,
    );
  });

  Future<Take> _save(
    PendingScreenTake pending,
    RecordingInfo info, {
    required bool recovered,
    required String reason,
    double? loudestRmsDb,
  }) async {
    final take = Take(
      path: pending.videoPath,
      recordedAt: pending.recordedAt,
      duration: info.duration,
      mode: TakeMode.screen,
      metadataPath: pending.metadataPath,
      recovered: recovered,
    );
    final script = library.byId(pending.snapshot.id);
    if (script == null) {
      throw const FormatException('The script is no longer in the library');
    }
    // Save the library first. A crash/retry can see the existing take by path and
    // finish the manifest without duplicating or replacing later script edits.
    final existing = script.takes.where((v) => v.path == take.path).firstOrNull;
    await library.save(
      existing == null
          ? script.copyWith(takes: [...script.takes, take])
          : script,
    );
    final metadata = jsonDecode(
      await File(pending.metadataPath).readAsString(),
    ) as Map<String, dynamic>;
    metadata.addAll({
      'state': recovered ? 'recovered' : 'saved',
      'durationUs': info.duration.inMicroseconds,
      'width': info.width,
      'height': info.height,
      'hasAudio': info.hasAudio,
      'stopReason': reason,
      'loudestRmsDb': ?loudestRmsDb,
    });
    await _write(File(pending.metadataPath), metadata);
    return existing ?? take;
  }

  /// Returns the number recovered. Unreadable/malformed/missing files are kept
  /// for retry; no private paths, script contents or decoder errors are logged.
  Future<int> recover() => _exclusive(_recover);

  Future<int> _recover() async {
    if (!await directory.exists()) return 0;
    var recovered = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final metadata =
            jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
        if (metadata['version'] != 1 ||
            metadata['state'] != 'pending' ||
            metadata['mode'] != 'screen') {
          continue;
        }
        final id = metadata['id'];
        if (id is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
            metadata['video'] != '$id-screen.mp4' ||
            entry.absolute.path !=
                File('${directory.path}${Platform.pathSeparator}$id.json')
                    .absolute
                    .path) {
          continue;
        }
        final video = File(
          '${directory.path}${Platform.pathSeparator}$id-screen.mp4',
        );
        // Don't follow an externally substituted symlink or use an arbitrary
        // path from the manifest. Every recovered file stays inside this folder.
        if (await FileSystemEntity.type(video.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final info = await inspector.inspect(video.path);
        if (!info.readable) continue;
        final pending = PendingScreenTake(
          id: id,
          videoPath: video.path,
          metadataPath: entry.path,
          snapshot: ScriptDocument.fromJson(
            Map<String, Object?>.from(metadata['script'] as Map),
          ),
          recordedAt: DateTime.parse(metadata['recordedAt'] as String),
        );
        await _save(pending, info, recovered: true, reason: 'interrupted');
        ++recovered;
      } on Object {
        /* Preserve local data for a later retry, without private logs. */
      }
    }
    return recovered;
  }

  Future<void> _write(File target, Map<String, Object?> metadata) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(metadata), flush: true);
    await temp.rename(target.path);
  }
}

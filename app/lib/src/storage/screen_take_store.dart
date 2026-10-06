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
    this.cameraPath,
  });
  final String id, videoPath, metadataPath;
  final String? cameraPath;
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
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  Future<PendingScreenTake> reserve({
    required FloatingPresentation presentation,
    required ScreenSource source,
    required bool recordAudio,
    String? microphoneName,
    String? cameraName,
    required String pace,
  }) => _exclusive(() async {
    await directory.create(recursive: true);
    var id = newId();
    String under(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';
    while (await File(under('$id.json')).exists() ||
        await File(under('$id-screen.mp4')).exists() ||
        await File(under('$id-camera.mp4')).exists()) {
      id = newId();
    }
    final at = DateTime.now();
    final videoPath = under('$id-screen.mp4');
    final metadataPath = under('$id.json');
    final cameraPath = cameraName == null ? null : under('$id-camera.mp4');
    final snapshot = presentation.script.copyWith(
      takes: const [],
      suggestions: const [],
    );
    await _write(File(metadataPath), {
      'version': 1,
      'state': 'pending',
      'id': id,
      'mode': cameraPath == null ? 'screen' : 'both',
      'video': '$id-screen.mp4',
      if (cameraPath != null) 'camera': '$id-camera.mp4',
      'cameraName': ?cameraName,
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
      cameraPath: cameraPath,
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
      cameraInfo: await _cameraInfo(pending.cameraPath),
      recovered: false,
      reason: status.reason.name,
      loudestRmsDb: status.loudestRmsDb,
    );
  });

  /// Cancellation before capture creates no video. Keep a small explicit local
  /// record of the cancellation, rather than retrying an empty take on startup.
  Future<void> abandon(PendingScreenTake pending) => _exclusive(() async {
    if (await File(pending.videoPath).exists() ||
        (pending.cameraPath != null &&
            await File(pending.cameraPath!).exists())) {
      return;
    }
    final metadata = jsonDecode(
      await File(pending.metadataPath).readAsString(),
    ) as Map<String, dynamic>;
    metadata['state'] = 'cancelled';
    await _write(File(pending.metadataPath), metadata);
  });

  Future<Take> _save(
    PendingScreenTake pending,
    RecordingInfo info, {
    required bool recovered,
    required String reason,
    double? loudestRmsDb,
    RecordingInfo? cameraInfo,
  }) async {
    final take = Take(
      path: pending.videoPath,
      recordedAt: pending.recordedAt,
      duration: info.duration,
      mode: cameraInfo == null ? TakeMode.screen : TakeMode.both,
      cameraPath: cameraInfo == null ? null : pending.cameraPath,
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
      if (pending.cameraPath != null) 'cameraReadable': cameraInfo != null,
      if (cameraInfo != null) ...{
        'cameraWidth': cameraInfo.width,
        'cameraHeight': cameraInfo.height,
        'cameraDurationUs': cameraInfo.duration.inMicroseconds,
      },
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
            !const ['screen', 'both'].contains(metadata['mode'])) {
          continue;
        }
        final id = metadata['id'];
        if (id is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
            metadata['video'] != '$id-screen.mp4' ||
            (metadata['mode'] == 'both' &&
                metadata['camera'] != '$id-camera.mp4') ||
            (metadata['mode'] == 'screen' && metadata['camera'] != null) ||
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
        final cameraPath = metadata['mode'] == 'both'
            ? '${directory.path}${Platform.pathSeparator}$id-camera.mp4'
            : null;
        // Reject a substituted camera link too. A genuinely missing/unreadable
        // camera can still leave a useful screen take, without following links.
        if (cameraPath != null &&
            await FileSystemEntity.type(cameraPath, followLinks: false) ==
                FileSystemEntityType.link) {
          continue;
        }
        final pending = PendingScreenTake(
          id: id,
          videoPath: video.path,
          metadataPath: entry.path,
          snapshot: ScriptDocument.fromJson(
            Map<String, Object?>.from(metadata['script'] as Map),
          ),
          recordedAt: DateTime.parse(metadata['recordedAt'] as String),
          cameraPath: cameraPath,
        );
        await _save(
          pending,
          info,
          recovered: true,
          reason: 'interrupted',
          cameraInfo: await _cameraInfo(cameraPath),
        );
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

  Future<RecordingInfo?> _cameraInfo(String? path) async {
    if (path == null ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file) {
      return null;
    }
    try {
      final info = await inspector.inspect(path);
      return info.readable ? info : null;
    } on Object {
      // Preserve the screen and the local camera file even if decoding fails.
      return null;
    }
  }
}

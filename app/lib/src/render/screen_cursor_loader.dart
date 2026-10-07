import 'dart:convert';
import 'dart:io';

import '../model/cut_plan.dart';
import '../model/script_document.dart';
import '../recording/activity_trace.dart';
import '../recording/recording_inspector.dart';
import 'screen_cursor.dart';

String _pathKey(String path) =>
    Platform.isWindows ? path.replaceAll('/', '\\').toLowerCase() : path;

Future<FileStat> _regular(File file, {int maximum = 1 << 53}) async {
  final path = file.path;
  if (!file.isAbsolute ||
      path.contains('\u0000') ||
      file.uri.pathSegments.any((part) => part == '.' || part == '..') ||
      Platform.isWindows &&
          (!RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
              path.substring(2).contains(':'))) {
    throw const FormatException('Local cursor files required');
  }
  if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file ||
      _pathKey(await file.resolveSymbolicLinks()) !=
          _pathKey(file.absolute.path)) {
    throw const FormatException('Regular cursor files required');
  }
  final stat = await file.stat();
  if (stat.size < 1 || stat.size > maximum) {
    throw const FormatException('Invalid cursor file size');
  }
  return stat;
}

bool _same(FileStat first, FileStat last) =>
    first.type == last.type &&
    first.size == last.size &&
    first.modified == last.modified;

Future<Map<String, Object?>> _manifest(File file) async {
  const maximum = 32 * 1024 * 1024;
  final bytes = <int>[];
  await for (final chunk in file.openRead(0, maximum + 1)) {
    bytes.addAll(chunk);
  }
  if (bytes.length > maximum) {
    throw const FormatException('Cursor manifest too large');
  }
  final json = jsonDecode(utf8.decode(bytes));
  if (json is! Map<String, Object?>) {
    throw const FormatException('Invalid cursor manifest');
  }
  return json;
}

Future<void> _terminated(File file, int size) async {
  final last = await file.openRead(size - 1, size).expand((b) => b).single;
  if (last != 10) throw const FormatException('Unfinished cursor activity');
}

/// Resolved files are private, ephemeral render inputs. Sound must always use
/// originalPath; picturePath is silent and must never replace the sound source.
/// Construction requires current file, manifest and native decoder checks.
class VerifiedCursorSource {
  VerifiedCursorSource._(
    this.take,
    this.original,
    this.picture,
    this.frames,
    this._metadataStat,
    this._originalStat,
    this._pictureStat,
    this._activityStat,
    this._summary,
  );
  final Take take;
  final RecordingInfo original, picture;
  final int frames;
  final FileStat _metadataStat, _originalStat, _pictureStat, _activityStat;
  final ActivitySummary _summary;
  String get originalPath => take.path;
  String get picturePath => take.cursorFreePath!;

  /// Recheck immediately before a job uses these files, and after activity work.
  Future<bool> unchanged() async {
    try {
      return _same(
            _metadataStat,
            await _regular(File(take.metadataPath!), maximum: 32 * 1024 * 1024),
          ) &&
          _same(_originalStat, await _regular(File(originalPath))) &&
          _same(_pictureStat, await _regular(File(picturePath))) &&
          _same(
            _activityStat,
            await _regular(
              File(take.activityPath!),
              maximum: 256 * 1024 * 1024,
            ),
          );
    } on Object {
      return false;
    }
  }
}

Future<VerifiedCursorSource?> verifyCursorSource(
  Take take,
  RecordingInspector inspector,
) async {
  if (take.mode == TakeMode.camera ||
      take.recovered ||
      take.cursorFreePath == null ||
      take.metadataPath == null ||
      take.activityPath == null ||
      take.duration <= Duration.zero ||
      take.duration > const Duration(hours: 24)) {
    return null;
  }
  try {
    final metadataFile = File(take.metadataPath!),
        source = File(take.path),
        picture = File(take.cursorFreePath!),
        activity = File(take.activityPath!);
    final metadataStat = await _regular(
      metadataFile,
      maximum: 32 * 1024 * 1024,
    );
    final json = await _manifest(metadataFile);
    final id = json['id'],
        frames = json['cursorFreeFrames'],
        cleanDuration = json['cursorFreeDurationUs'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) ||
        json['version'] != 1 ||
        json['state'] != 'saved' ||
        json['mode'] != take.mode.name ||
        json['recordActivity'] != true ||
        json['activityReadable'] != true ||
        json['cursorFreeReadable'] != true ||
        json['cursorFreeVersion'] != 1 ||
        json['cursorFreeMethod'] != 'wgcCursorExcluded' ||
        frames is! int ||
        frames < 1 ||
        frames > 24 * 60 * 60 * 30 ||
        json['durationUs'] != take.duration.inMicroseconds ||
        cleanDuration is! int ||
        (cleanDuration - take.duration.inMicroseconds).abs() > 2 ||
        (frames * 1000000 - take.duration.inMicroseconds * 30).abs() >
            34 * 30 ||
        DateTime.tryParse(
              json['recordedAt'] is String ? json['recordedAt']! as String : '',
            )?.isAtSameMomentAs(take.recordedAt) !=
            true ||
        json['video'] != '$id-screen.mp4' ||
        json['cursorFree'] != '$id-cursor-free.mp4' ||
        json['activity'] != '$id-activity.jsonl') {
      throw const FormatException('Unverified cursor capture');
    }
    final folder = metadataFile.parent.path;
    bool named(File file, String name) =>
        _pathKey(file.absolute.path) ==
        _pathKey(File('$folder${Platform.pathSeparator}$name').absolute.path);
    if (!named(metadataFile, '$id.json') ||
        !named(source, '$id-screen.mp4') ||
        !named(picture, '$id-cursor-free.mp4') ||
        !named(activity, '$id-activity.jsonl') ||
        take.mode == TakeMode.both &&
            (take.cameraPath == null ||
                json['camera'] != '$id-camera.mp4' ||
                json['cameraReadable'] != true ||
                !named(File(take.cameraPath!), '$id-camera.mp4'))) {
      throw const FormatException('Cursor source mismatch');
    }
    final originalStat = await _regular(source),
        pictureStat = await _regular(picture),
        activityStat = await _regular(activity, maximum: 256 * 1024 * 1024);
    final originalInfo = await inspector.inspect(source.path),
        cleanInfo = await inspector.inspect(picture.path);
    if (!originalInfo.readable ||
        !cleanInfo.readable ||
        cleanInfo.hasAudio ||
        originalInfo.width < 1 ||
        originalInfo.height < 1 ||
        originalInfo.width != json['width'] ||
        originalInfo.height != json['height'] ||
        originalInfo.hasAudio != json['hasAudio'] ||
        originalInfo.duration != take.duration ||
        cleanInfo.width != originalInfo.width ||
        cleanInfo.height != originalInfo.height ||
        (cleanInfo.duration - originalInfo.duration).inMicroseconds.abs() > 2 ||
        (cleanInfo.duration.inMicroseconds - cleanDuration).abs() > 2) {
      throw const FormatException('Cursor picture mismatch');
    }
    await _terminated(activity, activityStat.size);
    final summary = await inspectActivity(
      activity,
      maximumBytes: activityStat.size,
    );
    final savedSummary = json['activitySummary'];
    if (!summary.complete ||
        savedSummary is! Map ||
        savedSummary['complete'] != true ||
        savedSummary['events'] != summary.events ||
        savedSummary['durationUs'] is! int ||
        (summary.durationUs - take.duration.inMicroseconds).abs() > 34 ||
        ((savedSummary['durationUs'] as int) - summary.durationUs).abs() > 34) {
      throw const FormatException('Incomplete cursor activity');
    }
    final verified = VerifiedCursorSource._(
      take,
      originalInfo,
      cleanInfo,
      frames,
      metadataStat,
      originalStat,
      pictureStat,
      activityStat,
      summary,
    );
    return await verified.unchanged() ? verified : null;
  } on Object {
    // Optional cursor effects never log paths, private input or decoder errors.
    return null;
  }
}

/// Suitable for a worker isolate: only local I/O and pure immutable data.
Future<ScreenCursor?> loadScreenCursor(
  VerifiedCursorSource source,
  CutPlan plan,
) async {
  try {
    if (plan.sourceDuration != source.take.duration ||
        !await source.unchanged()) {
      return null;
    }
    final file = File(source.take.activityPath!);
    final summary = await inspectActivity(
      file,
      maximumBytes: source._activityStat.size,
    );
    if (!summary.complete ||
        summary.events != source._summary.events ||
        summary.durationUs != source._summary.durationUs) {
      return null;
    }
    final planner = ScreenCursorPlanner();
    await for (final row in activityRows(
      file,
      maximumBytes: source._activityStat.size,
    )) {
      if (row['type'] == 'header' || row['type'] == 'end') continue;
      final event = ActivityEvent.fromJson(row);
      if (event.timeUs < plan.sourceDuration.inMicroseconds) planner.add(event);
    }
    final result = planner.finish(plan);
    return await source.unchanged() ? result : null;
  } on Object {
    return null;
  }
}

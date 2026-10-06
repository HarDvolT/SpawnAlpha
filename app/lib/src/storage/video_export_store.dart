import 'dart:convert';
import 'dart:io';

import '../model/cut_plan.dart';
import '../model/script_document.dart';
import '../model/video_export.dart';
import '../model/mark.dart';
import '../recording/recording_inspector.dart';
import 'script_store.dart';
import '../render/screen_zooms.dart';

class ExportReservation {
  const ExportReservation(
    this.scriptId,
    this.source,
    this.video,
    this.plan, {
    this.srt,
    this.vtt,
    this.screenZooms,
  });
  final String scriptId, source;
  final VideoExport video;
  final CutPlan plan;
  final String? srt, vtt;
  final ScreenZooms? screenZooms;
  Map<String, Object?> toJson({bool complete = false}) => {
    'version': 1,
    'scriptId': scriptId,
    'source': source,
    'video': video.toJson(),
    'plan': plan.toJson(),
    'complete': complete,
    'srt': srt,
    'vtt': vtt,
    if (screenZooms != null) 'screenZooms': screenZooms!.toJson(),
  };
}

/// A flushed job journal, new output names and revision-bound local history.
/// Interrupted renders are never promoted to finished exports. A completed video
/// survives a failed library save and is attached on the next recovery pass.
class VideoExportStore {
  VideoExportStore(this.directory, this.library, this.inspector);
  final Directory directory;
  final ScriptLibrary library;
  final RecordingInspector inspector;
  Future<void> _queue = Future.value();
  Directory get pending =>
      Directory('${directory.path}${Platform.pathSeparator}pending');
  File file(VideoExport video, [String extension = 'mp4']) =>
      File('${directory.path}${Platform.pathSeparator}${video.id}.$extension');
  File _journal(VideoExport video) =>
      File('${pending.path}${Platform.pathSeparator}${video.id}.json');
  Future<void> _write(File file, Object json) async {
    final bytes = utf8.encode(jsonEncode(json));
    // Never write a journal too large for the bounded recovery reader.
    if (bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('Export metadata is too large');
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  Future<ExportReservation> reserve(
    String scriptId,
    Take take,
    VideoExport video,
    CutPlan plan, {
    String? srt,
    String? vtt,
    ScreenZooms? screenZooms,
  }) async {
    if ((screenZooms?.count ?? 0) != video.zoomCount ||
        (screenZooms?.steps.any((s) => s.time > plan.duration) ?? false) ||
        plan.sourceDuration != take.duration ||
        plan.duration != video.duration ||
        video.wordsPath != take.wordsPath ||
        video.cutPath != take.cutPath ||
        video.captions != (srt != null && vtt != null) ||
        (srt?.length ?? 0) > 8 * 1024 * 1024 ||
        (vtt?.length ?? 0) > 8 * 1024 * 1024) {
      throw const FormatException('Export revision mismatch');
    }
    await pending.create(recursive: true);
    if (await file(video).exists() || await _journal(video).exists()) {
      throw const FormatException('Export already exists');
    }
    final reservation = ExportReservation(
      scriptId,
      take.path,
      video,
      plan,
      srt: srt,
      vtt: vtt,
      screenZooms: screenZooms,
    );
    await _write(_journal(video), reservation.toJson());
    return reservation;
  }

  Future<bool> _under(File file, Directory root, int maxBytes) async {
    try {
      final resolvedRoot = await root.resolveSymbolicLinks(),
          resolved = await file.resolveSymbolicLinks();
      return resolved.toLowerCase().startsWith(
            '${resolvedRoot.toLowerCase()}${Platform.pathSeparator}',
          ) &&
          await file.length() <= maxBytes;
    } on Object {
      return false;
    }
  }

  Future<List<VideoExport>> load(Take take) async {
    if (take.exportsPath == null) return [];
    try {
      final catalog = File(take.exportsPath!);
      if (!await _under(catalog, directory, 8 * 1024 * 1024)) return [];
      final json =
          jsonDecode(await catalog.readAsString()) as Map<String, Object?>;
      if (json['version'] != 1 ||
          json['source'] != take.path ||
          json['videos'] is! List ||
          (json['videos']! as List).length > 2000) {
        return [];
      }
      final records = (json['videos']! as List)
          .map((v) => VideoExport.fromJson(v as Map<String, Object?>))
          .toList();
      if (records.map((v) => v.id).toSet().length != records.length) return [];
      final found = <VideoExport>[];
      for (final video in records) {
        if (await _under(file(video), directory, 1 << 53)) found.add(video);
      }
      return found;
    } on Object {
      return [];
    }
  }

  Future<void> finish(ExportReservation reservation) async {
    final video = reservation.video;
    if (!await _under(file(video), directory, 1 << 53)) {
      throw const FormatException('Export unavailable');
    }
    final info = await inspector.inspect(file(video).path);
    if (!info.readable ||
        info.width != video.format.width ||
        info.height != video.format.height ||
        (info.duration - video.duration).abs() >
            const Duration(milliseconds: 50)) {
      throw const FormatException('Export verification failed');
    }
    await _write(_journal(video), reservation.toJson(complete: true));
    // Once verified, recovery can retry captions, metadata and the library.
    if (video.captions) {
      await file(video, 'srt').writeAsString(reservation.srt!, flush: true);
      await file(video, 'vtt').writeAsString(reservation.vtt!, flush: true);
    }
    await _write(file(video, 'json'), {
      'version': 1,
      // Portable export metadata omits private local revision file paths.
      'video': video.toJson()
        ..remove('wordsPath')
        ..remove('cutPath'),
      'plan': reservation.plan.toJson(),
      if (reservation.screenZooms != null)
        'screenZooms': reservation.screenZooms!.toJson(),
    });
    await _attach(reservation);
  }

  Future<void> _attach(ExportReservation reservation) async {
    final job = _queue.then((_) async {
      final doc = library.byId(reservation.scriptId);
      final take = doc?.takes
          .where((t) => t.path == reservation.source)
          .firstOrNull;
      if (doc == null || take == null) {
        throw const FormatException('Take no longer available');
      }
      final existing = await load(take);
      if (existing.length >= 2000 &&
          !existing.any((v) => v.id == reservation.video.id)) {
        throw const FormatException('Export history is full');
      }
      final catalog = File(
        '${directory.path}${Platform.pathSeparator}${newId()}-history.json',
      );
      await _write(catalog, {
        'version': 1,
        'source': take.path,
        'videos': [
          reservation.video.toJson(),
          for (final old in existing)
            if (old.id != reservation.video.id) old.toJson(),
        ],
      });
      final latest = library.byId(reservation.scriptId);
      if (latest == null ||
          !latest.takes.any((t) => t.path == reservation.source)) {
        throw const FormatException('Take no longer available');
      }
      await library.save(
        latest.copyWith(
          takes: [
            for (final t in latest.takes)
              t.path == reservation.source ? t.withExports(catalog.path) : t,
          ],
        ),
      );
      await _journal(reservation.video).delete();
    });
    _queue = job.then((_) {}, onError: (Object _) {});
    await job;
  }

  Future<void> discard(ExportReservation reservation) async {
    // Called only after this job has ended/cancelled, never for a history item.
    for (final extension in ['mp4', 'srt', 'vtt', 'json']) {
      final output = file(reservation.video, extension);
      if (await _under(output, directory, 1 << 53)) {
        try {
          await output.delete();
        } on FileSystemException {
          /* Keep for retry. */
        }
      }
    }
    final journal = _journal(reservation.video);
    if (await _under(journal, pending, 32 * 1024 * 1024)) {
      try {
        await journal.delete();
      } on FileSystemException {
        /* Keep for retry. */
      }
    }
  }

  Future<int> recover() async {
    if (!await pending.exists()) return 0;
    var recovered = 0;
    await for (final item in pending.list(followLinks: false)) {
      if (item is! File || !item.path.endsWith('.json')) continue;
      try {
        if (!await _under(item, pending, 32 * 1024 * 1024)) continue;
        final json =
            jsonDecode(await item.readAsString()) as Map<String, Object?>;
        if (json['version'] != 1 ||
            json['complete'] != true ||
            json['scriptId'] is! String ||
            json['source'] is! String) {
          continue;
        }
        final video = VideoExport.fromJson(
          json['video']! as Map<String, Object?>,
        );
        if (item.absolute.path.toLowerCase() !=
            _journal(video).absolute.path.toLowerCase()) {
          continue;
        }
        final plan = CutPlan.fromJson(json['plan']! as Map<String, Object?>);
        final zooms = json['screenZooms'] == null
            ? null
            : ScreenZooms.fromJson(
                json['screenZooms']! as Map<String, Object?>,
              );
        if ((zooms?.count ?? 0) != video.zoomCount ||
            (zooms?.steps.any((s) => s.time > plan.duration) ?? false)) {
          continue;
        }
        if (plan.duration != video.duration) continue;
        final srt = json['srt'], vtt = json['vtt'];
        if (video.captions &&
            (srt is! String ||
                vtt is! String ||
                srt.length > 8 * 1024 * 1024 ||
                vtt.length > 8 * 1024 * 1024)) {
          continue;
        }
        await finish(
          ExportReservation(
            json['scriptId']! as String,
            json['source']! as String,
            video,
            plan,
            srt: srt as String?,
            vtt: vtt as String?,
            screenZooms: zooms,
          ),
        );
        ++recovered;
      } on Object {
        /* Preserve for retry; never log media/text/path diagnostics. */
      }
    }
    return recovered;
  }
}

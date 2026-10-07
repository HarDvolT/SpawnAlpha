import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cut/clean_plan.dart';
import '../model/caption_style.dart';
import '../model/script_document.dart';
import '../model/video_export.dart';
import 'export_processor.dart';

/// Immutable choices for every version in one batch. Each version still owns
/// its existing verified media, metadata and completed-job recovery journal.
class ExportChoices {
  const ExportChoices({
    this.clean,
    this.camera = true,
    this.burnedCaptions = true,
    this.captionStyle = CaptionStyle.readable,
    this.captionMotion = true,
    this.softAudioJoins = true,
    this.roomToneJoins = false,
    this.autoZoom = true,
    this.clickHighlights = true,
    this.showShortcuts = true,
    this.screenFrame = true,
    this.cameraPunch = true,
    this.cameraClear = true,
    this.motionBlur = true,
    this.balanceSound = false,
    this.softenSharpSound = false,
    this.reduceNoise = false,
  });
  final CleanPlan? clean;
  final CaptionStyle captionStyle;
  final bool camera,
      burnedCaptions,
      captionMotion,
      softAudioJoins,
      roomToneJoins,
      autoZoom,
      clickHighlights,
      showShortcuts,
      screenFrame,
      cameraPunch,
      cameraClear,
      motionBlur,
      balanceSound,
      softenSharpSound,
      reduceNoise;
  Future<VideoExport?> save(
    ExportProcessor job,
    ScriptDocument script,
    Take take,
    VideoFormat format,
  ) => job.export(
    script,
    take,
    format,
    clean: clean,
    camera: camera,
    burnedCaptions: burnedCaptions,
    captionStyle: captionStyle,
    captionMotion: captionMotion,
    softAudioJoins: softAudioJoins,
    roomToneJoins: roomToneJoins,
    autoZoom: autoZoom,
    clickHighlights: clickHighlights,
    showShortcuts: showShortcuts,
    screenFrame: screenFrame,
    cameraPunch: cameraPunch,
    cameraClear: cameraClear,
    motionBlur: motionBlur,
    balanceSound: balanceSound,
    softenSharpSound: softenSharpSound,
    reduceNoise: reduceNoise,
  );
}

/// One native job at a time. A cancelled/failed queue never removes completed
/// versions. The immutable request stays tied to the original words/cut.
class ExportBatch extends ChangeNotifier {
  ExportBatch(this.job);
  final ExportProcessor job;
  bool _running = false, _cancelled = false, _active = false, _disposed = false;
  List<VideoExport> _completed = [];
  List<VideoFormat> _formats = const [];
  bool get busy => _running;
  bool get cancelled => _cancelled;
  String? problem;
  int get total => _formats.length;
  int get saved => _completed.length;
  VideoFormat? get current =>
      _running && saved < total ? _formats[saved] : null;
  List<VideoExport> get completed => List.unmodifiable(_completed);
  double get progress =>
      total == 0 ? 0 : (saved + (_active ? job.progress : 0)) / total;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<List<VideoExport>> run(
    ScriptDocument script,
    Take take,
    Iterable<VideoFormat> formats, {
    ExportChoices choices = const ExportChoices(),
  }) async {
    if (_disposed) throw StateError('Batch disposed');
    if (_running || job.busy) return const [];
    final requested = List<VideoFormat>.unmodifiable(formats);
    if (requested.isEmpty ||
        requested.length > VideoFormat.values.length ||
        requested.toSet().length != requested.length) {
      throw ArgumentError('Choose distinct formats');
    }
    _formats = requested;
    _completed = [];
    problem = null;
    _cancelled = false;
    _running = true;
    job.addListener(_notify);
    _notify();
    try {
      for (final format in requested) {
        if (_cancelled || _disposed) break;
        _active = true;
        final video = await choices.save(job, script, take, format);
        _active = false;
        if (video == null) {
          problem = job.problem;
          _cancelled = _cancelled || job.phase == ExportPhase.cancelled;
          break;
        }
        _completed.add(video);
        _notify();
      }
    } on Object {
      problem = 'The remaining videos could not be saved. Finished videos and your original are safe.';
    } finally {
      _active = false;
      _running = false;
      job.removeListener(_notify);
      _notify();
    }
    return completed;
  }

  Future<void> cancel() async {
    if (!_running) return;
    _cancelled = true;
    _notify();
    await job.cancel();
  }

  @override
  void dispose() {
    _cancelled = _disposed = true;
    job.removeListener(_notify);
    if (_running) unawaited(job.cancel());
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../cut/clean_plan.dart';
import '../model/cut_plan.dart';
import '../model/caption_style.dart';
import '../model/script_document.dart';
import '../model/video_export.dart';
import '../model/mark.dart';
import '../storage/clean_cut_store.dart';
import '../storage/video_export_store.dart';
import '../transcription/captions.dart';
import '../transcription/caption_cues.dart';
import '../transcription/word_timing.dart';
import '../transcription/speech_processor.dart';
import 'video_renderer.dart';
import 'screen_zooms.dart';
import 'screen_zoom_loader.dart';
import '../theme/tokens.g.dart';

enum ExportPhase { idle, preparing, rendering, saving, done, cancelled, failed }

class _CaptionJob {
  const _CaptionJob(this.source, this.kept, this.plan, this.style);
  final SavedTranscript source;
  final WordTranscript kept;
  final CutPlan plan;
  final CaptionStyle style;
}

(List<Caption>, List<Caption>) _exportCaptions(_CaptionJob job) {
  final cues = captionCuesOnCut(
    source: job.source.transcript,
    kept: job.kept,
    plan: job.plan,
    snapshot: job.source.snapshot,
    aligned: job.source.alignment != null,
  );
  final phrases = captionsFromSpeech(job.kept, cues: cues);
  return (
    phrases,
    job.style == CaptionStyle.punch
        ? captionsFromSpeech(job.kept, cues: cues, punch: true)
        : phrases,
  );
}

class ExportProcessor extends ChangeNotifier {
  ExportProcessor(this.renderer, this.store, this.cuts, this.loadWords);
  final VideoRenderer renderer;
  final VideoExportStore store;
  final CleanCutStore cuts;
  final Future<SavedTranscript?> Function(Take) loadWords;
  ExportPhase phase = ExportPhase.idle;
  double progress = 0;
  String? problem, source, notice;
  VideoExport? result;
  bool _cancelled = false;
  bool get busy =>
      phase == ExportPhase.preparing ||
      phase == ExportPhase.rendering ||
      phase == ExportPhase.saving;
  void _phase(ExportPhase value) {
    phase = value;
    notifyListeners();
  }

  Future<VideoExport?> export(
    ScriptDocument script,
    Take take,
    VideoFormat format, {
    CleanPlan? clean,
    bool camera = true,
    bool burnedCaptions = true,
    CaptionStyle captionStyle = CaptionStyle.readable,
    bool captionMotion = true,
    bool softAudioJoins = true,
    bool autoZoom = true,
    bool clickHighlights = true,
    bool showShortcuts = true,
  }) async {
    if (busy) return null;
    source = take.path;
    result = null;
    problem = null;
    notice = null;
    progress = 0;
    _cancelled = false;
    _phase(ExportPhase.preparing);
    ExportReservation? reserved;
    try {
      await store.recover();
      final latest = store.library
          .byId(script.id)
          ?.takes
          .where((t) => t.path == take.path)
          .firstOrNull;
      if (latest == null ||
          latest.wordsPath != take.wordsPath ||
          latest.cutPath != take.cutPath) {
        throw const FormatException('Take changed');
      }
      if (take.cutPath != null) {
        final saved = await cuts.load(take);
        if (saved == null ||
            clean == null ||
            jsonEncode(saved.toJson()) != jsonEncode(clean.toJson())) {
          throw const FormatException('Cut changed');
        }
      }
      if (take.cutPath == null && clean != null) {
        throw const FormatException('Unsaved cut');
      }
      final spoken = take.wordsPath == null ? null : await loadWords(take);
      if (take.wordsPath != null && spoken == null) {
        throw const FormatException('Saved words unavailable');
      }
      if (spoken != null &&
          (spoken.sourcePath != take.path ||
              spoken.transcript.duration != take.duration ||
              take.wordsPath == null)) {
        throw const FormatException('Words mismatch');
      }
      final plan =
          clean?.asCutPlan() ??
          CutPlan(
            takeId: newId(),
            language: spoken?.transcript.language ?? script.language,
            sourceDuration: take.duration,
            ranges: [SourceRange(start: Duration.zero, end: take.duration)],
          );
      final timed = spoken == null
          ? null
          : clean == null
          ? speechOnCut(spoken.transcript, plan)
          : speechOnCleanCut(spoken.transcript, clean);
      final zooms =
          (autoZoom || clickHighlights || showShortcuts) &&
              take.mode != TakeMode.camera &&
              take.activityPath != null
          ? await compute(
              loadScreenZooms,
              ScreenZoomJob(
                take.path,
                take.activityPath!,
                plan,
                ZoomPolicy(
                  window: SaScreenFx.zoomClusterWindow,
                  distance: SaScreenFx.zoomClusterDistance,
                  lead: SaScreenFx.zoomLead,
                  hold: SaScreenFx.zoomHold,
                  factor: SaScreenFx.zoomDefault,
                  maximum: SaScreenFx.zoomMax,
                  typingMinimum: SaScreenFx.zoomTypingMinimum.toInt(),
                  smallTarget: SaScreenFx.zoomSmallTarget,
                  pointWindow: SaScreenFx.zoomPointWindow,
                ),
                spoken: spoken,
                autoZoom: autoZoom,
                clickDuration: clickHighlights
                    ? SaScreenFx.rippleDuration
                    : Duration.zero,
                shortcutDuration: showShortcuts
                    ? SaScreenFx.keycapDuration
                    : Duration.zero,
              ),
            )
          : LoadedScreenZooms(ScreenZooms(0, const []));
      if (_cancelled) throw const RenderCancelled();
      if (zooms.unavailable) notice = 'Screen activity is unavailable. This video keeps the whole picture.';
      final video = VideoExport(
        id: newId(),
        format: format,
        duration: plan.duration,
        createdAt: DateTime.now(),
        wordsPath: take.wordsPath,
        cutPath: take.cutPath,
        captions: timed != null && timed.words.isNotEmpty,
        camera: camera && take.mode == TakeMode.both && take.cameraPath != null,
        burnedCaptions:
            burnedCaptions && timed != null && timed.words.isNotEmpty,
        captionStyle: burnedCaptions ? captionStyle : CaptionStyle.readable,
        captionMotion: captionMotion,
        softAudioJoins: softAudioJoins && plan.hasJoins,
        zoomCount: zooms.zooms.count,
        clickCount: zooms.clicks?.count ?? 0,
        shortcutCount: zooms.shortcuts?.count ?? 0,
      );
      final captionTracks = video.captions
          ? await compute(
              _exportCaptions,
              _CaptionJob(spoken!, timed!, plan, video.captionStyle),
            )
          : null;
      final captions = captionTracks?.$1;
      final reservation = await store.reserve(
        script.id,
        take,
        video,
        plan,
        srt: captions == null ? null : subtitleText(captions),
        vtt: captions == null ? null : subtitleText(captions, vtt: true),
        screenZooms: zooms.zooms,
        screenClicks: zooms.clicks,
        screenShortcuts: zooms.shortcuts,
      );
      reserved = reservation;
      if (_cancelled) throw const RenderCancelled();
      _phase(ExportPhase.rendering);
      await renderer.render(
        VideoRenderRequest(
          source: take.path,
          output: store.file(video).path,
          camera: video.camera ? take.cameraPath : null,
          plan: plan,
          format: format,
          captions: video.burnedCaptions ? captionTracks!.$2 : const [],
          captionStyle: video.captionStyle,
          captionMotion: video.captionMotion,
          softAudioJoins: video.softAudioJoins,
          screenZooms: zooms.zooms,
          screenClicks: zooms.clicks,
          screenShortcuts: zooms.shortcuts,
        ),
        (amount) {
          progress = amount;
          notifyListeners();
        },
      );
      if (_cancelled) throw const RenderCancelled();
      _phase(ExportPhase.saving);
      await store.finish(reservation);
      result = video;
      _phase(ExportPhase.done);
      return video;
    } on RenderCancelled {
      if (reserved != null) await store.discard(reserved);
      _phase(ExportPhase.cancelled);
    } on Object {
      problem = phase == ExportPhase.saving
          ? 'The video could not be added to your take. Your original is safe. Check free space and try again.'
          : 'Video export could not finish. Your original and cut are safe. Check free space and try again.';
      _phase(ExportPhase.failed);
    }
    return null;
  }

  Future<void> cancel() async {
    if (phase == ExportPhase.saving) return;
    _cancelled = true;
    try {
      await renderer.cancel();
    } on Object {
      /* Generic UI only. */
    }
  }
}

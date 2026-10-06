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
import '../transcription/speech_processor.dart';
import 'video_renderer.dart';

enum ExportPhase { idle, preparing, rendering, saving, done, cancelled, failed }

class ExportProcessor extends ChangeNotifier {
  ExportProcessor(this.renderer, this.store, this.cuts, this.loadWords);
  final VideoRenderer renderer;
  final VideoExportStore store;
  final CleanCutStore cuts;
  final Future<SavedTranscript?> Function(Take) loadWords;
  ExportPhase phase = ExportPhase.idle;
  double progress = 0;
  String? problem, source;
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
  }) async {
    if (busy) return null;
    source = take.path;
    result = null;
    problem = null;
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
      );
      final captions = video.captions ? captionsFromSpeech(timed!) : null;
      final reservation = await store.reserve(
        script.id,
        take,
        video,
        plan,
        srt: captions == null ? null : subtitleText(captions),
        vtt: captions == null ? null : subtitleText(captions, vtt: true),
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
          captions: video.burnedCaptions ? captions! : const [],
          captionStyle: video.captionStyle,
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

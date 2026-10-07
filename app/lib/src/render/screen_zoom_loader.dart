import 'dart:io';

import '../model/cut_plan.dart';
import '../recording/activity_trace.dart';
import '../transcription/pointing_phrases.dart';
import '../transcription/speech_processor.dart';
import 'screen_zooms.dart';
import 'screen_clicks.dart';
import 'screen_shortcuts.dart';

class ScreenZoomJob {
  const ScreenZoomJob(
    this.source,
    this.activity,
    this.plan,
    this.policy, {
    this.spoken,
    this.autoZoom = true,
    this.clickDuration = Duration.zero,
    this.shortcutDuration = Duration.zero,
  });
  final String source, activity;
  final CutPlan plan;
  final ZoomPolicy policy;
  final SavedTranscript? spoken;
  final bool autoZoom;
  final Duration clickDuration;
  final Duration shortcutDuration;
}

class LoadedScreenZooms {
  const LoadedScreenZooms(
    this.zooms, {
    this.unavailable = false,
    this.clicks,
    this.shortcuts,
  });
  final ScreenZooms zooms;
  final bool unavailable;
  final ScreenClicks? clicks;
  final ScreenShortcuts? shortcuts;
}

Future<LoadedScreenZooms> loadScreenZooms(ScreenZoomJob job) async {
  try {
    final file = File(job.activity);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > 256 * 1024 * 1024) {
      throw const FormatException('Invalid screen activity');
    }
    final sourceFolder = await File(job.source).parent.resolveSymbolicLinks();
    final activityFolder = await file.parent.resolveSymbolicLinks();
    if ((Platform.isWindows ? sourceFolder.toLowerCase() : sourceFolder) !=
        (Platform.isWindows ? activityFolder.toLowerCase() : activityFolder)) {
      throw const FormatException('Invalid activity location');
    }
    await inspectActivity(file, limit: job.plan.sourceDuration);
    var pointing = <SourceRange>[];
    final spoken = job.spoken;
    if (job.autoZoom &&
        spoken != null &&
        spoken.sourcePath == job.source &&
        spoken.transcript.duration == job.plan.sourceDuration &&
        spoken.transcript.language == job.plan.language) {
      try {
        pointing = pointingPhrases(
          source: spoken.transcript,
          snapshot: spoken.snapshot,
          aligned: spoken.alignment != null,
          maximumSpan: job.policy.window,
        );
      } on FormatException {
        // An oversized/unusable script cannot disable ordinary activity zooms.
      }
    }
    final planner = ScreenZoomPlanner(job.policy, pointing: pointing);
    final clicks = job.clickDuration > Duration.zero
        ? ScreenClickPlanner(job.clickDuration)
        : null;
    final shortcuts = job.shortcutDuration > Duration.zero
        ? ScreenShortcutPlanner(job.shortcutDuration)
        : null;
    await for (final row in activityRows(file)) {
      if (row['type'] == 'header' || row['type'] == 'end') continue;
      final event = ActivityEvent.fromJson(row);
      if (event.timeUs < job.plan.sourceDuration.inMicroseconds) {
        if (job.autoZoom) planner.add(event);
        clicks?.add(event);
        shortcuts?.add(event);
      }
    }
    return LoadedScreenZooms(
      planner.finish(job.plan),
      clicks: clicks?.finish(job.plan),
      shortcuts: shortcuts?.finish(job.plan),
    );
  } on Object {
    // Generic information only, never private paths, activity or exceptions.
    return LoadedScreenZooms(ScreenZooms(0, const []), unavailable: true);
  }
}

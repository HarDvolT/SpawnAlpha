import 'dart:io';

import '../model/cut_plan.dart';
import '../recording/activity_trace.dart';
import 'screen_zooms.dart';

class ScreenZoomJob {
  const ScreenZoomJob(this.source, this.activity, this.plan, this.policy);
  final String source, activity;
  final CutPlan plan;
  final ZoomPolicy policy;
}

class LoadedScreenZooms {
  const LoadedScreenZooms(this.zooms, {this.unavailable = false});
  final ScreenZooms zooms;
  final bool unavailable;
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
    final planner = ScreenZoomPlanner(job.policy);
    await for (final row in activityRows(file)) {
      if (row['type'] == 'header' || row['type'] == 'end') continue;
      final event = ActivityEvent.fromJson(row);
      if (event.timeUs < job.plan.sourceDuration.inMicroseconds) {
        planner.add(event);
      }
    }
    return LoadedScreenZooms(planner.finish(job.plan));
  } on Object {
    // Generic information only, never private paths, activity or exceptions.
    return LoadedScreenZooms(ScreenZooms(0, const []), unavailable: true);
  }
}

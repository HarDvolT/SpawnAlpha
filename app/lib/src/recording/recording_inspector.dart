import 'dart:async';
import 'dart:io';

import '../theme/tokens.g.dart';
import 'screen_recording.dart';

class RecordingInfo {
  const RecordingInfo({
    this.readable = false,
    this.hasAudio = false,
    this.width = 0,
    this.height = 0,
    this.duration = Duration.zero,
  });
  final bool readable, hasAudio;
  final int width, height;
  final Duration duration;
}

abstract class RecordingInspector {
  factory RecordingInspector.platform() => Platform.isWindows
      ? const WindowsRecordingInspector()
      : const UnsupportedRecordingInspector();
  Future<RecordingInfo> inspect(String path);
}

class WindowsRecordingInspector implements RecordingInspector {
  const WindowsRecordingInspector();
  @override
  Future<RecordingInfo> inspect(String path) async {
    final channel = WindowsScreenRecordings.channel;
    final id = await channel.invokeMethod<int>('inspectStart', {'path': path});
    if (id == null || id <= 0) {
      throw const FormatException('Invalid recording check');
    }
    try {
      // Recovery may inspect the encoded samples of a long, unfinished take.
      final attempts =
          const Duration(minutes: 1).inMicroseconds ~/
          SaDurations.previewPoll.inMicroseconds;
      for (var attempt = 0; attempt < attempts; ++attempt) {
        final info = await channel.invokeMapMethod<String, Object?>(
          'inspectStatus',
          {'sessionId': id},
        );
        if (info == null) {
          throw const FormatException('Missing recording check');
        }
        if (info['ready'] == true) {
          if (info['readable'] != true) return const RecordingInfo();
          final width = info['width'],
              height = info['height'],
              duration = info['durationUs'];
          if (width is! int ||
              height is! int ||
              duration is! int ||
              width <= 0 ||
              height <= 0 ||
              duration <= 0) {
            throw const FormatException('Invalid recording details');
          }
          return RecordingInfo(
            readable: true,
            hasAudio: info['hasAudio'] == true,
            width: width,
            height: height,
            duration: Duration(microseconds: duration),
          );
        }
        await Future<void>.delayed(SaDurations.previewPoll);
      }
      throw TimeoutException('Recording check did not finish');
    } on Object {
      await channel.invokeMethod<void>('inspectCancel', {'sessionId': id});
      rethrow;
    }
  }
}

class UnsupportedRecordingInspector implements RecordingInspector {
  const UnsupportedRecordingInspector();
  @override
  Future<RecordingInfo> inspect(String path) async => const RecordingInfo();
}

import 'caption_style.dart';

enum VideoFormat {
  landscape('16:9 · 1080p', 1920, 1080),
  portrait('9:16 · 1080p', 1080, 1920),
  feed('4:5 · 1080p', 1080, 1350),
  landscape4k('16:9 · 4K', 3840, 2160);

  const VideoFormat(this.label, this.width, this.height);
  final String label;
  final int width, height;
}

/// A finished, local export tied to the exact words/cut used. Earlier exports
/// remain available after another speech pass or restoring a change.
class VideoExport {
  VideoExport({
    required this.id,
    required this.format,
    required this.duration,
    required this.createdAt,
    this.wordsPath,
    this.cutPath,
    this.captions = false,
    this.camera = false,
    this.burnedCaptions = false,
    this.captionStyle = CaptionStyle.readable,
    this.captionMotion = true,
  }) {
    if ((burnedCaptions && !captions) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) ||
        duration <= Duration.zero ||
        duration > const Duration(hours: 24)) {
      throw ArgumentError('Invalid video export');
    }
  }
  final String id;
  final VideoFormat format;
  final CaptionStyle captionStyle;
  final Duration duration;
  final DateTime createdAt;
  final String? wordsPath, cutPath;
  final bool captions, camera, burnedCaptions;
  final bool captionMotion;
  Map<String, Object?> toJson() => {
    'id': id,
    'format': format.name,
    'durationUs': duration.inMicroseconds,
    'createdAt': createdAt.toIso8601String(),
    'wordsPath': wordsPath,
    'cutPath': cutPath,
    'captions': captions,
    'camera': camera,
    'burnedCaptions': burnedCaptions,
    if (burnedCaptions) 'captionStyle': captionStyle.name,
    if (burnedCaptions) 'captionMotion': captionMotion,
  };
  factory VideoExport.fromJson(Map<String, Object?> json) {
    final format = VideoFormat.values
        .where((f) => f.name == json['format'])
        .firstOrNull;
    final id = json['id'],
        duration = json['durationUs'],
        date = json['createdAt'];
    final style = json['captionStyle'] == null
        ? CaptionStyle.readable
        : CaptionStyle.values
              .where((s) => s.name == json['captionStyle'])
              .firstOrNull;
    if (format == null ||
        style == null ||
        id is! String ||
        duration is! int ||
        date is! String ||
        (json['wordsPath'] != null && json['wordsPath'] is! String) ||
        (json['cutPath'] != null && json['cutPath'] is! String) ||
        json['captions'] is! bool ||
        json['camera'] is! bool ||
        (json['burnedCaptions'] != null && json['burnedCaptions'] is! bool) ||
        (json['captionMotion'] != null && json['captionMotion'] is! bool)) {
      throw const FormatException('Invalid video export');
    }
    try {
      return VideoExport(
        id: id,
        format: format,
        duration: Duration(microseconds: duration),
        createdAt: DateTime.parse(date),
        wordsPath: json['wordsPath'] as String?,
        cutPath: json['cutPath'] as String?,
        captions: json['captions'] == true,
        camera: json['camera'] == true,
        burnedCaptions: json['burnedCaptions'] == true,
        captionStyle: style,
        captionMotion: json['captionMotion'] as bool? ?? true,
      );
    } on ArgumentError {
      throw const FormatException('Invalid video export');
    }
  }
}

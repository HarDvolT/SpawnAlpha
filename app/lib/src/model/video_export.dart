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
    this.softAudioJoins = false,
    this.zoomCount = 0,
    this.clickCount = 0,
    this.shortcutCount = 0,
    this.screenFrame = false,
    this.cameraPunchCount = 0,
    this.cameraClear = false,
    this.motionBlur = false,
    this.balanceSound = false,
    this.softenSharpSound = false,
  }) {
    if (motionBlur && zoomCount == 0 ||
        cameraClear && !camera ||
        cameraPunchCount < 0 ||
        cameraPunchCount > 10000 ||
        shortcutCount < 0 ||
        shortcutCount > 20000 ||
        clickCount < 0 ||
        clickCount > 20000 ||
        zoomCount < 0 ||
        zoomCount > 10000 ||
        (burnedCaptions && !captions) ||
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
  final bool softAudioJoins;
  final int zoomCount;
  final int clickCount;
  final int shortcutCount;
  final bool screenFrame;
  final int cameraPunchCount;
  final bool cameraClear;
  final bool motionBlur;
  final bool balanceSound;
  final bool softenSharpSound;
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
    'softAudioJoins': softAudioJoins,
    'zoomCount': zoomCount,
    'clickCount': clickCount,
    'shortcutCount': shortcutCount,
    'screenFrame': screenFrame,
    'cameraPunchCount': cameraPunchCount,
    'cameraClear': cameraClear,
    'motionBlur': motionBlur,
    'balanceSound': balanceSound,
    'softenSharpSound': softenSharpSound,
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
        (json['captionMotion'] != null && json['captionMotion'] is! bool) ||
        (json['softAudioJoins'] != null && json['softAudioJoins'] is! bool) ||
        (json['zoomCount'] != null && json['zoomCount'] is! int) ||
        (json['clickCount'] != null && json['clickCount'] is! int) ||
        (json['shortcutCount'] != null && json['shortcutCount'] is! int) ||
        (json['screenFrame'] != null && json['screenFrame'] is! bool) ||
        (json['cameraPunchCount'] != null &&
            json['cameraPunchCount'] is! int) ||
        (json['cameraClear'] != null && json['cameraClear'] is! bool) ||
        (json['motionBlur'] != null && json['motionBlur'] is! bool) ||
        (json['balanceSound'] != null && json['balanceSound'] is! bool) ||
        (json['softenSharpSound'] != null &&
            json['softenSharpSound'] is! bool)) {
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
        softAudioJoins: json['softAudioJoins'] as bool? ?? false,
        zoomCount: json['zoomCount'] as int? ?? 0,
        clickCount: json['clickCount'] as int? ?? 0,
        shortcutCount: json['shortcutCount'] as int? ?? 0,
        screenFrame: json['screenFrame'] as bool? ?? false,
        cameraPunchCount: json['cameraPunchCount'] as int? ?? 0,
        cameraClear: json['cameraClear'] as bool? ?? false,
        motionBlur: json['motionBlur'] as bool? ?? false,
        balanceSound: json['balanceSound'] as bool? ?? false,
        softenSharpSound: json['softenSharpSound'] as bool? ?? false,
      );
    } on ArgumentError {
      throw const FormatException('Invalid video export');
    }
  }
}

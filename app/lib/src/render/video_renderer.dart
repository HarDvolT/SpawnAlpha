import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../model/cut_plan.dart';
import '../model/video_export.dart';
import '../theme/tokens.g.dart';
import '../transcription/captions.dart';

class VideoRenderRequest {
  VideoRenderRequest({
    required this.source,
    required this.output,
    required this.plan,
    required this.format,
    this.camera,
    List<Caption> captions = const [],
  }) : captions = List.unmodifiable(captions) {
    if (captions.length > 100000) {
      throw const FormatException('Too many captions');
    }
    var previous = Duration.zero, total = 0;
    for (final caption in captions) {
      total += caption.text.length;
      if (caption.start < previous ||
          caption.end <= caption.start ||
          caption.end > plan.duration ||
          caption.text.isEmpty ||
          caption.text.length > 4096 ||
          total > 4 * 1024 * 1024 ||
          RegExp(r'[\u0000-\u001f\u007f]').hasMatch(caption.text) ||
          utf8.decode(utf8.encode(caption.text)) != caption.text) {
        throw const FormatException('Invalid captions');
      }
      previous = caption.end;
    }
  }
  final String source, output;
  final String? camera;
  final CutPlan plan;
  final VideoFormat format;
  final List<Caption> captions;
  Map<String, Object?> toJson() => {
    'source': source,
    'camera': camera ?? '',
    'output': output,
    'width': format.width,
    'height': format.height,
    'cameraInset': SaVideoExport.cameraInset,
    'cameraMargin': SaVideoExport.cameraMargin,
    'sourceDurationUs': plan.sourceDuration.inMicroseconds,
    'ranges': plan.ranges.map((r) => r.toJson()).toList(),
    'captions': [
      for (final caption in captions)
        {
          'text': caption.text,
          'startUs': caption.start.inMicroseconds,
          'endUs': caption.end.inMicroseconds,
        },
    ],
    if (captions.isNotEmpty)
      'captionLayout': {
        'rtl': plan.language.isRtl,
        'edge': SaVideoExport.captionEdge,
        'bottom': SaVideoExport.captionBottom,
        'safeTop': SaVideoExport.captionSafeTop,
        'safeBottom': SaVideoExport.captionSafeBottom,
        'safeRight': SaVideoExport.captionSafeRight,
        'fontSize': SaType.captionCue.fontSize!,
        'lineHeight': SaType.captionCue.fontSize! * SaType.captionCue.height!,
        'weight': SaType.captionCue.fontWeight!.value,
        'minSize': SaVideoExport.captionMinSize,
        'padding': SaSpace.s3,
        'radius': SaRadius.sm,
        'shadowOffset': SaVideoExport.captionShadowOffset,
        'textColor': SaPalette.dark.captionText.toARGB32(),
        'plateColor': SaPalette.dark.captionPlate.toARGB32(),
      },
  };
}

class RenderCancelled implements Exception {
  const RenderCancelled();
}

abstract class VideoRenderer {
  factory VideoRenderer.platform() =>
      Platform.isWindows ? WindowsVideoRenderer() : UnavailableRenderer();
  bool get supported;
  Future<void> render(
    VideoRenderRequest request,
    void Function(double) progress,
  );
  Future<void> cancel();
}

class WindowsVideoRenderer implements VideoRenderer {
  static const channel = MethodChannel('spawnalpha/render');
  int? _session;
  bool _cancelled = false, _running = false;
  @override
  bool get supported => true;
  @override
  Future<void> render(
    VideoRenderRequest request,
    void Function(double) progress,
  ) async {
    if (_running) throw StateError('Video export is busy');
    if (request.plan.sourceDuration > const Duration(hours: 24) ||
        request.plan.duration > const Duration(hours: 24) ||
        request.plan.ranges.length > 20001) {
      throw const FormatException('Invalid video export');
    }
    _running = true;
    _cancelled = false;
    try {
      final id = await channel.invokeMethod<int>('start', request.toJson());
      if (id == null || id <= 0) {
        throw const FormatException('Invalid render session');
      }
      _session = id;
      if (_cancelled) {
        await channel.invokeMethod<void>('cancel', {'sessionId': id});
      }
      while (true) {
        final info = await channel.invokeMapMethod<String, Object?>('status', {
          'sessionId': id,
        });
        final state = info?['state'], amount = info?['progress'];
        if (amount is! num || !amount.isFinite || amount < 0 || amount > 1) {
          throw const FormatException('Invalid export progress');
        }
        if (state == 'ready') {
          if (_cancelled) throw const RenderCancelled();
          progress(1);
          return;
        }
        if (state == 'cancelled') throw const RenderCancelled();
        if (state == 'failed') throw StateError('Video export failed');
        if (state != 'working') {
          throw const FormatException('Invalid export state');
        }
        progress(amount.toDouble());
        await Future<void>.delayed(SaDurations.previewPoll);
      }
    } on Object {
      final current = _session;
      if (current != null) {
        try {
          await channel.invokeMethod<void>('cancel', {'sessionId': current});
        } on Object {
          /* No private errors. */
        }
      }
      rethrow;
    } finally {
      _session = null;
      _running = false;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final current = _session;
    if (current != null) {
      await channel.invokeMethod<void>('cancel', {'sessionId': current});
    }
  }
}

class UnavailableRenderer implements VideoRenderer {
  @override
  bool get supported => false;
  @override
  Future<void> render(
    VideoRenderRequest request,
    void Function(double) progress,
  ) async =>
      throw UnsupportedError('Video export is available on Windows first');
  @override
  Future<void> cancel() async {}
}

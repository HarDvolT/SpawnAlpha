import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

import '../model/cut_plan.dart';
import '../model/caption_style.dart';
import '../model/video_export.dart';
import '../theme/tokens.g.dart';
import '../transcription/captions.dart';
import 'screen_zooms.dart';
import 'screen_clicks.dart';
import 'screen_shortcuts.dart';
import 'camera_punches.dart';
import 'camera_targets.dart';

class VideoRenderRequest {
  VideoRenderRequest({
    required this.source,
    required this.output,
    required this.plan,
    required this.format,
    this.camera,
    this.captionStyle = CaptionStyle.readable,
    this.captionMotion = true,
    this.softAudioJoins = false,
    this.screenZooms,
    this.screenClicks,
    this.screenShortcuts,
    this.screenFrame = false,
    this.cameraPunches,
    this.cameraPunchMain = false,
    this.cameraClear = false,
    this.motionBlur = false,
    this.balanceSound = false,
    this.cameraTargets,
    List<Caption> captions = const [],
  }) : captions = List.unmodifiable(
         captions.map(
           (c) => Caption(
             c.text,
             c.start,
             c.end,
             words: List.unmodifiable(c.words),
           ),
         ),
       ) {
    if (motionBlur && ((screenZooms?.count ?? 0) == 0 || cameraPunchMain)) {
      throw const FormatException('Invalid screen motion blur');
    }
    cameraTargets?.validateClock(plan);
    if (cameraClear && camera == null ||
        (cameraTargets?.targets.isNotEmpty ?? false) &&
            (!cameraClear || camera == null)) {
      throw const FormatException('Invalid camera placement');
    }
    cameraPunches?.validateClock(
      plan,
      minimum: SaVideoExport.cameraPunchMinimum,
      interval: SaVideoExport.cameraPunchInterval,
    );
    if ((cameraPunches?.steps.any((s) => s.time > plan.duration) ?? false) ||
        ((cameraPunches?.count ?? 0) > 0 &&
            (plan.duration < SaVideoExport.cameraPunchMinimum ||
                plan.sourceDuration < SaVideoExport.cameraPunchMinimum ||
                cameraPunchMain &&
                    (camera != null ||
                        screenFrame ||
                        (screenZooms?.count ?? 0) > 0) ||
                !cameraPunchMain && camera == null))) {
      throw const FormatException('Invalid camera emphasis clock');
    }
    if (screenShortcuts?.badges.any((b) => b.end > plan.duration) ?? false) {
      throw const FormatException('Invalid shortcut clock');
    }
    if (screenClicks?.pulses.any((p) => p.end > plan.duration) ?? false) {
      throw const FormatException('Invalid click clock');
    }
    if (screenZooms != null &&
        screenZooms!.steps.any((s) => s.time > plan.duration)) {
      throw const FormatException('Invalid zoom clock');
    }
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
      if ((captionStyle != CaptionStyle.readable && caption.words.isEmpty) ||
          caption.words.length > (captionStyle == CaptionStyle.punch ? 3 : 7) ||
          (captionStyle == CaptionStyle.punch &&
              caption.words.length > 1 &&
              caption.words.any((w) => w.cue.stress))) {
        throw const FormatException('Missing caption word timings');
      }
      var offset = 0, wordEnd = caption.start;
      for (final word in caption.words) {
        final end = word.offset + word.length;
        if (word.offset != offset ||
            word.length < 1 ||
            end > caption.text.length ||
            word.start < wordEnd ||
            word.end <= word.start ||
            word.end > caption.end) {
          throw const FormatException('Invalid caption word timings');
        }
        final text = caption.text.substring(word.offset, end);
        if (RegExp(r'\s').hasMatch(text) ||
            utf8.decode(utf8.encode(text)) != text ||
            (end < caption.text.length && caption.text[end] != ' ')) {
          throw const FormatException('Invalid caption word range');
        }
        offset = end + 1;
        wordEnd = word.end;
      }
      if (caption.words.isNotEmpty &&
          (offset != caption.text.length + 1 ||
              caption.words.first.start != caption.start ||
              caption.words.last.end != caption.end)) {
        throw const FormatException('Incomplete caption word timings');
      }
    }
  }
  final String source, output;
  final String? camera;
  final CutPlan plan;
  final VideoFormat format;
  final CaptionStyle captionStyle;
  final bool captionMotion;
  final bool softAudioJoins;
  final ScreenZooms? screenZooms;
  final ScreenClicks? screenClicks;
  final ScreenShortcuts? screenShortcuts;
  final bool screenFrame;
  final CameraPunches? cameraPunches;
  final bool cameraPunchMain;
  final bool cameraClear;
  final bool motionBlur;
  final bool balanceSound;
  final CameraTargets? cameraTargets;
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
    'audioJoinFadeUs': softAudioJoins && plan.hasJoins
        ? SaVideoExport.audioJoinFade.inMicroseconds
        : 0,
    'ranges': plan.ranges.map((r) => r.toJson()).toList(),
    if (balanceSound)
      'soundBalance': {
        'target': SaSoundPolish.loudnessTarget,
        'ceiling': SaSoundPolish.peakCeiling,
        'maximumBoost': SaSoundPolish.maximumBoost,
      },
    if (motionBlur)
      'screenBlur': {
        'maximum': SaScreenFx.blurMax,
        'minimum': SaScreenFx.blurMinimum,
        'shutterUs': SaScreenFx.blurShutter.inMicroseconds,
      },
    if (cameraClear) ...{
      'cameraTargets':
          cameraTargets?.targets.map((t) => t.toJson()).toList() ?? [],
      'cameraClearLayout': {
        'gap': SaVideoExport.cameraClearGap,
        'intervalUs': SaVideoExport.cameraClearInterval.inMicroseconds,
        'mass': SaSprings.camera.mass,
        'stiffness': SaSprings.camera.stiffness,
        'damping': SaSprings.camera.damping,
      },
    },
    if (cameraPunches != null && cameraPunches!.count > 0) ...{
      'punchSteps': cameraPunches!.steps.map((s) => s.toJson()).toList(),
      'punchMain': cameraPunchMain,
      'punchFactor': SaVideoExport.cameraPunch,
      'punchSpring': {
        'mass': SaSprings.camera.mass,
        'stiffness': SaSprings.camera.stiffness,
        'damping': SaSprings.camera.damping,
      },
    },
    if (screenFrame)
      'screenFrame': {
        'inset': SaScreenFx.frameInset,
        'radius': SaRadius.md,
        'topColor': SaPalette.dark.surface.toARGB32(),
        'bottomColor': SaPalette.dark.paper.toARGB32(),
        'shadows': [
          for (final shadow in SaPalette.dark.shadowFloat)
            {
              'color': shadow.color.toARGB32(),
              'x': shadow.offset.dx,
              'y': shadow.offset.dy,
              'sigma': shadow.blurSigma,
            },
        ],
      },
    if (screenShortcuts != null && screenShortcuts!.count > 0) ...{
      'shortcutBadges': screenShortcuts!.badges.map((b) => b.toJson()).toList(),
      'shortcutLayout': {
        'edge': SaVideoExport.captionEdge,
        'safeTop': SaVideoExport.captionSafeTop,
        'safeRight': SaVideoExport.captionSafeRight,
        'fontSize': SaScreenFx.keycapFontSize,
        'lineHeight': SaScreenFx.keycapLineHeight,
        'weight': SaType.signalLabel.fontWeight!.value,
        'padding': SaSpace.s3,
        'radius': SaRadius.md,
        'textColor': SaPalette.dark.stageText.toARGB32(),
        'plateColor': SaPalette.dark.stageGlass.toARGB32(),
        'rise': SaScreenFx.keycapRise,
        'fadeUs': SaScreenFx.keycapFade.inMicroseconds,
        'mass': SaSprings.smooth.mass,
        'stiffness': SaSprings.smooth.stiffness,
        'damping': SaSprings.smooth.damping,
      },
    },
    if (screenClicks != null && screenClicks!.count > 0) ...{
      'clickPulses': screenClicks!.pulses.map((p) => p.toJson()).toList(),
      'clickLayout': {
        'radius': SaScreenFx.rippleRadius,
        'grow': SaScreenFx.rippleGrow,
        'stroke': SaScreenFx.rippleStroke,
        'halo': SaScreenFx.rippleHalo,
        'color': SaPalette.dark.ripple.toARGB32(),
        'mass': SaSprings.smooth.mass,
        'stiffness': SaSprings.smooth.stiffness,
        'damping': SaSprings.smooth.damping,
      },
    },
    if (screenZooms != null && screenZooms!.count > 0) ...{
      'zoomSteps': screenZooms!.steps.map((s) => s.toJson()).toList(),
      'zoomSpring': {
        'mass': SaSprings.camera.mass,
        'stiffness': SaSprings.camera.stiffness,
        'damping': SaSprings.camera.damping,
      },
    },
    'captions': [
      for (final caption in _displayCaptions)
        {
          'text': caption.text,
          'startUs': caption.start.inMicroseconds,
          'endUs': caption.end.inMicroseconds,
          if (caption.words.isNotEmpty)
            'words': caption.words.map((w) => w.toJson()).toList(),
        },
    ],
    if (captions.isNotEmpty)
      'captionLayout': {
        'style': captionStyle.name,
        'motion': captionMotion,
        'rtl': plan.language.isRtl,
        'edge': SaVideoExport.captionEdge,
        'bottom': SaVideoExport.captionBottom,
        'safeTop': SaVideoExport.captionSafeTop,
        'safeBottom': SaVideoExport.captionSafeBottom,
        'safeRight': SaVideoExport.captionSafeRight,
        'fontSize': _captionType.fontSize!,
        'lineHeight': _captionType.fontSize! * _captionType.height!,
        'weight': _captionType.fontWeight!.value,
        'minSize': SaVideoExport.captionMinSize,
        'padding': SaSpace.s3,
        'radius': SaRadius.sm,
        'shadowOffset': SaVideoExport.captionShadowOffset,
        'textColor': SaPalette.dark.captionText.toARGB32(),
        'plateColor': SaPalette.dark.captionPlate.toARGB32(),
        'waitingColor': SaPalette.dark.captionWaiting.toARGB32(),
        'underlineColor': SaPalette.dark.ripple.toARGB32(),
        'underlineSize': SaVideoExport.captionUnderlineSize,
        'underlineGap': SaVideoExport.captionUnderlineGap,
        'stressColor': SaPalette.dark.stageStress.toARGB32(),
        'energyColor': SaPalette.dark.stageEnergy.toARGB32(),
        'rise': SaVideoExport.captionRise,
        'popStart': SaVideoExport.captionPopStart,
        'popMax': SaVideoExport.captionPopMax,
        'popAmplitude': SaVideoExport.captionPopAmplitude,
        'punchStart': SaVideoExport.captionPunchStart,
        'stressWidth': SaVideoExport.captionStressWidth,
        'punchWidth': SaVideoExport.captionPunchWidth,
        'slowerWidth': SaVideoExport.captionSlowerWidth,
        'fasterWidth': SaVideoExport.captionFasterWidth,
        'smoothMass': SaSprings.smooth.mass,
        'smoothStiffness': SaSprings.smooth.stiffness,
        'smoothDamping': SaSprings.smooth.damping,
        'popMass': SaSprings.pop.mass,
        'popStiffness': SaSprings.pop.stiffness,
        'popDamping': SaSprings.pop.damping,
      },
  };

  // Styles keep exact saved words; type comes from fixed Cut tokens.
  TextStyle get _captionType => switch (captionStyle) {
    CaptionStyle.karaoke => SaType.captionKaraoke,
    CaptionStyle.punch => SaType.captionPunch,
    _ => SaType.captionCue,
  };
  Iterable<Caption> get _displayCaptions =>
      captionStyle == CaptionStyle.readable
      ? captions
      : captions.map((c) => captionDisplay(c, rtl: plan.language.isRtl));
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

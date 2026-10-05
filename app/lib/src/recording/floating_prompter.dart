import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../model/script_document.dart';
import '../prompter/guide.dart';
import '../prompter/prompter_controller.dart';
import '../storage/settings.dart';
import '../theme/theme.dart';

/// An in-memory presentation, deliberately excluding takes, suggestions and keys.
class FloatingPresentation {
  const FloatingPresentation({
    required this.script,
    this.guide = PrompterGuide.dot,
    this.motion = PrompterMotion.phrase,
    this.alignment = PrompterAlignment.center,
    this.kinetic = true,
    this.mirror = false,
    this.pace = ScrollMode.timed,
  });
  factory FloatingPresentation.fromSettings(
    ScriptDocument script,
    Settings settings, {
    ScrollMode pace = ScrollMode.timed,
  }) => FloatingPresentation(
    script: script,
    guide: settings.guide,
    motion: settings.motion,
    alignment: settings.alignment,
    kinetic: settings.kinetic,
    mirror: settings.mirror,
    pace: pace,
  );

  final ScriptDocument script;
  final PrompterGuide guide;
  final PrompterMotion motion;
  final PrompterAlignment? alignment;
  final bool kinetic;
  final bool mirror;
  final ScrollMode pace;

  String encode() => jsonEncode({
    'script': script.copyWith(takes: const [], suggestions: const []).toJson(),
    'guide': guide.name,
    'motion': motion.name,
    'alignment': alignment?.name,
    'kinetic': kinetic,
    'mirror': mirror,
    'pace': pace.name,
  });

  factory FloatingPresentation.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return FloatingPresentation(
      script: ScriptDocument.fromJson(
        Map<String, Object?>.from(data['script'] as Map),
      ),
      guide: PrompterGuide.fromName(data['guide'] as String?),
      motion: PrompterMotion.fromName(data['motion'] as String?),
      alignment: PrompterAlignment.fromName(data['alignment'] as String?),
      kinetic: data['kinetic'] != false,
      mirror: data['mirror'] == true,
      pace:
          ScrollMode.values.where((v) => v.name == data['pace']).firstOrNull ??
          ScrollMode.timed,
    );
  }
}

class FloatingHandle {
  const FloatingHandle(this.sessionId);
  final int sessionId;
}

class FloatingRecordingState {
  const FloatingRecordingState({
    required this.active,
    this.paused = false,
    this.speaking = false,
  });
  final bool active, paused, speaking;
  Map<String, Object?> toJson() => {
    'active': active,
    'paused': paused,
    'speaking': speaking,
  };
}

abstract class FloatingPrompters {
  factory FloatingPrompters.platform() => Platform.isWindows
      ? const WindowsFloatingPrompters()
      : const UnsupportedFloatingPrompters();
  bool get supported;
  Future<FloatingHandle> open(FloatingPresentation presentation);
  Future<bool> isOpen(FloatingHandle handle);
  Future<void> close(FloatingHandle handle);
  Future<void> update(FloatingHandle handle, FloatingRecordingState state);
  Future<void> show(FloatingHandle handle, bool visible);
  Future<void> lock(FloatingHandle handle);
}

class WindowsFloatingPrompters implements FloatingPrompters {
  const WindowsFloatingPrompters();
  static const channel = MethodChannel('spawnalpha/floating_prompter');
  @override
  bool get supported => true;
  @override
  Future<FloatingHandle> open(FloatingPresentation presentation) async {
    final id = await channel.invokeMethod<int>('open', {
      'presentation': presentation.encode(),
      'width': SaPrompter.floatingWidth.round(),
      'height': SaPrompter.floatingHeight.round(),
      'minWidth': SaPrompter.floatingMinWidth.round(),
      'minHeight': SaPrompter.floatingMinHeight.round(),
      'snap': SaSpace.s6.round(),
      'minOpacity': SaPrompter.floatingMinOpacity,
    });
    if (id == null) throw const FormatException('Missing floating session');
    final handle = FloatingHandle(id);
    try {
      final attempts =
          (SaDurations.beat * 5).inMicroseconds ~/
          SaDurations.previewPoll.inMicroseconds;
      for (var attempt = 0; attempt < attempts; ++attempt) {
        final state = await channel.invokeMapMethod<String, Object?>('status', {
          'sessionId': id,
        });
        if (state?['excluded'] != true) {
          throw const FormatException('Capture exclusion unavailable');
        }
        if (state?['visible'] == true) return handle;
        await Future<void>.delayed(SaDurations.previewPoll);
      }
      throw TimeoutException('Floating prompter unavailable');
    } on Object {
      await close(handle);
      rethrow;
    }
  }

  @override
  Future<void> close(FloatingHandle handle) =>
      channel.invokeMethod<void>('close', {'sessionId': handle.sessionId});
  @override
  Future<bool> isOpen(FloatingHandle handle) async {
    final state = await channel.invokeMapMethod<String, Object?>('status', {
      'sessionId': handle.sessionId,
    });
    return state?['excluded'] == true && state?['visible'] == true;
  }

  @override
  Future<void> update(FloatingHandle handle, FloatingRecordingState state) =>
      channel.invokeMethod<void>('update', {
        'sessionId': handle.sessionId,
        'state': state.toJson(),
      });
  @override
  Future<void> show(FloatingHandle handle, bool visible) =>
      channel.invokeMethod<void>('show', {
        'sessionId': handle.sessionId,
        'visible': visible,
      });
  @override
  Future<void> lock(FloatingHandle handle) =>
      channel.invokeMethod<void>('lock', {'sessionId': handle.sessionId});
}

class UnsupportedFloatingPrompters implements FloatingPrompters {
  const UnsupportedFloatingPrompters();
  @override
  bool get supported => false;
  @override
  Future<FloatingHandle> open(FloatingPresentation presentation) async =>
      throw UnsupportedError('Windows only');
  @override
  Future<void> close(FloatingHandle handle) async {}
  @override
  Future<bool> isOpen(FloatingHandle handle) async => false;
  @override
  Future<void> update(
    FloatingHandle handle,
    FloatingRecordingState state,
  ) async {}
  @override
  Future<void> show(FloatingHandle handle, bool visible) async {}
  @override
  Future<void> lock(FloatingHandle handle) async {}
}

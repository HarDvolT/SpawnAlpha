import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../model/script_document.dart';
import '../prompter/guide.dart';
import '../storage/settings.dart';
import '../theme/theme.dart';

/// An in-memory presentation, deliberately excluding takes, suggestions and keys.
class FloatingPresentation {
  const FloatingPresentation({required this.script, this.guide = PrompterGuide.dot,
    this.motion = PrompterMotion.phrase, this.alignment = PrompterAlignment.center,
    this.kinetic = true, this.mirror = false});
  factory FloatingPresentation.fromSettings(ScriptDocument script, Settings settings) =>
      FloatingPresentation(script: script, guide: settings.guide, motion: settings.motion,
        alignment: settings.alignment, kinetic: settings.kinetic, mirror: settings.mirror);

  final ScriptDocument script;
  final PrompterGuide guide;
  final PrompterMotion motion;
  final PrompterAlignment? alignment;
  final bool kinetic;
  final bool mirror;

  String encode() => jsonEncode({
    'script': script.copyWith(takes: const [], suggestions: const []).toJson(),
    'guide': guide.name, 'motion': motion.name, 'alignment': alignment?.name,
    'kinetic': kinetic, 'mirror': mirror,
  });

  factory FloatingPresentation.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return FloatingPresentation(script: ScriptDocument.fromJson(Map<String, Object?>.from(data['script'] as Map)),
      guide: PrompterGuide.fromName(data['guide'] as String?),
      motion: PrompterMotion.fromName(data['motion'] as String?),
      alignment: PrompterAlignment.fromName(data['alignment'] as String?),
      kinetic: data['kinetic'] != false, mirror: data['mirror'] == true);
  }
}

class FloatingHandle {
  const FloatingHandle(this.sessionId);
  final int sessionId;
}

abstract class FloatingPrompters {
  factory FloatingPrompters.platform() => Platform.isWindows
      ? const WindowsFloatingPrompters() : const UnsupportedFloatingPrompters();
  bool get supported;
  Future<FloatingHandle> open(FloatingPresentation presentation);
  Future<bool> isOpen(FloatingHandle handle);
  Future<void> close(FloatingHandle handle);
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
      'width': SaPrompter.floatingWidth.round(), 'height': SaPrompter.floatingHeight.round(),
      'minWidth': SaPrompter.floatingMinWidth.round(), 'minHeight': SaPrompter.floatingMinHeight.round(),
      'snap': SaSpace.s6.round(),
      'minOpacity': SaPrompter.floatingMinOpacity,
    });
    if (id == null) throw const FormatException('Missing floating session');
    final handle = FloatingHandle(id);
    try {
      final attempts = (SaDurations.beat * 5).inMicroseconds ~/ SaDurations.previewPoll.inMicroseconds;
      for (var attempt = 0; attempt < attempts; ++attempt) {
        final state = await channel.invokeMapMethod<String, Object?>('status', {'sessionId': id});
        if (state?['excluded'] != true) throw const FormatException('Capture exclusion unavailable');
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
  Future<void> close(FloatingHandle handle) => channel.invokeMethod<void>('close', {'sessionId': handle.sessionId});
  @override
  Future<bool> isOpen(FloatingHandle handle) async {
    final state = await channel.invokeMapMethod<String, Object?>('status', {'sessionId': handle.sessionId});
    return state?['excluded'] == true && state?['visible'] == true;
  }
}

class UnsupportedFloatingPrompters implements FloatingPrompters {
  const UnsupportedFloatingPrompters();
  @override
  bool get supported => false;
  @override
  Future<FloatingHandle> open(FloatingPresentation presentation) async => throw UnsupportedError('Windows only');
  @override
  Future<void> close(FloatingHandle handle) async {}
  @override
  Future<bool> isOpen(FloatingHandle handle) async => false;
}

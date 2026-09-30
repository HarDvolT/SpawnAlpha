import 'dart:io';

import 'package:flutter/services.dart';

/// A microphone the app can record from.
class AudioInput {
  const AudioInput({required this.id, required this.name, required this.isDefault});

  final String id;
  final String name;

  /// The one Windows uses by default.
  final bool isDefault;
}

/// A microphone's level over the last ~50 ms, in dBFS (-100 is silence).
class MicLevel {
  const MicLevel({required this.peakDb, required this.rmsDb, this.failed = false, this.denied = false});

  static const silent = MicLevel(peakDb: -100, rmsDb: -100);

  final double peakDb;
  final double rmsDb;

  /// The microphone could not be opened (unplugged, or access denied).
  final bool failed;

  /// The system refused access: on Windows, the microphone privacy
  /// switches are off for desktop apps.
  final bool denied;

  /// 0 to 1 for a meter: -60 dBFS and below is empty, 0 dBFS is full.
  double get meter => ((peakDb + 60) / 60).clamp(0.0, 1.0);
}

/// Lists microphones, chooses the one takes record from, and measures
/// levels for the meter and for voice pacing.
///
/// On Windows this talks to the vendored camera_windows plugin
/// (`spawnalpha/audio_input`). Other platforms don't support choosing yet.
abstract class AudioInputs {
  /// The implementation for this platform.
  factory AudioInputs.platform() => Platform.isWindows ? _ChannelAudioInputs() : const UnsupportedAudioInputs();

  bool get supported;

  Future<List<AudioInput>> list();

  /// The microphone new cameras record from; null means the default one.
  Future<void> select(String? id);

  /// Starts measuring [id] (null: the default microphone).
  Future<void> startLevels(String? id);

  Future<void> stopLevels();

  Future<MicLevel> level();

  /// Starts metering every microphone at once, for the record set-up.
  Future<void> watchAll();

  /// Every watched microphone's level, by ID.
  Future<Map<String, MicLevel>> levels();

  Future<void> unwatchAll();
}

class UnsupportedAudioInputs implements AudioInputs {
  const UnsupportedAudioInputs();

  @override
  bool get supported => false;

  @override
  Future<List<AudioInput>> list() async => const [];

  @override
  Future<void> select(String? id) async {}

  @override
  Future<void> startLevels(String? id) async {}

  @override
  Future<void> stopLevels() async {}

  @override
  Future<MicLevel> level() async => MicLevel.silent;

  @override
  Future<void> watchAll() async {}

  @override
  Future<Map<String, MicLevel>> levels() async => const {};

  @override
  Future<void> unwatchAll() async {}
}

class _ChannelAudioInputs implements AudioInputs {
  static const _channel = MethodChannel('spawnalpha/audio_input');

  @override
  bool get supported => true;

  @override
  Future<List<AudioInput>> list() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
    return [
      for (final m in raw)
        AudioInput(id: m['id'] as String, name: (m['name'] as String?) ?? 'Microphone', isDefault: m['default'] == true),
    ];
  }

  @override
  Future<void> select(String? id) => _channel.invokeMethod('select', id);

  @override
  Future<void> startLevels(String? id) => _channel.invokeMethod('startLevels', id);

  @override
  Future<void> stopLevels() => _channel.invokeMethod('stopLevels');

  @override
  Future<MicLevel> level() async => _levelOf(await _channel.invokeMapMethod<String, Object?>('level') ?? const {});

  @override
  Future<void> watchAll() => _channel.invokeMethod('watchAll');

  @override
  Future<Map<String, MicLevel>> levels() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('levels') ?? const {};
    return {
      for (final e in raw.entries)
        if (e.value is Map) e.key: _levelOf((e.value! as Map).cast<String, Object?>()),
    };
  }

  @override
  Future<void> unwatchAll() => _channel.invokeMethod('unwatchAll');

  static MicLevel _levelOf(Map<String, Object?> m) => MicLevel(
        peakDb: (m['peak'] as num?)?.toDouble() ?? -100,
        rmsDb: (m['rms'] as num?)?.toDouble() ?? -100,
        failed: m['failed'] == true,
        denied: m['denied'] == true,
      );
}

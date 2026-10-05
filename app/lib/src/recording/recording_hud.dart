import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'screen_source.dart';

enum HudPhase { preparing, countdown, recording, paused, saving }
class HudState {
  const HudState({this.phase = HudPhase.preparing, this.countdown = 3, this.duration = Duration.zero,
    this.microphone = 'Microphone', this.peakDb = -100, this.recordAudio = true, this.prompterOpen = true});
  final HudPhase phase;
  final int countdown;
  final Duration duration;
  final String microphone;
  final double peakDb;
  final bool recordAudio, prompterOpen;
  Map<String, Object?> toJson() => {'phase': phase.name, 'countdown': countdown,
    'durationUs': duration.inMicroseconds, 'microphone': microphone, 'peakDb': peakDb,
    'recordAudio': recordAudio, 'prompterOpen': prompterOpen};
  factory HudState.fromJson(Map<Object?, Object?> json) => HudState(
    phase: HudPhase.values.where((v) => v.name == json['phase']).firstOrNull ?? HudPhase.preparing,
    countdown: (json['countdown'] as int? ?? 3).clamp(1, 3),
    duration: Duration(microseconds: (json['durationUs'] as int? ?? 0).clamp(0, 1 << 62)),
    microphone: json['microphone'] as String? ?? 'Microphone',
    peakDb: (json['peakDb'] as num? ?? -100).toDouble().clamp(-100, 0),
    recordAudio: json['recordAudio'] != false, prompterOpen: json['prompterOpen'] != false);
}
class HudHandle { const HudHandle(this.sessionId); final int sessionId; }
class HudCommand { const HudCommand(this.sessionId, this.command); final int sessionId; final String command; }

abstract class RecordingHuds {
  factory RecordingHuds.platform() => Platform.isWindows ? WindowsRecordingHuds() : const UnsupportedRecordingHuds();
  Stream<HudCommand> get commands;
  Future<HudHandle> open(ScreenSource source);
  Future<bool> isOpen(HudHandle handle);
  Future<void> update(HudHandle handle, HudState state);
  Future<void> close(HudHandle handle);
}
class WindowsRecordingHuds implements RecordingHuds {
  WindowsRecordingHuds() {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'command' || call.arguments is! Map) return;
      final args = call.arguments as Map;
      final id = args['sessionId'], command = args['command'];
      if (id is int && command is String && const {'stop', 'pause', 'prompter', 'lock'}.contains(command)) {
        _commands.add(HudCommand(id, command));
      }
    });
  }
  static const channel = MethodChannel('spawnalpha/recording_hud');
  final _commands = StreamController<HudCommand>.broadcast();
  @override
  Stream<HudCommand> get commands => _commands.stream;
  @override
  Future<HudHandle> open(ScreenSource source) async {
    final id = await channel.invokeMethod<int>('open', {'sourceId': source.id,
      'width': SaPrompter.hudWidth.round(), 'height': SaPrompter.hudHeight.round(),
      'countdownSize': SaPrompter.countdownWindowSize.round(), 'inset': SaSpace.s6.round(),
      'hitPollMs': SaDurations.hudHitPoll.inMilliseconds, 'radius': SaRadius.lg.round()});
    if (id == null || id <= 0) throw const FormatException('Missing recording controls');
    final handle = HudHandle(id);
    try {
      final attempts = (SaDurations.beat * 5).inMicroseconds ~/ SaDurations.previewPoll.inMicroseconds;
      for (var i = 0; i < attempts; ++i) {
        final state = await channel.invokeMapMethod<String, Object?>('status', {'sessionId': id});
        if (state?['excluded'] != true) throw const FormatException('Capture exclusion unavailable');
        if (state?['ready'] == true) return handle;
        await Future<void>.delayed(SaDurations.previewPoll);
      }
      throw TimeoutException('Recording controls unavailable');
    } on Object { await close(handle); rethrow; }
  }
  @override
  Future<bool> isOpen(HudHandle handle) async {
    final state = await channel.invokeMapMethod<String, Object?>('status', {'sessionId': handle.sessionId});
    return state?['excluded'] == true && state?['ready'] == true;
  }
  @override
  Future<void> update(HudHandle handle, HudState state) => channel.invokeMethod<void>('update',
    {'sessionId': handle.sessionId, 'state': state.toJson()});
  @override
  Future<void> close(HudHandle handle) => channel.invokeMethod<void>('close', {'sessionId': handle.sessionId});
}
class UnsupportedRecordingHuds implements RecordingHuds {
  const UnsupportedRecordingHuds();
  @override
  Stream<HudCommand> get commands => const Stream.empty();
  @override
  Future<HudHandle> open(ScreenSource source) async => throw UnsupportedError('Windows only');
  @override
  Future<bool> isOpen(HudHandle handle) async => false;
  @override
  Future<void> update(HudHandle handle, HudState state) async {}
  @override
  Future<void> close(HudHandle handle) async {}
}

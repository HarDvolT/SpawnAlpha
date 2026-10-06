import 'dart:io';

import 'package:flutter/services.dart';

import '../model/script_language.dart';
import '../theme/theme.dart';

class SpeechCancelled implements Exception {
  const SpeechCancelled();
}

abstract class SpeechBackend {
  bool get supported;
  Future<bool> verify(String model);
  Future<List<Object?>> transcribe({
    required String model,
    required String media,
    required ScriptLanguage language,
    required String vocabulary,
    required Duration duration,
    required void Function(double) progress,
  });
  Future<void> cancel();
}

class WindowsSpeechBackend implements SpeechBackend {
  static const channel = MethodChannel('spawnalpha/speech');
  @override
  bool get supported => Platform.isWindows;
  bool _busy = false;
  int? _session;
  bool _cancelWanted = false;

  Future<Map<Object?, Object?>> _run(
    String method,
    Map<String, Object?> args,
    void Function(double)? progress,
  ) async {
    if (_busy) throw StateError('Speech processing is busy');
    _busy = true;
    _cancelWanted = false;
    try {
      final id = await channel.invokeMethod<int>(method, args);
      if (id == null) throw const FormatException('Speech job unavailable');
      _session = id;
      if (_cancelWanted) await cancel();
      for (;;) {
        final state = await channel.invokeMapMethod<Object?, Object?>(
          'status',
          {'sessionId': id},
        );
        if (state == null) {
          throw const FormatException('Speech job unavailable');
        }
        final amount = state['progress'];
        if (amount is num && amount.isFinite) {
          progress?.call(amount.toDouble().clamp(0, 1));
        }
        switch (state['state']) {
          case 'ready':
            if (_cancelWanted) throw const SpeechCancelled();
            return state;
          case 'cancelled':
            throw const SpeechCancelled();
          case 'failed':
            throw const FormatException('Offline speech could not finish');
          case 'working':
            break;
          default:
            throw const FormatException('Speech job unavailable');
        }
        await Future<void>.delayed(SaDurations.recordingPoll);
      }
    } finally {
      _session = null;
      _busy = false;
    }
  }

  @override
  Future<bool> verify(String model) async =>
      (await _run('verify', {'model': model}, null))['verified'] == true;
  @override
  Future<List<Object?>> transcribe({
    required String model,
    required String media,
    required ScriptLanguage language,
    required String vocabulary,
    required Duration duration,
    required void Function(double) progress,
  }) async {
    final state = await _run('start', {
      'model': model,
      'media': media,
      'language': language.name,
      'vocabulary': vocabulary,
      'durationUs': duration.inMicroseconds,
    }, progress);
    if (state['windows'] is! List) {
      throw const FormatException('Speech output unavailable');
    }
    return (state['windows']! as List).cast<Object?>();
  }

  @override
  Future<void> cancel() async {
    _cancelWanted = true;
    if (_session case final id?) {
      await channel.invokeMethod<void>('cancel', {'sessionId': id});
    }
  }
}

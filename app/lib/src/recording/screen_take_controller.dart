import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/script_document.dart';
import '../prompter/voice_activity.dart';
import '../storage/screen_take_store.dart';
import '../theme/theme.dart';
import 'floating_prompter.dart';
import 'recording_hud.dart';
import 'screen_recording.dart';
import 'screen_source.dart';

enum ScreenTakePhase {
  idle,
  preparing,
  countdown,
  starting,
  recording,
  paused,
  saving,
  saved,
  failed,
}

/// One owner for the protected windows, countdown, native capture and durable
/// take. Source/script data stays local; exceptions never enter messages/logs.
class ScreenTakeController extends ChangeNotifier {
  ScreenTakeController({
    required this.recorder,
    required this.huds,
    required this.floating,
    required this.store,
    this.wait = Future<void>.delayed,
  }) {
    _commands = huds.commands.listen((event) {
      if (event.sessionId != _hud?.sessionId) return;
      switch (event.command) {
        case 'stop':
          stop();
        case 'pause':
          unawaited(togglePause());
        case 'prompter':
          unawaited(togglePrompter());
        case 'lock':
          unawaited(lockPrompter());
      }
    });
  }
  final ScreenRecordings recorder;
  final RecordingHuds huds;
  final FloatingPrompters floating;
  final ScreenTakeStore store;
  final Future<void> Function(Duration) wait;
  late final StreamSubscription<HudCommand> _commands;
  ScreenTakePhase phase = ScreenTakePhase.idle;
  ScreenRecordingStatus? status;
  Take? take;
  String? problem;
  int countdown = 3;
  bool readerVisible = true;
  bool _stopWanted = false, _stopSent = false, _pauseChanging = false;
  bool _disposed = false, _unsafe = false;
  HudHandle? _hud;
  FloatingHandle? _reader;
  ScreenRecordingHandle? _capture;
  Future<void>? _run;
  bool _audio = true;
  String _microphone = 'Microphone';
  final _voice = VoiceActivity();
  bool get busy =>
      _unsafe ||
      const {
        ScreenTakePhase.preparing,
        ScreenTakePhase.countdown,
        ScreenTakePhase.starting,
        ScreenTakePhase.recording,
        ScreenTakePhase.paused,
        ScreenTakePhase.saving,
      }.contains(phase);
  bool get recording =>
      phase == ScreenTakePhase.recording || phase == ScreenTakePhase.paused;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _phase(ScreenTakePhase value) {
    phase = value;
    _changed();
  }

  Future<void> start({
    required FloatingPresentation presentation,
    required ScreenSource source,
    required bool recordAudio,
    String? microphoneId,
    String microphoneName = 'Microphone',
    Future<void> Function()? prepare,
  }) {
    if (busy || _disposed) return _run ?? Future<void>.value();
    _stopWanted = false;
    _stopSent = false;
    _unsafe = false;
    readerVisible = true;
    _audio = recordAudio;
    _microphone = microphoneName;
    status = null;
    take = null;
    problem = null;
    _voice.reset();
    _phase(ScreenTakePhase.preparing);
    return _run = _record(presentation, source, microphoneId, prepare);
  }

  Future<void> _record(
    FloatingPresentation presentation,
    ScreenSource source,
    String? microphoneId,
    Future<void> Function()? prepare,
  ) async {
    PendingScreenTake? pending;
    var cancelled = false;
    try {
      await prepare?.call();
      if (_stopWanted) { cancelled = true; return; }
      // The setup window and both overlays are excluded before countdown or
      // capture. A late reply after cancellation still belongs to this owner.
      _hud = await huds.open(source);
      if (_stopWanted) {
        cancelled = true;
        return;
      }
      _reader = await floating.open(presentation);
      if (_stopWanted) {
        cancelled = true;
        return;
      }
      _phase(ScreenTakePhase.countdown);
      for (countdown = 3; countdown > 0; --countdown) {
        await _updateHud();
        _changed();
        await wait(SaDurations.beat);
        if (_stopWanted) {
          cancelled = true;
          return;
        }
      }
      pending = await store.reserve(
        presentation: presentation,
        source: source,
        recordAudio: _audio,
        microphoneName: _audio ? _microphone : null,
        pace: presentation.pace.name,
      );
      if (_stopWanted) {
        cancelled = true;
        return;
      }
      _phase(ScreenTakePhase.starting);
      _capture = await recorder.start(
        source: source,
        path: pending.videoPath,
        recordAudio: _audio,
        microphoneId: microphoneId,
      );
      final startup = Stopwatch()..start();
      while (true) {
        if (_stopWanted && !_stopSent) {
          await recorder.stop(_capture!);
          _stopSent = true;
          _phase(ScreenTakePhase.saving);
        }
        status = await recorder.status(_capture!);
        if (status!.terminal) break;
        if (!_stopSent) {
          _phase(switch (status!.phase) {
            ScreenRecordingPhase.recording => ScreenTakePhase.recording,
            ScreenRecordingPhase.paused => ScreenTakePhase.paused,
            ScreenRecordingPhase.saving => ScreenTakePhase.saving,
            _ => ScreenTakePhase.starting,
          });
        }
        if (phase == ScreenTakePhase.starting &&
            startup.elapsed > SaDurations.beat * 7) {
          problem = 'No recording received. Restore the source and try again.';
          stop();
        }
        final speaking =
            _audio && _voice.update(status!.rmsDb, SaDurations.recordingPoll);
        await floating.update(
          _reader!,
          FloatingRecordingState(
            active: recording,
            paused: phase == ScreenTakePhase.paused,
            speaking: speaking,
          ),
        );
        readerVisible = await floating.isOpen(_reader!);
        if (!await huds.isOpen(_hud!)) {
          throw StateError('Protected controls unavailable');
        }
        await _updateHud();
        await wait(SaDurations.recordingPoll);
      }
    } on Object {
      problem =
          'Recording stopped. Check the screen and microphone, then try again.';
    } finally {
      _phase(ScreenTakePhase.saving);
      try {
        await _updateHud();
      } on Object {
        /* Keep protection until release. */
      }
      final capture = _capture;
      if (capture != null) {
        try {
          await recorder.release(capture);
          _capture = null;
        } on Object {
          // Never reveal the main window to an unconfirmed capture worker.
          _unsafe = true;
          problem = 'Recording could not finish. Close and reopen SpawnAlpha to recover it.';
        }
      }
      if (!_unsafe) {
        if (pending != null) {
          try {
            if (cancelled) {
              await store.abandon(pending);
            } else {
              take = await store.finish(
                pending,
                status ??
                    const ScreenRecordingStatus(
                      phase: ScreenRecordingPhase.failed,
                      reason: ScreenRecordingReason.encoder,
                    ),
              );
              problem ??= _stopMessage(
                status?.reason ?? ScreenRecordingReason.encoder,
              );
              if (_audio && (status?.loudestRmsDb ?? -100) < -55) {
                problem =
                    '${problem == null ? '' : '${problem!} '}$_microphone heard almost nothing. Check your sound before the next take.';
              }
            }
          } on Object {
            try {
              await store.abandon(pending);
            } on Object {
              /* Preserve recovery. */
            }
            problem = 'No take saved yet. Any captured video stays on this PC for recovery when you reopen the app.';
          }
        }
        final reader = _reader;
        _reader = null;
        final hud = _hud;
        _hud = null;
        if (reader != null) {
          try {
            await floating.close(reader);
          } on Object {
            /* Already closed. */
          }
        }
        if (hud != null) {
          try {
            await huds.close(hud);
          } on Object {
            /* Already closed. */
          }
        }
      }
      _phase(
        take != null
            ? ScreenTakePhase.saved
            : cancelled
            ? ScreenTakePhase.idle
            : ScreenTakePhase.failed,
      );
    }
  }

  static String? _stopMessage(ScreenRecordingReason reason) => switch (reason) {
    ScreenRecordingReason.source =>
      'The source closed or became unavailable. The captured part is saved.',
    ScreenRecordingReason.microphone =>
      'The microphone disconnected. The captured part is saved.',
    ScreenRecordingReason.encoder =>
      'Recording stopped early. The readable part is saved.',
    _ => null,
  };
  Future<void> _updateHud() async {
    final hud = _hud;
    if (hud == null) return;
    await huds.update(
      hud,
      HudState(
        phase: switch (phase) {
          ScreenTakePhase.countdown => HudPhase.countdown,
          ScreenTakePhase.recording => HudPhase.recording,
          ScreenTakePhase.paused => HudPhase.paused,
          ScreenTakePhase.saving => HudPhase.saving,
          _ => HudPhase.preparing,
        },
        countdown: countdown.clamp(1, 3),
        duration: status?.duration ?? Duration.zero,
        microphone: _microphone,
        peakDb: status?.peakDb ?? -100,
        recordAudio: _audio,
        prompterOpen: readerVisible,
      ),
    );
  }

  void stop() {
    if (busy) _stopWanted = true;
  }

  Future<void> togglePause() async {
    final capture = _capture;
    if (!recording || capture == null || _pauseChanging || _stopWanted) return;
    _pauseChanging = true;
    try {
      await recorder.pause(capture, phase != ScreenTakePhase.paused);
    } on Object {
      problem = 'Pause could not change. The take is stopping safely.';
      stop();
    } finally {
      _pauseChanging = false;
    }
  }

  Future<void> togglePrompter() async {
    final reader = _reader;
    if (reader == null || !recording || _stopWanted) return;
    try {
      await floating.show(reader, !readerVisible);
      readerVisible = !readerVisible;
      await _updateHud();
    } on Object {
      problem =
          'The hidden reader is unavailable. The take is stopping safely.';
      stop();
    }
  }

  Future<void> lockPrompter() async {
    final reader = _reader;
    if (reader == null || !recording || _stopWanted) return;
    try {
      await floating.lock(reader);
    } on Object {
      /* Child explains shortcut conflict. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    unawaited(_commands.cancel());
    // _record keeps ownership until native finalization and local saving finish.
    super.dispose();
  }
}

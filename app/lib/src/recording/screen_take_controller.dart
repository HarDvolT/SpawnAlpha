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
import 'camera_bubble.dart';

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
    this.bubbles = const UnsupportedCameraBubbles(),
    this.wait = Future<void>.delayed,
    this.cameraFollow,
    this.rememberCameraFollow,
  }) {
    _readerCommands = floating.commands.listen((event) {
      if (event.sessionId == _reader?.sessionId &&
          event.command == 'companionAsk') {
        unawaited(askCompanion());
      }
    });
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
        case 'companion':
          unawaited(toggleCompanion());
        case 'companionAsk':
          unawaited(askCompanion());
        case 'companionDocked':
          unawaited(chooseCompanion(false));
        case 'companionFollow':
          unawaited(chooseCompanion(true));
        case 'companionCancel':
          companionQuestion = false;
          unawaited(_updateHud());
      }
    });
  }
  final ScreenRecordings recorder;
  final RecordingHuds huds;
  final FloatingPrompters floating;
  final ScreenTakeStore store;
  final CameraBubbles bubbles;
  final Future<void> Function(Duration) wait;
  bool? cameraFollow;
  final Future<void> Function(bool)? rememberCameraFollow;
  bool companion = false, companionQuestion = false;
  bool _placementChanging = false, _reduceMotion = false;
  bool _visibilityChanging = false;
  int _readerVersion = 0;
  late final StreamSubscription<HudCommand> _commands;
  late final StreamSubscription<FloatingCommand> _readerCommands;
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
  CameraBubbleHandle? _bubble;
  String? _cameraId, _cameraName;
  Future<void>? _run;
  bool _audio = true;
  bool _systemAudio = false;
  bool _activity = false;
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
    bool recordSystemAudio = false,
    bool recordActivity = false,
    String? microphoneId,
    String microphoneName = 'Microphone',
    String? cameraId,
    String? cameraName,
    bool reduceMotion = false,
    Future<void> Function()? prepare,
  }) {
    if (busy || _disposed) return _run ?? Future<void>.value();
    if ((cameraId == null) != (cameraName == null) ||
        cameraId == '' ||
        cameraName == '' ||
        (cameraId != null && !bubbles.supported)) {
      problem = 'Choose a working camera before recording Both.';
      _phase(ScreenTakePhase.failed);
      return Future<void>.value();
    }
    _stopWanted = false;
    _stopSent = false;
    _unsafe = false;
    readerVisible = true;
    companion = companionQuestion = false;
    _reduceMotion = reduceMotion;
    _audio = recordAudio;
    _systemAudio = recordSystemAudio;
    _activity = recordActivity;
    _microphone = microphoneName;
    _cameraId = cameraId;
    _cameraName = cameraName;
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
      if (_stopWanted) {
        cancelled = true;
        return;
      }
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
      if (_cameraName != null) {
        _bubble = await bubbles.open(source, _cameraName!);
        if (_stopWanted) {
          cancelled = true;
          return;
        }
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
        recordSystemAudio: _systemAudio,
        recordActivity: _activity,
        microphoneName: _audio ? _microphone : null,
        cameraName: _cameraName,
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
        recordSystemAudio: _systemAudio,
        activityPath: pending.activityPath,
        microphoneId: microphoneId,
        cameraId: _cameraId,
        cameraPath: pending.cameraPath,
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
            startup.elapsed > SaDurations.beat * (_cameraId == null ? 7 : 12)) {
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
        final readerVersion = _readerVersion;
        final visible = await floating.isOpen(_reader!);
        if (readerVersion == _readerVersion &&
            !_visibilityChanging &&
            !_placementChanging) {
          readerVisible = visible;
        }
        if (!await huds.isOpen(_hud!)) {
          throw StateError('Protected controls unavailable');
        }
        if (_bubble != null && !await bubbles.isSafe(_bubble!)) {
          throw StateError('Protected camera preview unavailable');
        }
        await _updateHud();
        await wait(SaDurations.recordingPoll);
      }
    } on Object {
      problem = _cameraId == null
          ? 'Recording stopped. Check the screen and microphone, then try again.'
          : 'Recording stopped. Check the screen, camera and microphone, then try again.';
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
              if (_activity && take!.activityPath == null) {
                problem =
                    '${problem == null ? '' : '${problem!} '}The video is saved. Activity could not be read; automatic edits can use the video alone.';
              }
              if (pending.cameraPath != null && take!.cameraPath == null) {
                problem =
                    '${problem == null ? '' : '${problem!} '}The screen is saved. The camera file could not be read. Its data stays on this PC.';
              }
              if (_audio && (status?.loudestRmsDb ?? -100) < -55) {
                problem =
                    '${problem == null ? '' : '${problem!} '}$_microphone heard almost nothing. Check your sound before the next take.';
              }
              if (_systemAudio && (status?.loudestSystemRmsDb ?? -100) < -55) {
                problem =
                    '${problem == null ? '' : '${problem!} '}Windows played almost nothing. Check computer sound before the next take.';
              }
            }
          } on Object {
            try {
              await store.abandon(pending);
            } on Object {
              /* Preserve recovery. */
            }
            problem = switch (status?.reason) {
              ScreenRecordingReason.systemAudio => 'Computer sound is unavailable. Check the Windows playback device. No take saved yet; any captured video stays on this PC for recovery.',
              ScreenRecordingReason.activity => 'Activity is unavailable. Switch Activity off, then try again. Any captured video stays on this PC for recovery.',
              _ => 'No take saved yet. Any captured video stays on this PC for recovery when you reopen the app.',
            };
          }
        }
        final reader = _reader;
        _reader = null;
        final hud = _hud;
        _hud = null;
        final bubble = _bubble;
        _bubble = null;
        if (bubble != null) {
          try {
            await bubbles.close(bubble);
          } on Object {
            /* Already closed. */
          }
        }
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
    ScreenRecordingReason.camera =>
      'The camera disconnected. The captured part is saved.',
    ScreenRecordingReason.systemAudio =>
      'The playback device became unavailable. The captured part is saved.',
    ScreenRecordingReason.activity =>
      'Activity recording stopped early. The readable video is saved.',
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
        recordSystemAudio: _systemAudio,
        prompterOpen: readerVisible,
        companion: companion,
        companionQuestion: recording && companionQuestion,
        camera: _cameraId != null,
        cameraFollow: cameraFollow,
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
    if (reader == null ||
        !recording ||
        _stopWanted ||
        _visibilityChanging ||
        _placementChanging) {
      return;
    }
    _visibilityChanging = true;
    ++_readerVersion;
    try {
      await floating.show(reader, !readerVisible);
      if (_stopWanted || !recording) return;
      readerVisible = !readerVisible;
      await _updateHud();
    } on Object {
      problem =
          'The hidden reader is unavailable. The take is stopping safely.';
      stop();
    } finally {
      _visibilityChanging = false;
      ++_readerVersion;
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

  Future<void> toggleCompanion() async {
    if (!recording ||
        _stopWanted ||
        _placementChanging ||
        _visibilityChanging) {
      return;
    }
    if (!companion && _cameraId != null && cameraFollow == null) {
      companionQuestion = true;
      await _updateHud();
      return;
    }
    await _placeCompanion(!companion);
  }

  Future<void> askCompanion() async {
    if (!recording || _stopWanted || _cameraId == null || _placementChanging) {
      return;
    }
    companionQuestion = true;
    await _updateHud();
  }

  Future<void> chooseCompanion(bool follow) async {
    if (!recording ||
        _stopWanted ||
        !companionQuestion ||
        _cameraId == null ||
        _placementChanging) {
      return;
    }
    cameraFollow = follow;
    companionQuestion = false;
    // A preference write must never interrupt a useful recording.
    try {
      await rememberCameraFollow?.call(follow);
    } on Object {
      /* Retain session choice. */
    }
    await _placeCompanion(true);
  }

  Future<void> _placeCompanion(bool enabled) async {
    final reader = _reader;
    if (reader == null ||
        !recording ||
        _stopWanted ||
        _placementChanging ||
        _visibilityChanging) {
      return;
    }
    _placementChanging = true;
    ++_readerVersion;
    try {
      await floating.placement(
        reader,
        CompanionPlacement(
          enabled: enabled,
          follow: _cameraId == null || cameraFollow == true,
          camera: _cameraId != null,
          reduceMotion: _reduceMotion,
        ),
      );
      if (_stopWanted || !recording) return;
      companion = enabled;
      if (!readerVisible) {
        await floating.show(reader, true);
        readerVisible = true;
      }
      await _updateHud();
    } on Object {
      problem =
          'The hidden reader is unavailable. The take is stopping safely.';
      stop();
    } finally {
      _placementChanging = false;
      ++_readerVersion;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    unawaited(_commands.cancel());
    unawaited(_readerCommands.cancel());
    // _record keeps ownership until native finalization and local saving finish.
    super.dispose();
  }
}

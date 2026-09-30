import 'dart:async';

import 'package:flutter/foundation.dart';

import '../prompter/voice_activity.dart';
import 'audio_input.dart';

/// Watches the chosen microphone while a prompter screen is open: the level
/// for the meter, whether the speaker is talking (for voice pacing), and
/// the loudest level of a take (to catch silent recordings).
class MicMonitor extends ChangeNotifier {
  MicMonitor(this.inputs, {this.pollEvery = const Duration(milliseconds: 50)});

  final AudioInputs inputs;
  final Duration pollEvery;
  final _voice = VoiceActivity();

  Timer? _timer;
  bool _polling = false;
  String? _inputId;
  List<AudioInput> _available = const [];
  MicLevel _level = MicLevel.silent;
  bool _speaking = false;
  double _loudestRmsDb = -100;
  bool _watchingAll = false;
  Map<String, MicLevel> _levels = const {};

  bool get supported => inputs.supported;

  /// The microphones found, the Windows default first.
  List<AudioInput> get available => _available;

  /// The chosen microphone's ID, or null for the default one.
  String? get inputId => _inputId;

  /// The microphone being listened to.
  AudioInput? get input =>
      _available.where((a) => _inputId == null ? a.isDefault : a.id == _inputId).firstOrNull ??
      _available.firstOrNull;

  MicLevel get level => _level;

  /// Whether the speaker is talking, with the gaps between words smoothed.
  bool get speaking => _speaking;

  /// The loudest level since [resetLoudest], in dBFS.
  double get loudestRmsDb => _loudestRmsDb;

  /// Every microphone's level, by ID, while [watchEveryMic] is on.
  Map<String, MicLevel> get levels => _levels;

  /// Windows refused access to the microphones: the privacy switches are
  /// off for desktop apps. Takes would be silent.
  bool get blocked => _level.denied || (_levels.isNotEmpty && _levels.values.every((l) => l.denied));

  /// Lists the microphones, keeps [preferredId] if it is still there, and
  /// starts listening. Returns the ID in use (null: the default).
  Future<String?> start(String? preferredId) async {
    if (!supported) return null;
    _available = await inputs.list();
    _inputId = preferredId != null && _available.any((a) => a.id == preferredId) ? preferredId : null;
    await inputs.select(_inputId);
    await inputs.startLevels(_inputId);
    _timer?.cancel();
    _timer = Timer.periodic(pollEvery, (_) => _poll());
    notifyListeners();
    return _inputId;
  }

  /// Switches to [id] (null: the default). New cameras record from it.
  Future<void> choose(String? id) async {
    _inputId = id;
    _voice.reset();
    await inputs.select(id);
    await inputs.startLevels(id);
    notifyListeners();
  }

  void resetLoudest() => _loudestRmsDb = -100;

  /// Meters every microphone as well as the chosen one, so the record
  /// set-up can show which one moves when you talk. Stop it while
  /// recording.
  Future<void> watchEveryMic() async {
    if (!supported || _watchingAll) return;
    _watchingAll = true;
    await inputs.watchAll();
  }

  Future<void> stopWatchingAll() async {
    if (!_watchingAll) return;
    _watchingAll = false;
    _levels = const {};
    notifyListeners();
    if (supported) await inputs.unwatchAll();
  }

  /// Lists the microphones again and reopens them: after the user changed
  /// the privacy switches or plugged one in.
  Future<void> refresh() async {
    if (!supported) return;
    final watching = _watchingAll;
    if (watching) await stopWatchingAll();
    await start(_inputId);
    if (watching) await watchEveryMic();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      _level = await inputs.level();
      if (_watchingAll) _levels = await inputs.levels();
      _loudestRmsDb = _level.rmsDb > _loudestRmsDb ? _level.rmsDb : _loudestRmsDb;
      _speaking = _voice.update(_level.rmsDb, pollEvery);
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (supported) await inputs.stopLevels();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (supported) {
      inputs.stopLevels();
      if (_watchingAll) inputs.unwatchAll();
    }
    super.dispose();
  }
}

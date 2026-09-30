import 'package:flutter/foundation.dart';

import '../model/mark.dart';
import '../model/script_document.dart';
import '../model/token.dart';
import 'delivery_timeline.dart';

enum ScrollMode {
  /// The prompter scrolls itself at the planned pace, holding at pauses.
  timed,

  /// The prompter moves at the planned pace only while the speaker is
  /// talking, and waits when they stop. Planned pauses still run out in
  /// silence. Needs a microphone level (see [PrompterController.speaking]).
  voice,

  /// The user scrolls by hand, with a scroll wheel, a drag or the keys.
  manual,
}

enum PlaybackState { ready, playing, paused, finished }

/// Drives a read-through of a script: where the reader is, whether the
/// scroll is moving, and how fast.
///
/// The prompter widget calls [advance] every frame and reads [position]
/// to place the scroll. Listeners are notified only when something
/// discrete changes (the current word, a pause starting, play state,
/// speed or mode), not on every frame.
class PrompterController extends ChangeNotifier {
  PrompterController(ScriptDocument script, {this.mode = ScrollMode.timed})
      : _script = script,
        _marks = _acceptedMarks(script),
        _timeline = _buildTimeline(script);

  static const minSpeed = 0.5;
  static const maxSpeed = 2.0;
  static const speedStep = 0.1;

  ScriptDocument _script;
  DeliveryTimeline _timeline;

  ScriptDocument get script => _script;
  DeliveryTimeline get timeline => _timeline;
  List<Token> get tokens => _script.tokens;

  List<Mark> _marks;

  /// The marks the prompter shows: the ones the user accepted.
  List<Mark> get marks => _marks;

  ScrollMode mode;

  PlaybackState _state = PlaybackState.ready;
  PlaybackState get state => _state;
  bool get isPlaying => _state == PlaybackState.playing;

  double _speed = 1;

  /// A multiplier on the planned pace.
  double get speed => _speed;

  Duration _position = Duration.zero;

  /// Time into the planned read-through.
  Duration get position => _position;

  int _currentToken = 0;
  int get currentToken => _currentToken;

  bool _speaking = false;

  /// Whether the speaker is talking, fed from the microphone in voice mode.
  bool get speaking => _speaking;

  set speaking(bool value) {
    if (value == _speaking) return;
    _speaking = value;
    if (mode == ScrollMode.voice) notifyListeners();
  }

  /// True while voice mode is waiting for the speaker to go on.
  bool get waitingForVoice =>
      mode == ScrollMode.voice && isPlaying && !_speaking && !_timeline.isHolding(_position);

  MarkKind? _holding;

  /// The pause, long pause or breath the prompter is holding on.
  MarkKind? get holding => _holding;

  /// Planned words per minute at the current speed.
  int get effectiveWpm => (_timeline.wordsPerMinute * _speed).round();

  /// Time left at the current speed.
  Duration get remaining => (_timeline.total - _position) * (1 / _speed);

  static List<Mark> _acceptedMarks(ScriptDocument script) =>
      List.unmodifiable(script.marks.where((m) => m.accepted));

  static DeliveryTimeline _buildTimeline(ScriptDocument script) =>
      DeliveryTimeline.build(script.tokens, _acceptedMarks(script), script.style);

  /// Swaps in an edited script and keeps the reader near the same word.
  void updateScript(ScriptDocument script) {
    final token = _currentToken;
    _script = script;
    _marks = _acceptedMarks(script);
    _timeline = _buildTimeline(script);
    _seek(_timeline.isEmpty ? Duration.zero : _timeline.startOf(token.clamp(0, _timeline.length - 1)));
    notifyListeners();
  }

  void play() {
    if (_timeline.isEmpty) return;
    if (_state == PlaybackState.finished) _seek(Duration.zero);
    _setState(PlaybackState.playing);
  }

  void pause() {
    if (_state == PlaybackState.playing) _setState(PlaybackState.paused);
  }

  void togglePlay() => isPlaying ? pause() : play();

  /// Back to the first word, stopped.
  void restart() {
    _seek(Duration.zero);
    _setState(PlaybackState.ready);
  }

  void setSpeed(double speed) {
    final clamped = (speed * 10).round().clamp(minSpeed * 10, maxSpeed * 10) / 10;
    if (clamped == _speed) return;
    _speed = clamped;
    notifyListeners();
  }

  void faster() => setSpeed(_speed + speedStep);

  void slower() => setSpeed(_speed - speedStep);

  void setMode(ScrollMode mode) {
    if (mode == this.mode) return;
    this.mode = mode;
    if (mode == ScrollMode.manual) pause();
    notifyListeners();
  }

  /// Moves time forward by [elapsed] of wall-clock time. Call it every
  /// frame; it does nothing unless the scroll is playing on its own (timed,
  /// or voice while the speaker talks or a planned pause runs out).
  void advance(Duration elapsed) {
    if (!isPlaying || mode == ScrollMode.manual) return;
    if (waitingForVoice) return;
    final next = _position + elapsed * _speed;
    if (next >= _timeline.total) {
      _seek(_timeline.total);
      _setState(PlaybackState.finished);
      return;
    }
    _seek(next, notify: true);
  }

  /// Jumps to the start of [token].
  void seekToToken(int token) {
    if (_timeline.isEmpty) return;
    _seek(_timeline.startOf(token.clamp(0, _timeline.length - 1)), notify: true);
    if (_state == PlaybackState.finished) _setState(PlaybackState.paused);
  }

  void nextSentence() {
    for (final r in sentenceRanges(tokens)) {
      if (r.start > _currentToken) return seekToToken(r.start);
    }
  }

  void previousSentence() {
    final ranges = sentenceRanges(tokens);
    final current = ranges.indexWhere((r) => r.contains(_currentToken));
    if (current < 0) return;
    // At the start of a sentence, go back to the one before it.
    final r = ranges[current];
    final target = _currentToken == r.start && current > 0 ? ranges[current - 1] : r;
    seekToToken(target.start);
  }

  /// Follows a hand scroll: the word under the reading line is now
  /// [token]. Used in manual mode.
  void followScroll(int token) {
    if (_timeline.isEmpty || token == _currentToken) return;
    _seek(_timeline.startOf(token.clamp(0, _timeline.length - 1)), notify: true);
  }

  void _seek(Duration position, {bool notify = false}) {
    _position = position;
    final token = _timeline.tokenAt(position);
    final holding = _timeline.holdingOn(position);
    if (token != _currentToken || holding != _holding) {
      _currentToken = token;
      _holding = holding;
      if (notify) notifyListeners();
    }
  }

  void _setState(PlaybackState state) {
    if (state == _state) return;
    _state = state;
    notifyListeners();
  }
}

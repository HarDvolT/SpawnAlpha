/// Card changes on the recorder's pause-adjusted clock. A paused browse is
/// preparation, not a new chapter. Only the final selection on resume survives.
class NoteTimeline {
  NoteTimeline(this.cardCount) {
    if (cardCount < 1 || cardCount > 200) {
      throw const FormatException('Invalid card count');
    }
  }
  final int cardCount;
  final List<NoteMoment> _moments = [const NoteMoment(0, Duration.zero)];
  Duration _last = Duration.zero;
  List<NoteMoment> get moments => List.unmodifiable(_moments);
  bool observe(int index, Duration time, {required bool paused}) {
    if (index < 0 || index >= cardCount || time < _last) {
      throw const FormatException('Invalid card timing');
    }
    _last = time;
    if (paused || index == _moments.last.index) return false;
    if (_moments.last.time == time) _moments.removeLast();
    if (_moments.length >= 50000) throw const FormatException('Card timing capacity reached');
    _moments.add(NoteMoment(index, time));
    return true;
  }

  List<Map<String, Object?>> toJson() => [for (final m in _moments) m.toJson()];
}

class NoteMoment {
  const NoteMoment(this.index, this.time);
  final int index;
  final Duration time;
  Map<String, Object?> toJson() => {'cardIndex': index, 'timeUs': time.inMicroseconds};
}

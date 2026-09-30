import '../model/coaching_style.dart';
import '../model/mark.dart';
import '../model/token.dart';

/// How long a breath mark holds the scroll.
const breathHold = Duration(milliseconds: 350);

/// The planned timing of a read-through: when each word is spoken and how
/// long the prompter holds after it.
///
/// Word lengths follow the target words per minute, weighted by word
/// length, and pace marks stretch or squeeze them. Gap marks hold for
/// the style's pause lengths, and punctuation adds a short natural beat.
/// All times are in microseconds from the start of the script.
class DeliveryTimeline {
  DeliveryTimeline._(this._starts, this._ends, this._gapKinds, this._spokenBefore, this.wordsPerMinute);

  /// Builds the timeline for [tokens] at [wordsPerMinute], by default the
  /// middle of the style's range.
  factory DeliveryTimeline.build(
    List<Token> tokens,
    List<Mark> marks,
    CoachingStyle style, {
    int? wordsPerMinute,
  }) {
    final wpm = wordsPerMinute ?? style.targetWpm;
    final n = tokens.length;
    final gapKinds = List<MarkKind?>.filled(n, null);
    final pace = List<double>.filled(n, 1);
    for (final m in marks) {
      if (m.end >= n) continue;
      if (m.kind.isGap) {
        gapKinds[m.end] = m.kind;
      } else if (m.kind.isPace) {
        for (var i = m.start; i <= m.end; i++) {
          pace[i] = m.kind == MarkKind.slower ? 1.25 : 0.8;
        }
      }
    }

    // Longer words take longer to say. Weights are normalized to average 1
    // so the words per minute still hold across the script.
    final words = tokens.where((t) => t.isWord).toList();
    final averageLength =
        words.isEmpty ? 1.0 : words.fold<int>(0, (sum, t) => sum + t.bare.length) / words.length;
    final weights = [
      for (final t in tokens) t.isWord ? (t.bare.length / averageLength).clamp(0.6, 1.8) : 0.0,
    ];
    final meanWeight = words.isEmpty ? 1.0 : weights.fold<double>(0, (a, b) => a + b) / words.length;
    final microsPerWord = 60e6 / wpm;

    final starts = List<int>.filled(n, 0);
    final ends = List<int>.filled(n, 0);
    final spokenBefore = List<int>.filled(n + 1, 0);
    var clock = 0;
    for (var i = 0; i < n; i++) {
      final speech = (microsPerWord * weights[i] / meanWeight * pace[i]).round();
      starts[i] = clock;
      ends[i] = clock + speech;
      spokenBefore[i + 1] = spokenBefore[i] + speech;
      clock = ends[i] + (i == n - 1 ? 0 : _hold(tokens[i], gapKinds[i], style).inMicroseconds);
    }
    return DeliveryTimeline._(starts, ends, gapKinds, spokenBefore, wpm);
  }

  static Duration _hold(Token token, MarkKind? mark, CoachingStyle style) => switch (mark) {
        MarkKind.pauseShort => style.shortPause,
        MarkKind.pauseLong => style.longPause,
        MarkKind.breath => breathHold,
        _ when token.endsParagraph => const Duration(milliseconds: 500),
        _ when token.endsSentence || token.endsLine => const Duration(milliseconds: 250),
        _ when token.endsClause => const Duration(milliseconds: 120),
        _ => Duration.zero,
      };

  final List<int> _starts;
  final List<int> _ends;
  final List<MarkKind?> _gapKinds;
  final List<int> _spokenBefore;
  final int wordsPerMinute;

  int get length => _starts.length;

  bool get isEmpty => _starts.isEmpty;

  Duration get total => Duration(microseconds: isEmpty ? 0 : _ends.last);

  Duration startOf(int token) => Duration(microseconds: _starts[token]);

  Duration endOf(int token) => Duration(microseconds: _ends[token]);

  /// The token being spoken at [time], or the last one spoken while the
  /// prompter holds between words.
  int tokenAt(Duration time) {
    if (isEmpty) return 0;
    final t = time.inMicroseconds;
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_starts[mid] <= t) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// True while the prompter holds between two words at [time].
  bool isHolding(Duration time) {
    if (isEmpty) return false;
    final i = tokenAt(time);
    return i < length - 1 && time.inMicroseconds >= _ends[i];
  }

  /// The gap mark the prompter is holding on at [time], if any.
  MarkKind? holdingOn(Duration time) => isHolding(time) ? _gapKinds[tokenAt(time)] : null;

  /// Speaking time before [token] starts, leaving out every hold.
  Duration spokenBefore(int token) => Duration(microseconds: _spokenBefore[token]);

  /// Speaking time up to [time], leaving out every hold. The scroll follows
  /// this, so it stands still during pauses.
  Duration spokenAt(Duration time) {
    if (isEmpty) return Duration.zero;
    final i = tokenAt(time);
    final into = (time.inMicroseconds - _starts[i]).clamp(0, _ends[i] - _starts[i]);
    return Duration(microseconds: _spokenBefore[i] + into);
  }
}

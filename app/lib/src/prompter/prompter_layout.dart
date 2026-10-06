import 'delivery_timeline.dart';
import 'guide.dart';

/// Where the prompter's words landed on screen: which line each token is
/// on, and the vertical extent of each line. The prompter widget measures
/// this after layout; the scroll maths below uses it.
class PrompterLayout {
  PrompterLayout({
    required this.lineOfToken,
    required this.lineTops,
    required this.lineBottoms,
    this.phraseStarts = const [],
  }) : assert(lineTops.length == lineBottoms.length) {
    for (var i = 0; i < lineOfToken.length; i++) {
      final line = lineOfToken[i];
      _firstOnLine.putIfAbsent(line, () => i);
      _lastOnLine[line] = i;
    }
  }

  /// For each token, the index into [lineTops] of the line it is on.
  final List<int> lineOfToken;
  final List<double> lineTops;
  final List<double> lineBottoms;

  /// Where each phrase starts (sorted token indices), for the One phrase
  /// motion. Empty otherwise.
  final List<int> phraseStarts;

  final _firstOnLine = <int, int>{};
  final _lastOnLine = <int, int>{};

  int get lineCount => lineTops.length;

  /// False for blank lines between paragraphs.
  bool hasWords(int line) => _firstOnLine.containsKey(line);

  int firstTokenOn(int line) => _firstOnLine[line] ?? 0;

  int lastTokenOn(int line) => _lastOnLine[line] ?? 0;

  /// The top of the line [token] is on.
  double topOf(int token) => lineTops[lineOfToken[token]];

  /// The phrase [token] is in: its first token and the first token of the
  /// next phrase (or the token count). The whole script is one phrase when
  /// there are no [phraseStarts].
  (int start, int end) phraseOf(int token) {
    if (phraseStarts.isEmpty) return (0, lineOfToken.length);
    var low = 0;
    var high = phraseStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (phraseStarts[mid] <= token) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final end = low + 1 < phraseStarts.length ? phraseStarts[low + 1] : lineOfToken.length;
    return (phraseStarts[low], end);
  }

  /// The first token of the line at vertical position [y], or of the
  /// nearest line with words on it.
  int tokenAtY(double y) {
    if (lineOfToken.isEmpty) return 0;
    var best = 0;
    var bestDistance = double.infinity;
    for (final entry in _firstOnLine.entries) {
      final top = lineTops[entry.key];
      final bottom = lineBottoms[entry.key];
      if (y >= top && y < bottom) return entry.value;
      final distance = y < top ? top - y : y - bottom;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = entry.value;
      }
    }
    return best;
  }

  /// The vertical position to put under the reading line at [time].
  ///
  /// With [PrompterMotion.lineStep] it is the top of the line being
  /// spoken: the line being read stays still, so the eye can hold its
  /// place, and the view glides to the next line as its first word starts.
  ///
  /// With [PrompterMotion.smooth] the scroll moves at an even rate through
  /// each line while it is spoken, reaching the next line as the line's
  /// last word ends.
  ///
  /// With [PrompterMotion.phrase] it is the top of the phrase being
  /// spoken, which sits on the reading line until the next phrase starts.
  ///
  /// Either way, nothing moves during a pause.
  double scrollYAt(DeliveryTimeline timeline, Duration time, {PrompterMotion motion = PrompterMotion.lineStep, double? phraseViewportHeight}) {
    if (timeline.isEmpty || lineOfToken.length != timeline.length) return 0;
    final token = timeline.tokenAt(time);
    final line = lineOfToken[token];
    if (motion == PrompterMotion.lineStep) return lineTops[line];
    if (motion == PrompterMotion.phrase) {
      final (start, end) = phraseOf(token);
      final firstLine = lineOfToken[start], lastLine = lineOfToken[end - 1];
      // A compact reader still shows One phrase, stepping within long phrases
      // so its current word cannot disappear beneath the card.
      if (phraseViewportHeight != null && lineBottoms[lastLine] - lineTops[firstLine] > phraseViewportHeight) {
        return lineTops[line];
      }
      return lineTops[firstLine];
    }
    final first = firstTokenOn(line);
    final last = lastTokenOn(line);
    final from = timeline.spokenBefore(first).inMicroseconds;
    final to = timeline.spokenBefore(last).inMicroseconds + (timeline.endOf(last) - timeline.startOf(last)).inMicroseconds;
    final spoken = timeline.spokenAt(time).inMicroseconds;
    final progress = to > from ? ((spoken - from) / (to - from)).clamp(0.0, 1.0) : 1.0;
    final top = lineTops[line];
    final next = last + 1 < lineOfToken.length ? topOf(last + 1) : lineBottoms[line];
    return top + progress * (next - top);
  }
}

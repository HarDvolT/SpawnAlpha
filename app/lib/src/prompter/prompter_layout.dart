import 'delivery_timeline.dart';

/// Where the prompter's words landed on screen: which line each token is
/// on, and the vertical extent of each line. The prompter widget measures
/// this after layout; the scroll maths below uses it.
class PrompterLayout {
  PrompterLayout({required this.lineOfToken, required this.lineTops, required this.lineBottoms})
      : assert(lineTops.length == lineBottoms.length) {
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

  final _firstOnLine = <int, int>{};
  final _lastOnLine = <int, int>{};

  int get lineCount => lineTops.length;

  /// False for blank lines between paragraphs.
  bool hasWords(int line) => _firstOnLine.containsKey(line);

  int firstTokenOn(int line) => _firstOnLine[line] ?? 0;

  int lastTokenOn(int line) => _lastOnLine[line] ?? 0;

  /// The top of the line [token] is on.
  double topOf(int token) => lineTops[lineOfToken[token]];

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

  /// The vertical position to put under the reading line at [time]: the
  /// top of the line being spoken.
  ///
  /// The line being read stays still, so the eye can hold its place, and
  /// the view glides to the next line as its first word starts. During a
  /// pause nothing moves.
  double scrollYAt(DeliveryTimeline timeline, Duration time) {
    if (timeline.isEmpty || lineOfToken.length != timeline.length) return 0;
    return lineTops[lineOfToken[timeline.tokenAt(time)]];
  }
}

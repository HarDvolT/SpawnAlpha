/// A whitespace-separated chunk of a script, with its punctuation attached.
///
/// Marks refer to tokens by [index], so they stay separate from the script
/// text and survive edits (see `remapMarks`).
class Token {
  Token({
    required this.index,
    required this.text,
    required this.start,
    required this.end,
    required this.lineBreaksBefore,
    required this.lineBreaksAfter,
  });

  final int index;
  final String text;

  /// Character offsets of this token in the script text.
  final int start;
  final int end;

  /// How many line breaks separate this token from its neighbours.
  final int lineBreaksBefore;
  final int lineBreaksAfter;

  /// True when the token holds at least one letter or digit, so it is
  /// spoken. A lone dash or bullet is not.
  late final bool isWord = _letterOrDigit.hasMatch(text);

  /// The token lowercased, without surrounding punctuation or Arabic
  /// diacritics, for dictionary lookups and comparisons.
  late final String bare = normalizeWord(text);

  late final String _trailing = _stripClosers(text);

  bool get endsSentence => _sentenceEnd.hasMatch(_trailing);

  bool get endsClause => !endsSentence && (_clauseEnd.hasMatch(_trailing) || _dash.hasMatch(text));

  /// True when the token is the last one on its line.
  bool get endsLine => lineBreaksAfter > 0;

  bool get endsParagraph => lineBreaksAfter > 1;

  bool get hasDigit => _digit.hasMatch(text);

  /// All-caps words of three letters or more, which writers use to stress.
  bool get isShouted {
    final letters = bare.length;
    return letters >= 3 && text.toUpperCase() == text && text.toLowerCase() != text;
  }

  @override
  String toString() => 'Token($index, "$text")';
}

/// An inclusive range of token indices.
class TokenRange {
  const TokenRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;

  bool contains(int index) => index >= start && index <= end;

  @override
  bool operator ==(Object other) => other is TokenRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start..$end]';
}

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _digit = RegExp(r'\p{Nd}', unicode: true);
final _closers = RegExp(r'''["'”’»)\]}*_]+$''');
final _sentenceEnd = RegExp(r'([.!?…؟‼⁉]|\.\.\.)$');
final _clauseEnd = RegExp(r'[,;:،؛]$');
final _dash = RegExp(r'^[—–-]+$|[—–]$');
final _edgePunctuation = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);
final _arabicMarks = RegExp(r'[ؐ-ًؚ-ٰٟۖ-ۭـ]');

String _stripClosers(String text) => text.replaceAll(_closers, '');

/// Lowercases [word], strips punctuation around it and folds the Arabic
/// letter variants that writers use interchangeably, so that dictionary
/// lookups and text comparisons ignore them.
String normalizeWord(String word) {
  var w = word.replaceAll('’', "'").replaceAll(_edgePunctuation, '').toLowerCase();
  if (w.isEmpty) return w;
  w = w
      .replaceAll(_arabicMarks, '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
  return w;
}

/// Splits [text] into tokens on whitespace.
List<Token> tokenize(String text) {
  final matches = RegExp(r'\S+').allMatches(text).toList();
  final breaks = List<int>.filled(matches.length + 1, 0);
  var previousEnd = 0;
  for (var i = 0; i < matches.length; i++) {
    if (i > 0) breaks[i] = _countNewlines(text, previousEnd, matches[i].start);
    previousEnd = matches[i].end;
  }
  return [
    for (var i = 0; i < matches.length; i++)
      Token(
        index: i,
        text: matches[i][0]!,
        start: matches[i].start,
        end: matches[i].end,
        lineBreaksBefore: breaks[i],
        lineBreaksAfter: breaks[i + 1],
      ),
  ];
}

int _countNewlines(String text, int from, int to) {
  var count = 0;
  for (var i = from; i < to; i++) {
    if (text.codeUnitAt(i) == 0x0A) count++;
  }
  return count;
}

/// Splits tokens into sentences. A line break also ends a sentence, so
/// bullet points and headings without punctuation are kept apart.
List<TokenRange> sentenceRanges(List<Token> tokens) {
  final ranges = <TokenRange>[];
  var start = 0;
  for (final t in tokens) {
    if (t.endsSentence || t.endsLine || t.index == tokens.length - 1) {
      ranges.add(TokenRange(start, t.index));
      start = t.index + 1;
    }
  }
  return ranges;
}

/// The sentence that holds token [index].
TokenRange sentenceAt(List<Token> tokens, int index) {
  for (final r in sentenceRanges(tokens)) {
    if (r.contains(index)) return r;
  }
  return TokenRange(index, index);
}

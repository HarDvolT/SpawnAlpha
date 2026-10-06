import '../markup/lexicon.dart';
import '../model/cut_plan.dart';
import '../model/script_document.dart';
import 'script_alignment.dart';
import 'word_timing.dart';

/// Original source intervals only; a later cut must retain all this evidence.
/// Notes/free speech and an unsaid/uncertain script phrase never imply a target.
List<SourceRange> pointingPhrases({
  required WordTranscript source,
  ScriptDocument? snapshot,
  bool aligned = false,
  required Duration maximumSpan,
}) {
  if (!aligned || snapshot == null || snapshot.usesNotes) return const [];
  if (maximumSpan <= Duration.zero ||
      maximumSpan > const Duration(seconds: 5)) {
    throw const FormatException('Invalid pointing phrase window');
  }
  final alignment = alignTranscript(snapshot, source);
  final lexicon = Lexicon.of(source.language);
  final phrases = <int, int>{};
  for (var i = 0; i < snapshot.tokens.length; ++i) {
    final length = lexicon.matchAt(lexicon.pointing, snapshot.tokens, i);
    if (length > 0) phrases[i] = length;
  }
  final result = <SourceRange>[];
  for (var i = 0; i < alignment.words.length; ++i) {
    final first = alignment.words[i];
    final length = phrases[first.tokenIndex];
    if (length == null || i + length > alignment.words.length) continue;
    var reliable = true;
    for (var offset = 0; offset < length; ++offset) {
      final match = alignment.words[i + offset];
      final word = source.words[match.spokenIndex];
      if (match.tokenIndex != first.tokenIndex! + offset ||
          match.attempt != first.attempt ||
          match.match != WordMatch.exact ||
          (offset < length - 1 &&
              snapshot.tokens[match.tokenIndex!].endsSentence) ||
          (!word.corrected && (word.confidence ?? 0) < .6)) {
        reliable = false;
        break;
      }
    }
    final start = source.words[first.spokenIndex].start;
    final end = source.words[alignment.words[i + length - 1].spokenIndex].end;
    if (reliable && end - start <= maximumSpan) {
      result.add(SourceRange(start: start, end: end));
    }
  }
  return List.unmodifiable(result);
}

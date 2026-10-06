import 'dart:typed_data';

import '../model/script_document.dart';
import 'word_timing.dart';

enum WordMatch { exact, changed, added }

/// Each spoken word is preserved exactly once, including rejected attempts.
class AlignedWord {
  const AlignedWord({
    required this.spokenIndex,
    required this.tokenIndex,
    required this.match,
    required this.attempt,
  });
  final int spokenIndex;
  final int? tokenIndex;
  final WordMatch match;
  final int attempt;
}

class ScriptAlignment {
  ScriptAlignment._(
    this.transcript,
    List<AlignedWord> words,
    List<int> missed,
    List<int> unspoken,
  ) : words = List.unmodifiable(words),
      missedTokens = List.unmodifiable(missed),
      unspokenTokens = List.unmodifiable(unspoken);

  final WordTranscript transcript;
  final List<AlignedWord> words;
  final List<int> missedTokens;

  /// Punctuation-only script tokens have no spoken timing and are not missed.
  final List<int> unspokenTokens;
  int get attemptCount => words.isEmpty ? 0 : words.last.attempt + 1;
  List<AlignedWord> occurrences(int tokenIndex) =>
      List.unmodifiable(words.where((word) => word.tokenIndex == tokenIndex));
}

/// Sequence alignment with explicit backward jumps for anchored restarts.
///
/// Comparisons use the model's EN/FR/AR normalization. A jump needs three exact
/// upcoming words (two when that is the whole script), so a lone repeated common
/// word cannot masquerade as a retake. Substitutions are flagged, never rewritten.
/// Memory/work are bounded; a caller must chunk a long take or run off the UI
/// thread, rather than silently returning fabricated/missing timings.
ScriptAlignment alignTranscript(
  ScriptDocument script,
  WordTranscript transcript, {
  int maxCells = 4000000,
}) {
  if (script.language != transcript.language) {
    throw const FormatException('Transcript language does not match script');
  }
  final tokens = script.tokens.where((token) => token.isWord).toList();
  final n = tokens.length, m = transcript.words.length, width = n + 1;
  if (maxCells < 1 || maxCells > 4000000 || (m + 1) * width > maxCells) {
    throw const FormatException('Alignment needs smaller sections');
  }
  final source = [for (final token in tokens) token.bare];
  final spoken = [for (final word in transcript.words) word.bare];
  // Codes: 1 diagonal, 2 added speech, 3 missed script, 4 anchored restart.
  final trace = Uint8List((m + 1) * width);
  final jump = Uint32List(trace.length);
  var previous = Int32List(width);
  var previousRun = Uint8List(width);
  for (var j = 1; j <= n; j++) {
    previous[j] = -2 * j;
    trace[j] = 3;
  }
  final anchorLength = n == 2 ? 2 : 3;
  for (var i = 1; i <= m; i++) {
    final suffix = Int32List(width), suffixIndex = Uint32List(width);
    if (n > 0) {
      suffix[n] = previousRun[n] >= anchorLength ? previous[n] : -1000000000;
      suffixIndex[n] = n;
    }
    for (var j = n - 1; j >= 0; j--) {
      if (previousRun[j] >= anchorLength && previous[j] >= suffix[j + 1]) {
        suffix[j] = previous[j];
        suffixIndex[j] = j;
      } else {
        suffix[j] = suffix[j + 1];
        suffixIndex[j] = suffixIndex[j + 1];
      }
    }
    final current = Int32List(width);
    final currentRun = Uint8List(width);
    current[0] = previous[0] - 2;
    trace[i * width] = 2;
    for (var j = 1; j <= n; j++) {
      final exact = source[j - 1] == spoken[i - 1];
      var best = previous[j - 1] + (exact ? 3 : -3), code = 1;
      if (previous[j] - 2 > best) {
        best = previous[j] - 2;
        code = 2;
      }
      if (current[j - 1] - 2 > best) {
        best = current[j - 1] - 2;
        code = 3;
      }
      if (exact && j + anchorLength - 1 <= n && i + anchorLength - 1 <= m) {
        var anchored = true;
        for (var k = 1; k < anchorLength; k++) {
          if (source[j - 1 + k] != spoken[i - 1 + k]) {
            anchored = false;
            break;
          }
        }
        // Both attempts need anchor-length exact matches. Initial script
        // deletions must not count as having spoken a previous attempt.
        final rewindFrom = j + anchorLength - 1;
        if (anchored && suffix[rewindFrom] - 4 + 3 > best) {
          best = suffix[rewindFrom] - 4 + 3;
          code = 4;
          jump[i * width + j] = suffixIndex[rewindFrom];
        }
      }
      current[j] = best;
      trace[i * width + j] = code;
      currentRun[j] = switch (code) {
        1 => exact ? (previousRun[j - 1] + 1).clamp(0, anchorLength) : 0,
        2 => previousRun[j],
        4 => 1,
        _ => 0,
      };
    }
    previous = current;
    previousRun = currentRun;
  }
  var i = m, j = n;
  final reverse = <(int, int?, WordMatch)>[];
  while (i > 0 || j > 0) {
    switch (trace[i * width + j]) {
      case 1:
        reverse.add((
          i - 1,
          tokens[j - 1].index,
          source[j - 1] == spoken[i - 1] ? WordMatch.exact : WordMatch.changed,
        ));
        i--;
        j--;
      case 2:
        reverse.add((i - 1, null, WordMatch.added));
        i--;
      case 3:
        j--;
      case 4:
        reverse.add((i - 1, tokens[j - 1].index, WordMatch.exact));
        j = jump[i * width + j];
        i--;
      default:
        throw StateError('Invalid alignment state');
    }
  }
  final words = <AlignedWord>[];
  final covered = <int>{};
  var attempt = 0;
  int? lastToken;
  for (final (spokenIndex, tokenIndex, match) in reverse.reversed) {
    if (tokenIndex != null) {
      if (lastToken != null && tokenIndex <= lastToken) attempt++;
      covered.add(tokenIndex);
      lastToken = tokenIndex;
    }
    words.add(
      AlignedWord(
        spokenIndex: spokenIndex,
        tokenIndex: tokenIndex,
        match: match,
        attempt: attempt,
      ),
    );
  }
  return ScriptAlignment._(
    transcript,
    words,
    [
      for (final token in tokens)
        if (!covered.contains(token.index)) token.index,
    ],
    [
      for (final token in script.tokens)
        if (!token.isWord) token.index,
    ],
  );
}

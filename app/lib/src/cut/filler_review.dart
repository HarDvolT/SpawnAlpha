import '../markup/lexicon.dart';
import '../model/cut_plan.dart';
import '../model/script_document.dart';
import '../transcription/script_alignment.dart';
import '../transcription/word_timing.dart';
import 'clean_plan.dart';
import 'quiet_evidence.dart';

/// Proposals only: lexical matches do not establish an unwanted hesitation.
/// Boundaries require measured quiet, clear words and the frozen aid policy.
CleanPlan withFillerReview({
  required CleanPlan base,
  required WordTranscript transcript,
  required List<SourceRange> quiet,
  ScriptDocument? snapshot,
  ScriptAlignment? alignment,
  bool screenContext = false,
}) {
  speechOnCleanCut(transcript, base);
  if (base.fillersReviewed) return base;
  final changes = [...base.changes];
  CleanPlan finish() {
    changes.sort((a, b) => a.range.start.compareTo(b.range.start));
    final plan = CleanPlan(
      takeId: base.takeId,
      language: base.language,
      sourceDuration: base.sourceDuration,
      changes: changes,
      fillersReviewed: true,
      notice: base.notice,
      retakesReviewed: base.retakesReviewed,
      retakes: base.retakes,
    );
    speechOnCleanCut(transcript, plan);
    return plan;
  }

  if (screenContext ||
      snapshot == null ||
      (!snapshot.usesNotes && alignment == null)) {
    return finish();
  }
  if (snapshot.language != transcript.language ||
      (alignment != null &&
          alignment.words.length != transcript.words.length)) {
    throw const FormatException('Filler review mismatch');
  }
  var previous = Duration.zero;
  for (final range in quiet) {
    if (range.start < previous || range.end > transcript.duration) {
      throw const FormatException('Invalid quiet evidence');
    }
    previous = range.end;
  }
  final scriptWords = snapshot.tokens
      .where((t) => t.isWord)
      .map((t) => t.bare)
      .toList();
  final vocabulary = Lexicon.of(transcript.language).fillers;
  final scriptedPhrases = <String, bool>{};
  final protected = snapshot.usesNotes || alignment == null
      ? <SourceRange>[]
      : protectedCueGaps(snapshot, alignment, transcript);
  protected.sort((a, b) => a.start.compareTo(b.start));
  final bare = transcript.words.map((w) => w.bare).toList();
  var lastProposalEnd = Duration.zero, existingIndex = 0, protectionIndex = 0;
  for (var index = 0; index < bare.length && changes.length < 10000; index++) {
    final candidates = vocabulary.startingWith(bare[index]);
    for (final phrase in candidates) {
      final endIndex = index + phrase.length;
      if (endIndex > bare.length) continue;
      var valid = true;
      for (var k = 0; k < phrase.length; k++) {
        final word = transcript.words[index + k];
        valid =
            valid &&
            bare[index + k] == phrase[k] &&
            word.confidence != null &&
            word.confidence! >= .6 &&
            (snapshot.usesNotes ||
                alignment!.words[index + k].match == WordMatch.added) &&
            (k == 0 ||
                word.start - transcript.words[index + k - 1].end <=
                    const Duration(milliseconds: 700));
      }
      if (!valid ||
          (!snapshot.usesNotes &&
              scriptedPhrases.putIfAbsent(
                phrase.join(' '),
                () => _contains(scriptWords, phrase),
              ))) {
        continue;
      }
      final first = transcript.words[index],
          last = transcript.words[endIndex - 1];
      var lower = index == 0
          ? Duration.zero
          : transcript.words[index - 1].end +
                wordSafetyMargin(transcript.words[index - 1]);
      var upper = endIndex == bare.length
          ? transcript.duration
          : transcript.words[endIndex].start -
                wordSafetyMargin(transcript.words[endIndex]);
      if (lastProposalEnd > lower) lower = lastProposalEnd;
      while (existingIndex < base.changes.length &&
          base.changes[existingIndex].range.end <= first.start) {
        existingIndex++;
      }
      if (existingIndex > 0 &&
          base.changes[existingIndex - 1].range.end > lower) {
        lower = base.changes[existingIndex - 1].range.end;
      }
      if (existingIndex < base.changes.length &&
          base.changes[existingIndex].range.start < upper) {
        upper = base.changes[existingIndex].range.start;
      }
      final start = quietBoundary(
        quiet,
        lower,
        first.start - const Duration(milliseconds: 100),
        latest: true,
      );
      final end = quietBoundary(
        quiet,
        last.end + const Duration(milliseconds: 100),
        upper,
        latest: false,
      );
      if (start == null || end == null || end <= start) continue;
      while (protectionIndex < protected.length &&
          protected[protectionIndex].end <= start) {
        protectionIndex++;
      }
      if (protectionIndex < protected.length &&
          protected[protectionIndex].start < end) {
        continue;
      }
      changes.add(
        CutChange(
          id: 'filler-$index',
          kind: CutChangeKind.filler,
          enabled: false,
          range: SourceRange(start: start, end: end),
          spokenIndices: [for (var i = index; i < endIndex; i++) i],
          text: transcript.words
              .sublist(index, endIndex)
              .map((w) => w.text)
              .join(' '),
        ),
      );
      lastProposalEnd = end;
      index = endIndex - 1;
      break;
    }
  }
  return finish();
}

bool _contains(List<String> words, List<String> phrase) {
  for (var i = 0; i + phrase.length <= words.length; i++) {
    var equal = true;
    for (var k = 0; k < phrase.length; k++) {
      if (words[i + k] != phrase[k]) {
        equal = false;
        break;
      }
    }
    if (equal) return true;
  }
  return false;
}

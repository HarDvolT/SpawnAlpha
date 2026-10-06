import '../model/cut_plan.dart';
import '../model/script_document.dart';
import '../review/repeated_sections.dart';
import '../transcription/script_alignment.dart';
import '../transcription/word_timing.dart';
import 'clean_plan.dart';
import 'quiet_evidence.dart';
import 'retake_choice.dart';

CleanPlan withRetakeReview({
  required CleanPlan base,
  required WordTranscript transcript,
  required List<SourceRange> quiet,
  ScriptDocument? snapshot,
  ScriptAlignment? alignment,
  bool screenContext = false,
}) {
  speechOnCleanCut(transcript, base);
  if (base.retakesReviewed) return base;
  final choices = <RetakeChoice>[];
  var previous = Duration.zero;
  for (final range in quiet) {
    if (range.start < previous || range.end > transcript.duration) {
      throw const FormatException('Invalid quiet evidence');
    }
    previous = range.end;
  }
  if (!screenContext &&
      snapshot != null &&
      !snapshot.usesNotes &&
      alignment != null) {
    final protected = protectedCueGaps(snapshot, alignment, transcript);
    protected.sort((a, b) => a.start.compareTo(b.start));
    final owners = {
      for (final (i, word) in transcript.words.indexed)
        word.end.inMicroseconds: i,
    };
    bool touchesRetainedCue(Duration start, Duration end, int first, int last) {
      var lo = 0, hi = protected.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (protected[mid].end <= start) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      for (var i = lo; i < protected.length && protected[i].start < end; i++) {
        final owner = owners[protected[i].start.inMicroseconds];
        if (owner == null || owner < first || owner > last) return true;
      }
      return false;
    }

    for (final section in repeatedSections(
      snapshot,
      transcript,
      alignment: alignment,
    )) {
      final options = <RetakeOption>[];
      for (final attempt in section.attempts) {
        SourceRange? removal;
        if (attempt.uncertain == 0) {
          final first = transcript.words[attempt.firstWord],
              last = transcript.words[attempt.lastWord];
          final lower = attempt.firstWord == 0
              ? Duration.zero
              : transcript.words[attempt.firstWord - 1].end +
                    wordSafetyMargin(transcript.words[attempt.firstWord - 1]);
          final upper = attempt.lastWord + 1 == transcript.words.length
              ? transcript.duration
              : transcript.words[attempt.lastWord + 1].start -
                    wordSafetyMargin(transcript.words[attempt.lastWord + 1]);
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
          if (start != null && end != null && end > start) {
            if (!touchesRetainedCue(
              start,
              end,
              attempt.firstWord,
              attempt.lastWord,
            )) {
              removal = SourceRange(start: start, end: end);
            }
          }
        }
        options.add(
          RetakeOption(
            firstWord: attempt.firstWord,
            lastWord: attempt.lastWord,
            text: attempt.text,
            preview: attempt.range,
            complete: attempt.covered == section.scriptWords,
            removal: removal,
          ),
        );
      }
      choices.add(RetakeChoice(id: section.id, options: options));
    }
  }
  final result = CleanPlan(
    takeId: base.takeId,
    language: base.language,
    sourceDuration: base.sourceDuration,
    changes: base.changes,
    notice: base.notice,
    fillersReviewed: base.fillersReviewed,
    retakesReviewed: true,
    retakes: choices,
  );
  speechOnCleanCut(transcript, result);
  return result;
}

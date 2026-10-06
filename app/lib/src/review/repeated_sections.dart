import '../model/cut_plan.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../model/token.dart';
import '../transcription/script_alignment.dart';
import '../transcription/word_timing.dart';

/// A section found in one anchored attempt, on the untouched source clock.
/// These are comparison facts, not performance grades or removal decisions.
class SectionAttempt {
  const SectionAttempt({
    required this.range,
    required this.text,
    required this.matched,
    required this.changed,
    required this.added,
    required this.covered,
    required this.uncertain,
    required this.firstWord,
    required this.lastWord,
  });
  final SourceRange range;
  final String text;
  final int matched, changed, added, covered, uncertain;
  final int firstWord, lastWord;
}

class RepeatedSection {
  RepeatedSection({
    required this.language,
    required this.scriptText,
    required this.scriptWords,
    required this.id,
    required List<SectionAttempt> attempts,
  }) : attempts = List.unmodifiable(attempts);
  final ScriptLanguage language;
  final String scriptText;
  final String id;
  final int scriptWords;
  final List<SectionAttempt> attempts;
}

/// A backwards jump needs the aligner's exact-word anchor. Normal script
/// repetition, a single echoed word and Notes never become retake comparisons.
/// Partial sections are retained and shown honestly; every spoken word and
/// original time remains intact. Work shares the aligner's bounded cell limit.
List<RepeatedSection> repeatedSections(
  ScriptDocument script,
  WordTranscript transcript, {
  ScriptAlignment? alignment,
}) {
  if (script.usesNotes || transcript.words.isEmpty) return const [];
  alignment ??= alignTranscript(script, transcript);
  if (!identical(alignment.transcript, transcript)) {
    throw const FormatException('Retake alignment mismatch');
  }
  if (alignment.attemptCount < 2) return const [];
  final result = <RepeatedSection>[];
  for (final section in sentenceRanges(script.tokens)) {
    final tokens = script.tokens
        .sublist(section.start, section.end + 1)
        .where((t) => t.isWord)
        .toList();
    if (tokens.isEmpty) continue;
    final groups = <int, List<AlignedWord>>{};
    for (final word in alignment.words) {
      if (word.tokenIndex != null && section.contains(word.tokenIndex!)) {
        (groups[word.attempt] ??= []).add(word);
      }
    }
    if (groups.length < 2) continue;
    final attempts = <SectionAttempt>[];
    for (final mapped in groups.values) {
      var first = mapped.first.spokenIndex, last = mapped.last.spokenIndex;
      // Added wording after a section's final anchor still belongs in what
      // the person hears. Stop at the next mapped word, never duplicate it in
      // an adjacent section or consume the next attempt's anchor.
      while (last + 1 < alignment.words.length &&
          alignment.words[last + 1].attempt == mapped.last.attempt &&
          alignment.words[last + 1].tokenIndex == null) {
        ++last;
      }
      // Initial added speech has no previous section to own it.
      if (mapped.first.attempt == 0 &&
          alignment.words.take(first).every((w) => w.tokenIndex == null)) {
        first = 0;
      }
      final words = transcript.words.sublist(first, last + 1);
      final exact = mapped.where((w) => w.match == WordMatch.exact).length;
      // Require shared anchored substance, not one common word at a boundary.
      if (exact < (tokens.length < 3 ? tokens.length : 3)) continue;
      attempts.add(
        SectionAttempt(
          range: SourceRange(start: words.first.start, end: words.last.end),
          text: words.map((w) => w.text).join(' '),
          matched: exact,
          changed: mapped.where((w) => w.match == WordMatch.changed).length,
          added: words.length - mapped.length,
          covered: mapped.map((w) => w.tokenIndex).toSet().length,
          uncertain: words
              .where((w) => w.confidence == null || w.confidence! < .6)
              .length,
          firstWord: first,
          lastWord: last,
        ),
      );
    }
    if (attempts.length < 2) continue;
    result.add(
      RepeatedSection(
        language: script.language,
        scriptText: script.text.substring(
          script.tokens[section.start].start,
          script.tokens[section.end].end,
        ),
        scriptWords: tokens.length,
        id: 'section-${section.start}-${section.end}',
        attempts: attempts,
      ),
    );
  }
  return List.unmodifiable(result);
}

/// Isolate entry point: only frozen script/word data crosses the boundary.
List<RepeatedSection> repeatedSectionsFromJson(Map<String, Object?> args) =>
    repeatedSections(
      ScriptDocument.fromJson(args['script']! as Map<String, Object?>),
      WordTranscript.fromJson(args['words']! as Map<String, Object?>),
    );

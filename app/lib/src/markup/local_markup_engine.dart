import '../model/coaching_style.dart';
import '../model/mark.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../model/token.dart';
import 'lexicon.dart';
import 'markup_engine.dart';

/// Rule-based markup that runs on the device, offline and free. It reads
/// punctuation, line breaks and word lists for English, French and Arabic,
/// and applies the coaching style's habits. The cloud engine does better;
/// this one keeps the app useful without a network or a subscription.
class LocalMarkupEngine implements MarkupEngine {
  const LocalMarkupEngine();

  @override
  String get name => 'On-device';

  @override
  Future<MarkupResult> markup(ScriptDocument script) async =>
      markupTokens(script.tokens, script.text, script.language, script.style);

  MarkupResult markupTokens(
    List<Token> tokens,
    String text,
    ScriptLanguage language,
    CoachingStyle style,
  ) {
    if (tokens.isEmpty) return const MarkupResult(marks: []);
    final pass = _Pass(tokens, text, Lexicon.of(language), style)..run();
    return MarkupResult(
      marks: normalizeMarks(pass.marks, tokens.length),
      suggestions: pass.suggestions,
    );
  }
}

class _Pass {
  _Pass(this.tokens, this.text, this.lex, this.style) : sentences = sentenceRanges(tokens);

  final List<Token> tokens;
  final String text;
  final Lexicon lex;
  final CoachingStyle style;
  final List<TokenRange> sentences;

  final marks = <Mark>[];
  final suggestions = <Suggestion>[];
  final _gapAfter = <int>{};
  final _stressed = <int>{};

  void run() {
    _pauses();
    _breaths();
    _stress();
    _pace();
    _energy();
    _suggestions();
  }

  // ---- helpers ------------------------------------------------------------

  void _gap(MarkKind kind, int after, String note) {
    if (after >= tokens.length - 1) return;
    _gapAfter.add(after);
    marks.add(Mark.gap(id: newId(), kind: kind, after: after, origin: MarkOrigin.rules, accepted: false, note: note));
  }

  void _span(MarkKind kind, int start, int end, String note) {
    marks.add(Mark(
      id: newId(),
      kind: kind,
      start: start,
      end: end,
      origin: MarkOrigin.rules,
      accepted: false,
      note: note,
    ));
    if (kind == MarkKind.stress) {
      for (var i = start; i <= end; i++) {
        _stressed.add(i);
      }
    }
  }

  int _wordsIn(TokenRange r) {
    var n = 0;
    for (var i = r.start; i <= r.end; i++) {
      if (tokens[i].isWord) n++;
    }
    return n;
  }

  bool _hasNumber(TokenRange r) {
    for (var i = r.start; i <= r.end; i++) {
      if (lex.isNumber(tokens[i])) return true;
    }
    return false;
  }

  bool _hasDigits(TokenRange r) {
    for (var i = r.start; i <= r.end; i++) {
      if (tokens[i].hasDigit) return true;
    }
    return false;
  }

  bool _hasShouted(TokenRange r) {
    for (var i = r.start; i <= r.end; i++) {
      if (tokens[i].isShouted) return true;
    }
    return false;
  }

  bool _isQuestion(TokenRange r) => RegExp(r'[?؟]\W*$').hasMatch(tokens[r.end].text);

  bool _isExclamation(TokenRange r) => RegExp(r'!\W*$').hasMatch(tokens[r.end].text);

  bool _startsStep(TokenRange r) =>
      lex.matchAt(lex.stepMarkers, tokens, r.start) > 0 || RegExp(r'^\d+[.)]$').hasMatch(tokens[r.start].text);

  /// Short social scripts tend to end on a call to action.
  bool _isCallToAction(TokenRange r) {
    for (var i = r.start; i <= r.end; i++) {
      if (lex.matchAt(lex.callToAction, tokens, i) > 0) return true;
    }
    return false;
  }

  // ---- pauses -------------------------------------------------------------

  void _pauses() {
    for (var k = 0; k < sentences.length - 1; k++) {
      final s = sentences[k];
      final next = sentences[k + 1];
      final end = tokens[s.end];
      switch (style) {
        case CoachingStyle.shortSocial:
          if (k == 0) {
            _gap(MarkKind.pauseShort, s.end, 'Let the hook land');
          } else if (end.endsParagraph) {
            _gap(MarkKind.pauseShort, s.end, 'Beat before the next idea');
          } else if (_isQuestion(s) || _isExclamation(s)) {
            _gap(MarkKind.pauseShort, s.end, 'Quick beat for punch');
          } else if (k == sentences.length - 2 && _isCallToAction(next)) {
            _gap(MarkKind.pauseShort, s.end, 'Reset before the call to action');
          }
        case CoachingStyle.presentation:
          if (end.endsParagraph) {
            _gap(MarkKind.pauseLong, s.end, 'New point: give it room');
          } else if (_isQuestion(s)) {
            _gap(MarkKind.pauseLong, s.end, 'Let the question hang');
          } else if (_hasNumber(s) || _hasShouted(s) || _isExclamation(s)) {
            _gap(MarkKind.pauseLong, s.end, 'Let the key point sink in');
          } else {
            _gap(MarkKind.pauseShort, s.end, 'End of sentence');
          }
        case CoachingStyle.tutorial:
          if (_startsStep(next) || end.endsParagraph) {
            _gap(MarkKind.pauseLong, s.end, 'Pause between steps');
          } else {
            _gap(MarkKind.pauseShort, s.end, 'Let it register');
          }
      }
    }

    // A colon inside a sentence sets up what follows.
    for (final t in tokens) {
      if (!t.endsSentence && !t.endsLine && RegExp(r'[:：]$').hasMatch(t.text) && !_gapAfter.contains(t.index)) {
        _gap(MarkKind.pauseShort, t.index, 'Build anticipation');
      }
    }
  }

  // ---- breaths ------------------------------------------------------------

  void _breaths() {
    var sinceRest = 0;
    for (final t in tokens) {
      if (!t.isWord) continue;
      sinceRest++;
      if (_gapAfter.contains(t.index) || t.endsSentence || t.endsLine) {
        sinceRest = 0;
        continue;
      }
      if (sinceRest < style.wordsPerBreath || t.index >= tokens.length - 1) continue;
      final beforeConjunction = lex.matchAt(lex.conjunctions, tokens, t.index + 1) > 0;
      if (t.endsClause || (sinceRest >= style.wordsPerBreath + 6 && beforeConjunction)) {
        _gap(MarkKind.breath, t.index, 'Breathe here');
        sinceRest = 0;
      }
    }
  }

  // ---- stress -------------------------------------------------------------

  void _stress() {
    for (var k = 0; k < sentences.length; k++) {
      final s = sentences[k];
      final words = _wordsIn(s);
      if (words == 0) continue;
      final budget = switch (style) {
        CoachingStyle.shortSocial => (words / 5).ceil().clamp(1, 3),
        _ => (words / 7).ceil().clamp(1, 2),
      };
      var used = 0;

      // Words the writer put in capitals.
      for (var i = s.start; i <= s.end && used < budget; i++) {
        if (tokens[i].isShouted) {
          _span(MarkKind.stress, i, i, 'Written in capitals');
          used++;
        }
      }

      // Numbers, with the word that gives them a unit.
      for (var i = s.start; i <= s.end && used < budget; i++) {
        if (_stressed.contains(i) || !lex.isNumber(tokens[i])) continue;
        var end = i;
        while (end + 1 <= s.end &&
            !tokens[end].endsClause &&
            (lex.isNumber(tokens[end + 1]) ||
                lex.isPercentSign(tokens[end + 1]) ||
                lex.matchAt(lex.units, tokens, end + 1) > 0)) {
          end += lex.matchAt(lex.units, tokens, end + 1).clamp(1, 3);
        }
        end = end.clamp(i, s.end);
        _span(MarkKind.stress, i, end, 'Numbers stick when stressed');
        used++;
        i = end;
      }

      // The action in a tutorial step, the claim in a pitch.
      final lookFor = style == CoachingStyle.tutorial ? lex.actionVerbs : lex.emphasis;
      final note = style == CoachingStyle.tutorial ? 'The action to take' : 'Key word';
      for (var i = s.start; i <= s.end && used < budget; i++) {
        if (_stressed.contains(i) || lex.matchAt(lookFor, tokens, i) == 0) continue;
        _span(MarkKind.stress, i, i, note);
        used++;
        if (style != CoachingStyle.shortSocial) break;
      }

      // Social hooks always get a punch word.
      if (style == CoachingStyle.shortSocial && k == 0 && used == 0) {
        final punch = _longestWord(s);
        if (punch != null) _span(MarkKind.stress, punch, punch, 'Punch the hook');
      }
    }
  }

  int? _longestWord(TokenRange r) {
    int? best;
    var bestLength = 3;
    for (var i = r.start; i <= r.end; i++) {
      final length = tokens[i].bare.length;
      if (tokens[i].isWord && length > bestLength) {
        best = i;
        bestLength = length;
      }
    }
    return best;
  }

  // ---- pace ---------------------------------------------------------------

  void _pace() {
    switch (style) {
      case CoachingStyle.tutorial:
        int? runStart;
        var runEnd = -10;
        for (final t in tokens) {
          if (!_isTechnical(t)) continue;
          if (runStart != null && t.index - runEnd <= 2 && !tokens[runEnd].endsSentence) {
            runEnd = t.index;
            continue;
          }
          if (runStart != null) _span(MarkKind.slower, runStart, runEnd, 'Technical term: slow down');
          runStart = t.index;
          runEnd = t.index;
        }
        if (runStart != null) _span(MarkKind.slower, runStart, runEnd, 'Technical term: slow down');
      case CoachingStyle.presentation:
        // Figures written in digits carry the data; slow down for them.
        for (final s in sentences) {
          if (_hasDigits(s)) _span(MarkKind.slower, s.start, s.end, 'Let the numbers land');
        }
      case CoachingStyle.shortSocial:
        for (var k = 1; k < sentences.length; k++) {
          final s = sentences[k];
          if (_wordsIn(s) >= 16 && !_hasNumber(s)) {
            _span(MarkKind.faster, s.start, s.end, 'Keep the momentum');
          }
        }
    }
  }

  static final _camelCase = RegExp(r'\p{Ll}\p{Lu}', unicode: true);
  static final _innerSymbol = RegExp(r'\w[./\\_@#=<>+]\w');
  static final _mixedDigits = RegExp(r'(?=.*\p{L})(?=.*\p{Nd})', unicode: true);
  static final _acronym = RegExp(r'^[A-Z]{2,6}s?$');
  static final _quoted = RegExp(r'^[`"«“].+[`"»”]$');

  bool _isTechnical(Token t) {
    if (!t.isWord) return false;
    final core = t.text.replaceAll(RegExp(r'^[(\[]+|[)\],.;:!?]+$'), '');
    return _camelCase.hasMatch(core) ||
        _innerSymbol.hasMatch(core) ||
        _mixedDigits.hasMatch(core) ||
        _acronym.hasMatch(core) ||
        _quoted.hasMatch(core) ||
        (lex.language != ScriptLanguage.ar && t.bare.length >= 13);
  }

  // ---- energy -------------------------------------------------------------

  void _energy() {
    final last = sentences.length - 1;
    for (var k = 0; k <= last; k++) {
      final s = sentences[k];
      if (style == CoachingStyle.shortSocial && k == 0) {
        _span(MarkKind.energy, s.start, s.end, 'Open strong');
      } else if (style == CoachingStyle.shortSocial && k == last) {
        _span(MarkKind.energy, s.start, s.end, 'Finish with energy');
      } else if (style == CoachingStyle.presentation && k > 0 && lex.matchAt(lex.conclusion, tokens, s.start) > 0) {
        _span(MarkKind.energy, s.start, s.end, 'Land the conclusion');
      } else if (style == CoachingStyle.presentation && k == last && last > 0) {
        _span(MarkKind.energy, s.start, s.end, 'Close strong');
      } else if (style == CoachingStyle.tutorial && k == 0 && last >= 2) {
        _span(MarkKind.energy, s.start, s.end, 'Warm welcome');
      } else if (_isExclamation(s)) {
        _span(MarkKind.energy, s.start, s.end, 'Exclamation: lift it');
      }
    }
  }

  // ---- suggestions --------------------------------------------------------

  void _suggestions() {
    final hook = sentences.first;
    final hookWords = _wordsIn(hook);
    final hookLimit = style == CoachingStyle.shortSocial ? 14 : 25;
    if (hookWords > hookLimit) {
      suggestions.add(Suggestion(
        id: newId(),
        kind: SuggestionKind.hook,
        start: hook.start,
        end: hook.end,
        original: _textOf(hook.start, hook.end),
        note: 'Your opening line is $hookWords words. Openers under $hookLimit words land better: '
            'lead with the payoff or a question.',
      ));
    }

    for (var i = 0; i < tokens.length && suggestions.length < 8; i++) {
      final phrase = lex.phraseAt(lex.tighteningPhrases, tokens, i);
      if (phrase == null) continue;
      final suggestion = _tighten(i, phrase.length, lex.tightenings[phrase.join(' ')] ?? '');
      if (suggestion != null) suggestions.add(suggestion);
      i += phrase.length - 1;
    }
  }

  static final _trailingPunctuation = RegExp(r'[^\p{L}\p{N}]+$', unicode: true);

  /// Rewrites the [length] tokens from [start] as [replacement]. An empty
  /// replacement removes the phrase and takes the next word along, so a
  /// sentence-opening capital moves onto it.
  Suggestion? _tighten(int start, int length, String replacement) {
    var end = start + length - 1;
    final first = tokens[start];
    final last = tokens[end];
    if (last.endsSentence) return null;
    final capitalized = first.text.isNotEmpty && first.text[0] != first.text[0].toLowerCase();

    String rewrite;
    if (replacement.isEmpty) {
      if (end + 1 >= tokens.length || last.endsLine) return null;
      end++;
      rewrite = tokens[end].text;
    } else {
      final trailing = _trailingPunctuation.firstMatch(last.text)?.group(0) ?? '';
      rewrite = '$replacement$trailing';
    }
    if (capitalized && rewrite.isNotEmpty) rewrite = rewrite[0].toUpperCase() + rewrite.substring(1);

    final original = _textOf(start, end);
    return Suggestion(
      id: newId(),
      kind: SuggestionKind.tighten,
      start: start,
      end: end,
      original: original,
      replacement: rewrite,
      note: replacement.isEmpty
          ? '"${_textOf(start, start + length - 1)}" adds little. Cut it.'
          : 'Say it shorter.',
    );
  }

  String _textOf(int start, int end) => text.substring(tokens[start].start, tokens[end].end);
}

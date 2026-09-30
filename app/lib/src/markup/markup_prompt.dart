import 'dart:convert';

import '../model/coaching_style.dart';
import '../model/mark.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../model/token.dart';
import 'markup_engine.dart';

/// The prompt, the reply schema and the reply parser shared by every
/// language-model engine (Claude, OpenAI-compatible cloud APIs, and local
/// servers such as Ollama and LM Studio).
///
/// The script is sent as numbered words and the model refers to words by
/// number. Every mark also repeats its words, and marks whose words don't
/// match are moved to the nearest match or dropped, so a model that
/// miscounts can't put cues in the wrong place.
abstract final class MarkupPrompt {
  /// The script as `[index]word` pairs, keeping its line breaks.
  static String numberedScript(List<Token> tokens) {
    final out = StringBuffer();
    for (final t in tokens) {
      if (t.index > 0) out.write(t.lineBreaksBefore > 0 ? '\n' * t.lineBreaksBefore : ' ');
      out.write('[${t.index}]${t.text}');
    }
    return out.toString();
  }

  /// The instructions. With [includeSchema] the reply format is spelled
  /// out too, for servers that can't enforce a JSON schema.
  static String system(CoachingStyle style, ScriptLanguage language, {bool includeSchema = false}) {
    final prompt = '''
You are the delivery director for a teleprompter app. A speaker will read the script below aloud on camera, with your cues shown on the prompter. Mark up how to deliver it: where to pause, which words to stress, where to slow down or speed up, where to lift the energy, and where to breathe. You may also suggest a stronger opening or tighter lines.

The script arrives as numbered words, written [index]word. Refer to words only by these indices.

Mark kinds:
- pause_short, pause_long, breath: a gap after one word. Set start and end both to the index of the word the gap follows. Never put a gap after the last word.
- stress: the word to punch, or a short group of up to three words such as a number and its unit.
- slower, faster: a run of words to say slower or faster than the speaker's base pace.
- energy: a run of words to deliver brighter and more animated.
For every mark, "text" repeats the covered words exactly as written, from start to end, and "note" gives the reason in a few words of English.

Coaching style: ${style.label}. Goal: ${style.goal}.
${_styleGuide[style]}

The script is in ${_languageName[language]}. ${_languageGuide[language]}

Keep the marks sparse enough to read at a glance while speaking: about one stress per sentence (two at most), a gap mark at most sentence ends, a breath only where a long stretch has no natural pause, and pace or energy runs only where they change the delivery.

Suggestions:
- hook: when the opening could grab attention faster, rewrite the first sentence once. start and end cover that sentence.
- tighten: up to five lines that can be said in fewer words without losing meaning.
For each suggestion, "original" is the exact text of words start to end, "replacement" is the new text in the script's language and voice, and "note" explains the change in a few words of English. Return an empty list when nothing is worth changing.''';
    if (!includeSchema) return prompt;
    return '$prompt\n\n$_jsonInstruction';
  }

  static const _jsonInstruction = '''
Reply with a single JSON object and nothing else: no prose, no code fences. It has this shape:
{"marks": [{"kind": "pause_short", "start": 12, "end": 12, "text": "word", "note": "why"}],
 "suggestions": [{"kind": "tighten", "start": 3, "end": 7, "original": "exact words", "replacement": "new words", "note": "why"}]}
"kind" is one of pause_short, pause_long, breath, stress, slower, faster, energy for marks, and hook or tighten for suggestions. "start" and "end" are word indices.''';

  static const _styleGuide = {
    CoachingStyle.shortSocial:
        'Open with a strong hook and keep the energy high. Use short, punchy pauses (pause_short, rarely pause_long), '
            'heavy emphasis and a faster pace. Lift the energy on the hook and on the closing call to action.',
    CoachingStyle.presentation:
        'Sound confident and persuasive. Put longer pauses around key points, stress numbers and claims, '
            'and keep a steady pace, slowing down where numbers or the main message need to land.',
    CoachingStyle.tutorial:
        'Be clear and easy to follow. Pause between steps (pause_long), slow down on technical terms, '
            'and stress the action the viewer has to take in each step.',
  };

  static const _languageName = {
    ScriptLanguage.en: 'English',
    ScriptLanguage.fr: 'French',
    ScriptLanguage.ar: 'Arabic',
  };

  static const _languageGuide = {
    ScriptLanguage.en: 'Follow natural English stress and phrasing.',
    ScriptLanguage.fr: 'Follow French phrasing: stress tends to fall at the end of a rhythmic group, '
        'so place stress and pauses by phrase rather than by English habits.',
    ScriptLanguage.ar: 'Follow Arabic phrasing. Words carry attached prefixes such as و and ف; '
        'mark whole words as written. The prompter shows the script right to left.',
  };

  /// The reply format, as a JSON schema that structured-output APIs can
  /// enforce. Every object lists all its properties as required and allows
  /// no others, as strict modes demand.
  static const responseSchema = {
    'type': 'object',
    'properties': {
      'marks': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['pause_short', 'pause_long', 'breath', 'stress', 'slower', 'faster', 'energy'],
            },
            'start': {'type': 'integer'},
            'end': {'type': 'integer'},
            'text': {'type': 'string'},
            'note': {'type': 'string'},
          },
          'required': ['kind', 'start', 'end', 'text', 'note'],
          'additionalProperties': false,
        },
      },
      'suggestions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['hook', 'tighten'],
            },
            'start': {'type': 'integer'},
            'end': {'type': 'integer'},
            'original': {'type': 'string'},
            'replacement': {'type': 'string'},
            'note': {'type': 'string'},
          },
          'required': ['kind', 'start', 'end', 'original', 'replacement', 'note'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['marks', 'suggestions'],
    'additionalProperties': false,
  };

  // ---- reply --------------------------------------------------------------

  /// Pulls the JSON object out of a reply that may carry extra text: the
  /// `<think>` block of a reasoning model, a code fence, or a sentence
  /// before or after the object.
  static String extractJson(String reply) {
    var s = reply.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
    if (fence != null) s = fence.group(1)!.trim();
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    return start >= 0 && end > start ? s.substring(start, end + 1) : s;
  }

  /// Names smaller models use instead of the schema's kinds.
  static const _kindAliases = {
    'pause': MarkKind.pauseShort,
    'short_pause': MarkKind.pauseShort,
    'long_pause': MarkKind.pauseLong,
    'breathe': MarkKind.breath,
    'emphasis': MarkKind.stress,
    'emphasize': MarkKind.stress,
    'slow': MarkKind.slower,
    'slow_down': MarkKind.slower,
    'fast': MarkKind.faster,
    'speed_up': MarkKind.faster,
    'energy_lift': MarkKind.energy,
  };

  static MarkKind? _kind(Object? raw) {
    if (raw is! String) return null;
    final id = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    return MarkKind.fromId(id) ?? _kindAliases[id];
  }

  static int? _int(Object? raw) => switch (raw) {
        int v => v,
        double v when v == v.roundToDouble() => v.toInt(),
        String v => int.tryParse(v.trim()),
        _ => null,
      };

  /// Turns the model's reply into marks and suggestions for [script],
  /// checking every anchor against the words it claims to cover. [source]
  /// names the model in error messages.
  static MarkupResult parseReply(String reply, ScriptDocument script, {String source = 'The model'}) {
    Object? json;
    try {
      json = jsonDecode(extractJson(reply));
    } on FormatException {
      json = null;
    }
    if (json is! Map<String, Object?>) {
      throw MarkupException('$source sent back a reply the app could not read. Try again, or try another model.');
    }
    final tokens = script.tokens;
    final marks = <Mark>[];
    for (final item in json['marks'] is List ? json['marks'] as List : const []) {
      if (item is! Map<String, Object?>) continue;
      final kind = _kind(item['kind']);
      final start = _int(item['start']);
      final end = _int(item['end']) ?? start;
      if (kind == null || start == null || end == null) continue;
      final text = item['text'];
      final range = locateWords(tokens, start, kind.isGap ? start : end, text is String ? text : '');
      if (range == null) continue;
      final note = item['note'];
      marks.add(Mark(
        id: newId(),
        kind: kind,
        start: kind.isGap ? range.end : range.start,
        end: range.end,
        origin: MarkOrigin.ai,
        accepted: false,
        note: note is String && note.trim().isNotEmpty ? note.trim() : null,
      ));
    }

    final suggestions = <Suggestion>[];
    for (final item in json['suggestions'] is List ? json['suggestions'] as List : const []) {
      if (item is! Map<String, Object?>) continue;
      final kind = SuggestionKind.fromId(item['kind'] is String ? (item['kind'] as String).trim().toLowerCase() : null);
      final original = item['original'] is String ? (item['original'] as String).trim() : '';
      final start = _int(item['start']) ?? -1;
      final end = _int(item['end']) ?? -1;
      if (kind == null || original.isEmpty) continue;
      final range = locateText(script, start, end, original);
      if (range == null) continue;
      final replacement = item['replacement'] is String ? (item['replacement'] as String).trim() : '';
      final note = item['note'];
      suggestions.add(Suggestion(
        id: newId(),
        kind: kind,
        start: range.start,
        end: range.end,
        original: script.textOf(range.start, range.end),
        replacement: replacement.isEmpty || replacement == original ? null : replacement,
        note: note is String && note.trim().isNotEmpty ? note.trim() : null,
      ));
    }
    return MarkupResult(marks: normalizeMarks(marks, tokens.length), suggestions: suggestions);
  }

  /// How far from the claimed position to look for the claimed words.
  static const _searchRadius = 6;

  /// Finds the tokens the model meant: [start]..[end] if their words match
  /// [text], else the nearest run of the same length whose words do. With
  /// no usable [text], the indices are trusted if in range.
  static TokenRange? locateWords(List<Token> tokens, int start, int end, String text) {
    final words = [
      for (final w in text.split(RegExp(r'\s+')))
        if (normalizeWord(w) case final n when n.isNotEmpty) n,
    ];
    bool inRange(int s, int e) => s >= 0 && e < tokens.length && s <= e;
    if (words.isEmpty) return inRange(start, end) ? TokenRange(start, end) : null;

    bool matches(int s) {
      if (!inRange(s, s + words.length - 1)) return false;
      for (var k = 0; k < words.length; k++) {
        if (tokens[s + k].bare != words[k]) return false;
      }
      return true;
    }

    for (var offset = 0; offset <= _searchRadius; offset++) {
      for (final s in {start + offset, start - offset}) {
        if (matches(s)) return TokenRange(s, s + words.length - 1);
      }
    }
    return null;
  }

  /// Finds the tokens whose text is exactly [original], preferring the
  /// claimed position.
  static TokenRange? locateText(ScriptDocument script, int start, int end, String original) {
    final tokens = script.tokens;
    if (start >= 0 && end < tokens.length && start <= end && script.textOf(start, end) == original) {
      return TokenRange(start, end);
    }
    final at = script.text.indexOf(original);
    if (at < 0) return null;
    final first = tokens.indexWhere((t) => t.start == at);
    final last = tokens.indexWhere((t) => t.end == at + original.length);
    if (first < 0 || last < first) return null;
    return TokenRange(first, last);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/coaching_style.dart';
import '../model/mark.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../model/token.dart';
import 'markup_engine.dart';

/// Marks up a script with Claude through the Messages API.
///
/// Dart has no official Anthropic SDK, so this speaks raw HTTP. The request
/// streams (a long script can take a while) and uses structured outputs, so
/// the reply is JSON that matches [responseSchema]. The script is sent as
/// numbered words and the model refers to words by number; every mark also
/// repeats its words, and marks whose words don't match are moved to the
/// nearest match or dropped.
class ClaudeMarkupEngine implements MarkupEngine {
  ClaudeMarkupEngine({
    required this.apiKey,
    this.model = defaultModel,
    http.Client? client,
    this.onProgress,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const defaultModel = 'claude-opus-5-5';
  static final endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  /// Models that accept `fallbacks: "default"`, which re-runs a request on
  /// another model if a safety classifier declines a benign script.
  static const _fallbackModels = {
    'claude-fable-5-1',
    'claude-opus-5-5',
    'claude-opus-5',
    'claude-sonnet-5-5',
  };

  final String apiKey;
  final String model;
  final http.Client _client;
  final bool _ownsClient;

  /// Called with the number of characters received so far.
  final void Function(int received)? onProgress;

  @override
  String get name => 'Claude';

  @override
  Future<MarkupResult> markup(ScriptDocument script) async {
    if (script.tokens.isEmpty) return const MarkupResult(marks: []);
    final reply = await _send(buildRequest(script));
    return parseReply(reply, script);
  }

  Map<String, String> get headers => {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        if (_fallbackModels.contains(model)) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      };

  Map<String, Object?> buildRequest(ScriptDocument script) => {
        'model': model,
        'max_tokens': 32000,
        'stream': true,
        if (_fallbackModels.contains(model)) 'fallbacks': 'default',
        'output_config': {
          'effort': 'medium',
          'format': {'type': 'json_schema', 'schema': responseSchema},
        },
        'system': systemPrompt(script.style, script.language),
        'messages': [
          {'role': 'user', 'content': numberedScript(script.tokens)},
        ],
      };

  // ---- transport ----------------------------------------------------------

  Future<String> _send(Map<String, Object?> body) async {
    const maxAttempts = 3;
    for (var attempt = 1;; attempt++) {
      final request = http.Request('POST', endpoint)
        ..headers.addAll(headers)
        ..body = jsonEncode(body);
      final http.StreamedResponse response;
      try {
        response = await _client.send(request).timeout(const Duration(seconds: 60));
      } on TimeoutException {
        throw const MarkupException('Claude did not answer in time. Check your connection and try again.');
      } on http.ClientException catch (e) {
        throw MarkupException('Could not reach Claude: ${e.message}');
      }

      if (response.statusCode == 200) return _readStream(response.stream);

      final errorBody = await response.stream.bytesToString();
      final retryable = response.statusCode == 429 || response.statusCode >= 500;
      if (retryable && attempt < maxAttempts) {
        final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
        await Future<void>.delayed(Duration(seconds: retryAfter ?? attempt * 2));
        continue;
      }
      throw MarkupException(_describeError(response.statusCode, errorBody));
    }
  }

  Future<String> _readStream(Stream<List<int>> bytes) async {
    final text = StringBuffer();
    String? stopReason;
    await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final Object? event;
      try {
        event = jsonDecode(line.substring(5).trim());
      } on FormatException {
        continue;
      }
      if (event is! Map<String, Object?>) continue;
      switch (event['type']) {
        case 'content_block_delta':
          final delta = event['delta'];
          if (delta is Map<String, Object?> && delta['type'] == 'text_delta') {
            text.write(delta['text'] as String? ?? '');
            onProgress?.call(text.length);
          }
        case 'message_delta':
          final delta = event['delta'];
          if (delta is Map<String, Object?>) stopReason = delta['stop_reason'] as String? ?? stopReason;
        case 'error':
          final error = event['error'];
          final message = error is Map<String, Object?> ? error['message'] : null;
          throw MarkupException('Claude stopped with an error: ${message ?? 'unknown error'}');
      }
    }
    switch (stopReason) {
      case 'refusal':
        throw const MarkupException('Claude declined to mark up this script.');
      case 'max_tokens':
        throw const MarkupException('The script is too long to mark up in one go. Try splitting it.');
    }
    return text.toString();
  }

  /// Releases the HTTP client if this engine created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  String _describeError(int status, String body) {
    String? message;
    try {
      final json = jsonDecode(body);
      if (json is Map<String, Object?> && json['error'] is Map<String, Object?>) {
        message = (json['error'] as Map<String, Object?>)['message'] as String?;
      }
    } on FormatException {
      // Not JSON; fall through to the status alone.
    }
    return switch (status) {
      401 => 'Claude rejected the API key. Check it in Settings.',
      403 => 'This API key is not allowed to use $model. ${message ?? ''}'.trim(),
      429 => 'Claude is rate limiting this key. Wait a minute and try again.',
      _ => 'Claude returned an error ($status)${message == null ? '' : ': $message'}',
    };
  }

  // ---- prompt -------------------------------------------------------------

  /// The script as `[index]word` pairs, keeping its line breaks.
  static String numberedScript(List<Token> tokens) {
    final out = StringBuffer();
    for (final t in tokens) {
      if (t.index > 0) out.write(t.lineBreaksBefore > 0 ? '\n' * t.lineBreaksBefore : ' ');
      out.write('[${t.index}]${t.text}');
    }
    return out.toString();
  }

  static String systemPrompt(CoachingStyle style, ScriptLanguage language) => '''
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

  /// Turns the model's JSON into marks and suggestions for [script],
  /// checking every anchor against the words it claims to cover.
  static MarkupResult parseReply(String reply, ScriptDocument script) {
    final Object? json;
    try {
      json = jsonDecode(reply);
    } on FormatException {
      throw const MarkupException('Claude sent back a reply the app could not read. Try again.');
    }
    if (json is! Map<String, Object?>) {
      throw const MarkupException('Claude sent back a reply the app could not read. Try again.');
    }
    final tokens = script.tokens;
    final marks = <Mark>[];
    for (final item in json['marks'] as List<Object?>? ?? const []) {
      if (item is! Map<String, Object?>) continue;
      final kind = MarkKind.fromId(item['kind'] as String?);
      final start = item['start'];
      final end = item['end'];
      if (kind == null || start is! int || end is! int) continue;
      final range = locateWords(tokens, start, kind.isGap ? start : end, item['text'] as String? ?? '');
      if (range == null) continue;
      marks.add(Mark(
        id: newId(),
        kind: kind,
        start: kind.isGap ? range.end : range.start,
        end: range.end,
        origin: MarkOrigin.cloud,
        accepted: false,
        note: item['note'] as String?,
      ));
    }

    final suggestions = <Suggestion>[];
    for (final item in json['suggestions'] as List<Object?>? ?? const []) {
      if (item is! Map<String, Object?>) continue;
      final kind = SuggestionKind.fromId(item['kind'] as String?);
      final original = item['original'] as String? ?? '';
      final start = item['start'];
      final end = item['end'];
      if (kind == null || start is! int || end is! int || original.trim().isEmpty) continue;
      final range = locateText(script, start, end, original.trim());
      if (range == null) continue;
      final replacement = (item['replacement'] as String? ?? '').trim();
      suggestions.add(Suggestion(
        id: newId(),
        kind: kind,
        start: range.start,
        end: range.end,
        original: script.textOf(range.start, range.end),
        replacement: replacement.isEmpty ? null : replacement,
        note: item['note'] as String?,
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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spawnalpha/src/markup/claude_markup_engine.dart';
import 'package:spawnalpha/src/markup/markup_engine.dart';
import 'package:spawnalpha/src/markup/markup_prompt.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';

final script = ScriptDocument.create(
  text: 'We grew forty percent.\nThanks for listening.',
  language: ScriptLanguage.en,
  style: CoachingStyle.presentation,
);

/// A server-sent event stream that delivers [text] in two chunks.
String sse(String text, {String stopReason = 'end_turn'}) {
  final half = text.length ~/ 2;
  String event(Map<String, Object?> data) => 'event: ${data['type']}\ndata: ${jsonEncode(data)}\n\n';
  return [
    event({
      'type': 'message_start',
      'message': {'id': 'msg_1', 'model': 'claude-opus-5-5'},
    }),
    event({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    }),
    for (final part in [text.substring(0, half), text.substring(half)])
      event({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': part},
      }),
    event({'type': 'content_block_stop', 'index': 0}),
    event({
      'type': 'message_delta',
      'delta': {'stop_reason': stopReason},
    }),
    event({'type': 'message_stop'}),
  ].join();
}

MockClient replying(List<http.StreamedResponse Function(http.BaseRequest)> replies, List<http.BaseRequest> seen) {
  var call = 0;
  return MockClient.streaming((request, bodyStream) async {
    seen.add(request);
    return replies[call++](request);
  });
}

http.StreamedResponse ok(String body) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), 200, headers: {'content-type': 'text/event-stream'});

http.StreamedResponse status(int code, [Map<String, String> headers = const {}]) => http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({
        'type': 'error',
        'error': {'type': 'x', 'message': 'nope'},
      }))),
      code,
      headers: headers,
    );

void main() {
  test('numbers the words and keeps line breaks', () {
    expect(
      MarkupPrompt.numberedScript(script.tokens),
      '[0]We [1]grew [2]forty [3]percent.\n[4]Thanks [5]for [6]listening.',
    );
  });

  test('builds a streaming structured-output request', () {
    final engine = ClaudeMarkupEngine(apiKey: 'k');
    final body = engine.buildRequest(script);
    expect(body['model'], 'claude-opus-5-5');
    expect(body['stream'], isTrue);
    expect(body['fallbacks'], 'default');
    final outputConfig = body['output_config'] as Map;
    expect((outputConfig['format'] as Map)['type'], 'json_schema');
    expect(body['system'], contains('Presentation'));
    expect(engine.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    expect(engine.headers['x-api-key'], 'k');
  });

  test('leaves out fallbacks for models that do not take them', () {
    final engine = ClaudeMarkupEngine(apiKey: 'k', model: 'claude-haiku-4-5');
    expect(engine.buildRequest(script).containsKey('fallbacks'), isFalse);
    expect(engine.headers.containsKey('anthropic-beta'), isFalse);
  });

  test('parses marks and suggestions from the stream', () async {
    final reply = jsonEncode({
      'marks': [
        {'kind': 'stress', 'start': 2, 'end': 3, 'text': 'forty percent.', 'note': 'Number'},
        {'kind': 'pause_long', 'start': 3, 'end': 3, 'text': 'percent.', 'note': 'Land it'},
        // Off by one: the words say token 6, so the mark moves there.
        {'kind': 'stress', 'start': 5, 'end': 5, 'text': 'listening', 'note': 'x'},
        // Words that are not in the script: dropped.
        {'kind': 'stress', 'start': 1, 'end': 1, 'text': 'banana', 'note': 'x'},
        // A pause after the last word: dropped.
        {'kind': 'pause_short', 'start': 6, 'end': 6, 'text': 'listening.', 'note': 'x'},
      ],
      'suggestions': [
        {
          'kind': 'tighten',
          'start': 4,
          'end': 6,
          'original': 'Thanks for listening.',
          'replacement': 'Thank you.',
          'note': 'Shorter',
        },
        {'kind': 'hook', 'start': 0, 'end': 3, 'original': 'not in the script', 'replacement': 'x', 'note': 'x'},
      ],
    });
    final seen = <http.BaseRequest>[];
    var progress = 0;
    final engine = ClaudeMarkupEngine(
      apiKey: 'k',
      client: replying([(_) => ok(sse(reply))], seen),
      onProgress: (n) => progress = n,
    );
    final result = await engine.markup(script);

    expect(seen.single.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(progress, reply.length);
    expect(result.marks.map((m) => (m.kind, m.start, m.end)), [
      (MarkKind.stress, 2, 3),
      (MarkKind.pauseLong, 3, 3),
      (MarkKind.stress, 6, 6),
    ]);
    expect(result.marks.every((m) => m.origin == MarkOrigin.ai && !m.accepted), isTrue);
    expect(result.suggestions.single.replacement, 'Thank you.');
    expect(result.suggestions.single.start, 4);
  });

  test('retries when overloaded, then succeeds', () async {
    final seen = <http.BaseRequest>[];
    final engine = ClaudeMarkupEngine(
      apiKey: 'k',
      client: replying([
        (_) => status(529, {'retry-after': '0'}),
        (_) => ok(sse('{"marks":[],"suggestions":[]}')),
      ], seen),
    );
    final result = await engine.markup(script);
    expect(seen, hasLength(2));
    expect(result.marks, isEmpty);
  });

  test('explains a rejected key', () async {
    final engine = ClaudeMarkupEngine(apiKey: 'bad', client: replying([(_) => status(401)], []));
    expect(
      () => engine.markup(script),
      throwsA(isA<MarkupException>().having((e) => e.message, 'message', contains('API key'))),
    );
  });

  test('reports a refusal instead of parsing it', () async {
    final engine = ClaudeMarkupEngine(
      apiKey: 'k',
      client: replying([(_) => ok(sse('', stopReason: 'refusal'))], []),
    );
    expect(
      () => engine.markup(script),
      throwsA(isA<MarkupException>().having((e) => e.message, 'message', contains('declined'))),
    );
  });
}

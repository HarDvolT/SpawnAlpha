import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spawnalpha/src/markup/markup_engine.dart';
import 'package:spawnalpha/src/markup/openai_compatible_engine.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';

final script = ScriptDocument.create(
  text: 'We grew forty percent.\nThanks for listening.',
  language: ScriptLanguage.en,
  style: CoachingStyle.presentation,
);

const reply = '{"marks":[{"kind":"stress","start":2,"end":3,"text":"forty percent.","note":"Number"},'
    '{"kind":"pause_long","start":3,"end":3,"text":"percent.","note":"Land it"}],"suggestions":[]}';

/// An OpenAI-style event stream that delivers [text] in two chunks.
String sse(String text, {String finish = 'stop'}) {
  final half = text.length ~/ 2;
  String chunk(Map<String, Object?> delta, [String? finishReason]) => 'data: ${jsonEncode({
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finishReason},
        ],
      })}\n\n';
  return [
    chunk({'role': 'assistant', 'content': ''}),
    chunk({'content': text.substring(0, half)}),
    chunk({'content': text.substring(half)}),
    chunk({}, finish),
    'data: [DONE]\n\n',
  ].join();
}

http.StreamedResponse respond(int status, String body) => http.StreamedResponse(Stream.value(utf8.encode(body)), status);

OpenAiCompatibleEngine engine(
  List<http.StreamedResponse Function(http.Request)> replies, {
  List<http.Request>? seen,
  String? apiKey,
  bool isLocal = false,
  void Function(int)? onProgress,
}) {
  var call = 0;
  return OpenAiCompatibleEngine(
    name: isLocal ? 'Ollama' : 'OpenAI',
    baseUrl: isLocal ? 'http://localhost:11434/v1/' : 'https://api.example.com/v1',
    model: 'some-model',
    apiKey: apiKey,
    isLocal: isLocal,
    onProgress: onProgress,
    client: MockClient.streaming((request, body) async {
      final r = request as http.Request;
      seen?.add(r);
      return replies[call++](r);
    }),
  );
}

Map<String, Object?> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, Object?>;

void main() {
  test('asks for schema-constrained JSON over a stream, with the key as a bearer token', () async {
    final seen = <http.Request>[];
    var progress = 0;
    final result = await engine(
      [(_) => respond(200, sse(reply))],
      seen: seen,
      apiKey: 'sk-test',
      onProgress: (n) => progress = n,
    ).markup(script);

    final request = seen.single;
    expect(request.url.toString(), 'https://api.example.com/v1/chat/completions');
    expect(request.headers['authorization'], 'Bearer sk-test');
    final body = bodyOf(request);
    expect(body['model'], 'some-model');
    expect(body['stream'], isTrue);
    expect((body['response_format'] as Map)['type'], 'json_schema');
    final messages = body['messages'] as List;
    expect((messages.first as Map)['content'], contains('Reply with a single JSON object'));
    expect((messages.last as Map)['content'], startsWith('[0]We [1]grew'));

    expect(progress, reply.length);
    expect(result.marks.map((m) => (m.kind, m.start, m.end)), [
      (MarkKind.stress, 2, 3),
      (MarkKind.pauseLong, 3, 3),
    ]);
    expect(result.marks.every((m) => m.origin == MarkOrigin.ai), isTrue);
  });

  test('sends no authorization header without a key, and tidies the address', () async {
    final seen = <http.Request>[];
    await engine([(_) => respond(200, sse(reply))], seen: seen, isLocal: true).markup(script);
    expect(seen.single.headers.containsKey('authorization'), isFalse);
    expect(seen.single.url.toString(), 'http://localhost:11434/v1/chat/completions');
  });

  test('steps down to looser reply formats when the server rejects one', () async {
    final seen = <http.Request>[];
    final result = await engine([
      (_) => respond(400, '{"error":{"message":"response_format json_schema not supported"}}'),
      (_) => respond(422, '{"error":"json_object not supported"}'),
      (_) => respond(200, sse('Sure! ```json\n$reply\n```')),
    ], seen: seen).markup(script);
    expect(seen.map((r) => (bodyOf(r)['response_format'] as Map?)?['type']), ['json_schema', 'json_object', null]);
    expect(result.marks, hasLength(2));
  });

  test('reads a plain JSON reply from servers that ignore streaming', () async {
    final body = jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': '<think>Let me count the words.</think>$reply'},
          'finish_reason': 'stop',
        },
      ],
    });
    final result = await engine([(_) => respond(200, body)]).markup(script);
    expect(result.marks, hasLength(2));
  });

  test('explains a reply cut short by a small context window', () async {
    expect(
      () => engine([(_) => respond(200, sse('{"marks": [', finish: 'length'))], isLocal: true).markup(script),
      throwsA(isA<MarkupException>().having((e) => e.message, 'message', contains('context length'))),
    );
  });

  test('says how to fix an unreachable local server', () async {
    final e = OpenAiCompatibleEngine(
      name: 'Ollama',
      baseUrl: 'http://localhost:11434/v1',
      model: 'm',
      isLocal: true,
      client: MockClient((_) async => throw http.ClientException('Connection refused')),
    );
    expect(
      () => e.markup(script),
      throwsA(isA<MarkupException>().having((e) => e.message, 'message', contains('Is it running'))),
    );
  });

  test('explains a rejected key', () async {
    expect(
      () => engine([(_) => respond(401, '{"error":{"message":"Incorrect API key"}}')]).markup(script),
      throwsA(isA<MarkupException>().having((e) => e.message, 'message', contains('rejected the API key'))),
    );
  });

  test('lists models, sorted, without the Gemini prefix', () async {
    final seen = <http.Request>[];
    final models = await engine([
      (_) => respond(200, jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'models/zeta', 'object': 'model'},
              {'id': 'alpha:latest', 'object': 'model'},
            ],
          })),
    ], seen: seen).listModels();
    expect(seen.single.url.path, '/v1/models');
    expect(models, ['alpha:latest', 'zeta']);
  });
}

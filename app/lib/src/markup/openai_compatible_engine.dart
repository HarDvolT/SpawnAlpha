import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/script_document.dart';
import 'markup_engine.dart';
import 'markup_prompt.dart';
import 'remote_http.dart';

/// How strictly the request asks for JSON. Servers differ in what they
/// accept, so the engine steps down this list when one is rejected.
enum ReplyFormat {
  /// `response_format: json_schema`: the server enforces the schema.
  jsonSchema,

  /// `response_format: json_object`: valid JSON, shape from the prompt.
  jsonObject,

  /// No constraint; the prompt asks for JSON and the parser digs it out.
  prompt,
}

/// Marks up a script through an OpenAI-compatible Chat Completions API.
///
/// One engine covers most providers, because they speak the same protocol:
/// OpenAI, Google Gemini (its OpenAI endpoint), Mistral, OpenRouter, Groq,
/// and local servers such as Ollama, LM Studio, llama.cpp and vLLM. The
/// request streams, asks for JSON that matches the schema, and falls back
/// to looser formats when a server rejects the stricter ones.
class OpenAiCompatibleEngine implements RemoteMarkupEngine {
  OpenAiCompatibleEngine({
    required this.name,
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.isLocal = false,
    http.Client? client,
    this.onProgress,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  @override
  final String name;

  /// The API root, such as `https://api.openai.com/v1` or
  /// `http://localhost:11434/v1`.
  final String baseUrl;
  final String model;

  /// Sent as a bearer token when set. Local servers don't need one.
  final String? apiKey;

  /// Local servers can take minutes to load a model, so they get a longer
  /// timeout and a hint about starting the server when unreachable.
  final bool isLocal;

  final http.Client _client;
  final bool _ownsClient;

  /// Called with the number of characters received so far.
  final void Function(int received)? onProgress;

  Uri _uri(String path) => Uri.parse('${baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/$path');

  Map<String, String> get headers => {
        'content-type': 'application/json',
        if ((apiKey ?? '').isNotEmpty) 'authorization': 'Bearer $apiKey',
      };

  String get _unreachable => isLocal
      ? 'Could not reach $name at $baseUrl. Is it running with a model loaded? '
          'On a phone, use your computer\'s network address instead of localhost.'
      : 'Could not reach $name. Check your connection and the server address.';

  Map<String, Object?> buildRequest(ScriptDocument script, ReplyFormat format) => {
        'model': model,
        'stream': true,
        'messages': [
          {
            'role': 'system',
            'content': MarkupPrompt.system(script.style, script.language, includeSchema: true),
          },
          {'role': 'user', 'content': MarkupPrompt.numberedScript(script.tokens)},
        ],
        if (format == ReplyFormat.jsonSchema)
          'response_format': {
            'type': 'json_schema',
            'json_schema': {'name': 'delivery_markup', 'strict': true, 'schema': MarkupPrompt.responseSchema},
          },
        if (format == ReplyFormat.jsonObject) 'response_format': {'type': 'json_object'},
      };

  @override
  Future<MarkupResult> markup(ScriptDocument script) async {
    if (script.tokens.isEmpty) return const MarkupResult(marks: []);
    for (final format in ReplyFormat.values) {
      final body = jsonEncode(buildRequest(script, format));
      final http.StreamedResponse response;
      try {
        response = await sendWithRetry(
          _client,
          () => http.Request('POST', _uri('chat/completions'))
            ..headers.addAll(headers)
            ..body = body,
          timeout: isLocal ? const Duration(minutes: 5) : const Duration(seconds: 90),
          unreachable: _unreachable,
        );
      } on HttpFailure catch (e) {
        // A 400 or 422 often means "this server can't do that
        // response_format"; try a looser one before giving up.
        final formatProblem = e.status == 400 || e.status == 422;
        if (formatProblem && format != ReplyFormat.prompt) continue;
        throw MarkupException(_describe(e));
      }
      return MarkupPrompt.parseReply(await _readReply(response.stream), script, source: name);
    }
    throw StateError('unreachable');
  }

  /// Reads a streamed reply, or a plain JSON one from servers that ignore
  /// `stream`.
  Future<String> _readReply(Stream<List<int>> bytes) async {
    final text = StringBuffer();
    final raw = StringBuffer();
    var streamed = false;
    String? finish;
    await for (final line in bodyLines(bytes)) {
      if (line.startsWith('data:')) streamed = true;
      if (!streamed) {
        raw.writeln(line);
        continue;
      }
      final event = sseJson(line);
      if (event == null) continue;
      _throwIfError(event);
      final choices = event['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) continue;
      final choice = choices.first as Map;
      final delta = choice['delta'];
      if (delta is Map && delta['content'] is String) {
        text.write(delta['content']);
        onProgress?.call(text.length);
      }
      if (choice['finish_reason'] is String) finish = choice['finish_reason'] as String;
    }

    if (!streamed) {
      Object? json;
      try {
        json = jsonDecode(raw.toString());
      } on FormatException {
        throw MarkupException('$name sent back a reply the app could not read.');
      }
      if (json is Map<String, Object?>) {
        _throwIfError(json);
        final choices = json['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final choice = choices.first as Map;
          final message = choice['message'];
          if (message is Map && message['content'] is String) text.write(message['content']);
          finish = choice['finish_reason'] as String?;
        }
      }
    }

    if (finish == 'length') {
      throw MarkupException(
        '$name ran out of room before finishing. Try a shorter script'
        '${isLocal ? ', or raise the context length in $name' : ''}.',
      );
    }
    if (finish == 'content_filter') throw MarkupException('$name declined to mark up this script.');
    return text.toString();
  }

  void _throwIfError(Map<String, Object?> json) {
    final error = json['error'];
    if (error == null) return;
    final message = error is Map ? error['message'] : error;
    throw MarkupException('$name stopped with an error: ${message ?? 'unknown error'}');
  }

  @override
  Future<List<String>> listModels() async {
    try {
      final response = await sendWithRetry(
        _client,
        () => http.Request('GET', _uri('models'))..headers.addAll(headers),
        timeout: const Duration(seconds: 30),
        unreachable: _unreachable,
      );
      final json = jsonDecode(await response.stream.bytesToString());
      final data = json is Map<String, Object?> ? json['data'] : null;
      final ids = [
        for (final m in data is List ? data : const [])
          if (m is Map && m['id'] is String)
            // Gemini lists "models/gemini-…" but takes the bare id.
            (m['id'] as String).replaceFirst(RegExp('^models/'), ''),
      ]..sort();
      return ids;
    } on HttpFailure catch (e) {
      throw MarkupException(_describe(e));
    } on FormatException {
      throw MarkupException('$name sent back a model list the app could not read.');
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }

  String _describe(HttpFailure e) {
    final message = e.apiMessage;
    return switch (e.status) {
      401 || 403 => '$name rejected the API key${message == null ? '' : ': $message'}. Check it in Settings.',
      404 => '$name could not find the model "$model" or the address $baseUrl. '
          'Check both in Settings.',
      429 => '$name is rate limiting this key. Wait a minute and try again.',
      _ => '$name returned an error (${e.status})${message == null ? '' : ': $message'}',
    };
  }
}

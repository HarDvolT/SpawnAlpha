import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/script_document.dart';
import 'markup_engine.dart';
import 'markup_prompt.dart';
import 'remote_http.dart';

/// Marks up a script with Claude through the Anthropic Messages API.
///
/// Dart has no official Anthropic SDK, so this speaks raw HTTP. The request
/// streams (a long script can take a while) and uses structured outputs, so
/// the reply is JSON that matches [MarkupPrompt.responseSchema].
class ClaudeMarkupEngine implements RemoteMarkupEngine {
  ClaudeMarkupEngine({
    required this.apiKey,
    this.model = defaultModel,
    this.baseUrl = defaultBaseUrl,
    http.Client? client,
    this.onProgress,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const defaultModel = 'claude-opus-5-5';
  static const defaultBaseUrl = 'https://api.anthropic.com/v1';

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
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  /// Called with the number of characters received so far.
  final void Function(int received)? onProgress;

  @override
  String get name => 'Claude';

  Uri _uri(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/$path');

  bool get _usesFallbacks => _fallbackModels.contains(model);

  Map<String, String> get headers => {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        if (_usesFallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      };

  Map<String, Object?> buildRequest(ScriptDocument script) => {
        'model': model,
        'max_tokens': 32000,
        'stream': true,
        if (_usesFallbacks) 'fallbacks': 'default',
        'output_config': {
          'effort': 'medium',
          'format': {'type': 'json_schema', 'schema': MarkupPrompt.responseSchema},
        },
        'system': MarkupPrompt.system(script.style, script.language),
        'messages': [
          {'role': 'user', 'content': MarkupPrompt.numberedScript(script.tokens)},
        ],
      };

  @override
  Future<MarkupResult> markup(ScriptDocument script) async {
    if (script.tokens.isEmpty) return const MarkupResult(marks: []);
    final body = jsonEncode(buildRequest(script));
    final http.StreamedResponse response;
    try {
      response = await sendWithRetry(
        _client,
        () => http.Request('POST', _uri('messages'))
          ..headers.addAll(headers)
          ..body = body,
        timeout: const Duration(seconds: 90),
        unreachable: 'Could not reach Claude. Check your connection and try again.',
      );
    } on HttpFailure catch (e) {
      throw MarkupException(_describe(e));
    }
    return MarkupPrompt.parseReply(await _readStream(response.stream), script, source: name);
  }

  Future<String> _readStream(Stream<List<int>> bytes) async {
    final text = StringBuffer();
    String? stopReason;
    await for (final line in bodyLines(bytes)) {
      final event = sseJson(line);
      if (event == null) continue;
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

  @override
  Future<List<String>> listModels() async {
    try {
      final response = await sendWithRetry(
        _client,
        () => http.Request('GET', _uri('models?limit=100'))..headers.addAll(headers),
        timeout: const Duration(seconds: 30),
        unreachable: 'Could not reach Claude. Check your connection.',
      );
      final json = jsonDecode(await response.stream.bytesToString());
      final data = json is Map<String, Object?> ? json['data'] : null;
      return [
        for (final m in data is List ? data : const [])
          if (m is Map && m['id'] is String) m['id'] as String,
      ];
    } on HttpFailure catch (e) {
      throw MarkupException(_describe(e));
    } on FormatException {
      throw const MarkupException('Claude sent back a model list the app could not read.');
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }

  String _describe(HttpFailure e) {
    final message = e.apiMessage;
    return switch (e.status) {
      401 => 'Claude rejected the API key. Check it in Settings.',
      403 => 'This API key is not allowed to use $model. ${message ?? ''}'.trim(),
      404 => 'Claude does not know the model "$model". Pick one from the list in Settings.',
      429 => 'Claude is rate limiting this key. Wait a minute and try again.',
      _ => 'Claude returned an error (${e.status})${message == null ? '' : ': $message'}',
    };
  }
}

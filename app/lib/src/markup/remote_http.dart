import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'markup_engine.dart';

/// A non-success HTTP reply, after retries.
class HttpFailure implements Exception {
  const HttpFailure(this.status, this.body);

  final int status;
  final String body;

  /// The server's own error message, from the shapes the supported APIs
  /// use: `{"error": {"message": ...}}` (Anthropic, OpenAI and most
  /// compatible servers), `{"error": "..."}` (Ollama), `{"message": ...}`,
  /// or a list holding one of these (Gemini).
  String? get apiMessage {
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      final text = body.trim();
      return text.isEmpty || text.length > 300 ? null : text;
    }
    if (json is List && json.isNotEmpty) json = json.first;
    if (json is! Map) return null;
    final error = json['error'];
    if (error is Map && error['message'] is String) return error['message'] as String;
    if (error is String) return error;
    if (json['message'] is String) return json['message'] as String;
    return null;
  }

  @override
  String toString() => 'HTTP $status${apiMessage == null ? '' : ': $apiMessage'}';
}

/// Sends a request built by [build], retrying rate limits and server errors
/// twice (honouring `retry-after`), and returns the successful response
/// with its body still streaming.
///
/// Network failures and timeouts become [MarkupException]s with
/// [unreachable] as the message. Other failures throw [HttpFailure] for
/// the caller to explain.
Future<http.StreamedResponse> sendWithRetry(
  http.Client client,
  http.BaseRequest Function() build, {
  required Duration timeout,
  required String unreachable,
  int attempts = 3,
}) async {
  for (var attempt = 1;; attempt++) {
    final http.StreamedResponse response;
    try {
      response = await client.send(build()).timeout(timeout);
    } on TimeoutException {
      throw MarkupException('$unreachable (no answer after ${timeout.inSeconds} seconds)');
    } on http.ClientException catch (e) {
      throw MarkupException('$unreachable (${e.message})');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return response;

    final body = await response.stream.bytesToString();
    final retryable = response.statusCode == 429 || response.statusCode >= 500;
    if (retryable && attempt < attempts) {
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
      await Future<void>.delayed(Duration(seconds: retryAfter ?? attempt * 2));
      continue;
    }
    throw HttpFailure(response.statusCode, body);
  }
}

/// The lines of a response body, decoded.
Stream<String> bodyLines(Stream<List<int>> bytes) => bytes.transform(utf8.decoder).transform(const LineSplitter());

/// The JSON payload of a server-sent event line (`data: {...}`), or null
/// for other lines, keep-alives and the `[DONE]` marker.
Map<String, Object?>? sseJson(String line) {
  if (!line.startsWith('data:')) return null;
  final data = line.substring(5).trim();
  if (data.isEmpty || data == '[DONE]') return null;
  try {
    final json = jsonDecode(data);
    return json is Map<String, Object?> ? json : null;
  } on FormatException {
    return null;
  }
}

// Reads only the explicit generated fixture output, never an owner recording.
import 'dart:convert';
import 'dart:io';

import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/transcription/script_alignment.dart';
import 'package:spawnalpha/src/transcription/speech_pieces.dart';

void main(List<String> args) {
  if (args.length != 1 ||
      !RegExp(r'^check-[a-f0-9-]+$').hasMatch(args.single)) {
    throw const FormatException('A generated fixture ID is required');
  }
  final file = File('build/asr/${args.single}-pieces.json');
  if (file.lengthSync() > 4000000) {
    throw const FormatException('Fixture is too large');
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final transcript = transcriptFromPieces(
    language: ScriptLanguage.en,
    duration: Duration(microseconds: data['durationUs']! as int),
    pieces: [
      for (final row in data['pieces']! as List)
        SpeechPiece(
          bytes: (row['bytes'] as List).cast<int>(),
          start: Duration(microseconds: row['startUs'] as int),
          end: Duration(microseconds: row['endUs'] as int),
          probability: (row['probability'] as num).toDouble(),
        ),
    ],
  );
  final script = ScriptDocument.create(
    text:
        'We launch today. '
        'This is a local speech timing test. We launch today.',
  );
  final result = alignTranscript(script, transcript);
  if (result.missedTokens.isNotEmpty ||
      result.words.any((word) => word.match != WordMatch.exact) ||
      result.words.length != script.wordCount ||
      result.attemptCount != 1) {
    throw StateError('Generated end-to-end timing check failed');
  }
  stdout.writeln(
    'Generated AAC speech → UTF-8 words → script alignment passed; no text logged',
  );
}

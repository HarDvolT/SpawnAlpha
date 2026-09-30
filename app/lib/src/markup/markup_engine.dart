import '../model/mark.dart';
import '../model/script_document.dart';

/// What a markup engine returns: proposed marks and rewrite suggestions,
/// all unaccepted until the user reviews them.
class MarkupResult {
  const MarkupResult({required this.marks, this.suggestions = const []});

  final List<Mark> marks;
  final List<Suggestion> suggestions;
}

/// Something that marks up a script for delivery.
abstract interface class MarkupEngine {
  /// Shown in the editor, e.g. "On-device" or "Claude".
  String get name;

  Future<MarkupResult> markup(ScriptDocument script);
}

/// A markup failure with a message fit to show the user.
class MarkupException implements Exception {
  const MarkupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Replaces the script's proposed marks with [result], keeping the marks
/// the user accepted or added.
ScriptDocument applyMarkup(ScriptDocument script, MarkupResult result) {
  final kept = script.marks.where((m) => m.accepted || m.origin == MarkOrigin.user);
  return script.copyWith(
    // normalizeMarks lets accepted marks win where a proposal collides.
    marks: normalizeMarks([...kept, ...result.marks], script.tokens.length),
    suggestions: result.suggestions,
  );
}

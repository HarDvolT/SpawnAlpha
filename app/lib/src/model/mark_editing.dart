import 'mark.dart';
import 'script_document.dart';
import 'token.dart';

/// Edits the editor makes to a script's marks. Each returns a new script
/// with normalized marks.
extension MarkEditing on ScriptDocument {
  ScriptDocument _withMarks(List<Mark> marks) => copyWith(marks: normalizeMarks(marks, tokens.length));

  /// The marks on or right after [token]: spans that cover it and the gap
  /// mark that follows it.
  List<Mark> marksAt(int token) =>
      [for (final m in marks) if (m.kind.isGap ? m.end == token : m.covers(token)) m];

  ScriptDocument acceptMark(String id) =>
      _withMarks([for (final m in marks) m.id == id ? m.copyWith(accepted: true) : m]);

  ScriptDocument removeMark(String id) => _withMarks([for (final m in marks) if (m.id != id) m]);

  /// Switches a mark to another kind in the same place. The user has now
  /// reviewed it, so it counts as accepted.
  ScriptDocument changeMarkKind(String id, MarkKind kind) =>
      _withMarks([for (final m in marks) m.id == id ? m.copyWith(kind: kind, accepted: true) : m]);

  ScriptDocument acceptAllMarks() => _withMarks([for (final m in marks) m.copyWith(accepted: true)]);

  ScriptDocument discardPendingMarks() => _withMarks([for (final m in marks) if (m.accepted) m]);

  /// Whether a mark of [kind] can go at [token]: gap marks need a word
  /// after them.
  bool canAddMark(MarkKind kind, int token) =>
      token >= 0 && token < tokens.length && (!kind.isGap || token < tokens.length - 1);

  /// Adds a user mark at [token]. Gap marks go after the word, stress goes
  /// on it, and pace and energy runs cover its sentence. The new mark
  /// replaces marks of the same family in its place.
  ScriptDocument addMark(MarkKind kind, int token) {
    if (!canAddMark(kind, token)) return this;
    final range = switch (kind) {
      MarkKind.slower || MarkKind.faster || MarkKind.energy => sentenceAt(tokens, token),
      _ => TokenRange(token, token),
    };
    final added = Mark(id: newId(), kind: kind, start: range.start, end: range.end);
    final replaced = kind.isGap
        ? (Mark m) => m.kind.isGap && m.end == token
        : (Mark m) => m.kind.family == kind.family && m.start <= range.end && m.end >= range.start;
    return _withMarks([added, for (final m in marks) if (!replaced(m)) m]);
  }
}

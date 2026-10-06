import 'coaching_style.dart';
import 'mark.dart';
import 'mark_remapper.dart';
import 'note_deck.dart';
import 'script_language.dart';
import 'token.dart';

/// What a suggestion from the markup is about.
enum SuggestionKind {
  /// A stronger opening line.
  hook('hook', 'Stronger hook'),

  /// A shorter way to say the same thing.
  tighten('tighten', 'Tighter line');

  const SuggestionKind(this.id, this.label);

  final String id;
  final String label;

  static SuggestionKind? fromId(String? id) {
    for (final k in SuggestionKind.values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// A proposed rewrite of tokens [start]..[end]. A suggestion without a
/// [replacement] is advice only.
class Suggestion {
  const Suggestion({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.original,
    this.replacement,
    this.note,
  });

  final String id;
  final SuggestionKind kind;
  final int start;
  final int end;

  /// The script text the suggestion was made against, so a stale
  /// suggestion can be detected after edits.
  final String original;
  final String? replacement;
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.id,
    'start': start,
    'end': end,
    'original': original,
    if (replacement != null) 'replacement': replacement,
    if (note != null) 'note': note,
  };

  static Suggestion? fromJson(Map<String, Object?> json) {
    final kind = SuggestionKind.fromId(json['kind'] as String?);
    final start = json['start'];
    final end = json['end'];
    if (kind == null || start is! int || end is! int || start < 0 || end < start) {
      return null;
    }
    return Suggestion(
      id: json['id'] as String? ?? newId(),
      kind: kind,
      start: start,
      end: end,
      original: json['original'] as String? ?? '',
      replacement: json['replacement'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// A recording made from a script.
enum TakeMode { camera, screen, both }

enum RecordingAid { script, notes }

class Take {
  const Take({
    required this.path,
    required this.recordedAt,
    required this.duration,
    this.mode = TakeMode.camera,
    this.cameraPath,
    this.metadataPath,
    this.activityPath,
    this.wordsPath,
    this.cutPath,
    this.recovered = false,
  });

  final String path;
  final DateTime recordedAt;
  final Duration duration;
  final TakeMode mode;
  final String? cameraPath, metadataPath, activityPath, wordsPath, cutPath;
  Take withWords(String path) => Take(path: this.path, recordedAt: recordedAt, duration: duration,
    mode: mode, cameraPath: cameraPath, metadataPath: metadataPath, activityPath: activityPath,
    recovered: recovered, wordsPath: path);
  Take withCut(String path) => Take(path: this.path, recordedAt: recordedAt, duration: duration,
    mode: mode, cameraPath: cameraPath, metadataPath: metadataPath, activityPath: activityPath,
    recovered: recovered, wordsPath: wordsPath, cutPath: path);
  final bool recovered;

  Map<String, Object?> toJson() => {
    'path': path,
    'recordedAt': recordedAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'durationUs': duration.inMicroseconds,
    'mode': mode.name,
    'cameraPath': ?cameraPath,
    'metadataPath': ?metadataPath,
    'activityPath': ?activityPath,
    'wordsPath': ?wordsPath,
    'cutPath': ?cutPath,
    if (recovered) 'recovered': true,
  };

  static Take? fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final at = DateTime.tryParse(json['recordedAt'] as String? ?? '');
    if (path is! String || at == null) return null;
    final precise = json['durationUs'];
    if (precise != null && (precise is! int || precise < 0 || precise > 1 << 53)) return null;
    return Take(
      path: path,
      recordedAt: at,
      duration: precise is int ? Duration(microseconds: precise) : Duration(milliseconds: json['durationMs'] as int? ?? 0),
      mode: TakeMode.values.where((v) => v.name == json['mode']).firstOrNull ?? TakeMode.camera,
      cameraPath: json['cameraPath'] as String?,
      metadataPath: json['metadataPath'] as String?,
      activityPath: json['activityPath'] as String?,
      wordsPath: json['wordsPath'] as String?,
      cutPath: json['cutPath'] as String?,
      recovered: json['recovered'] == true,
    );
  }
}

/// A script with its delivery marks. Immutable; edits return a copy.
class ScriptDocument {
  ScriptDocument({
    required this.id,
    required this.title,
    required this.text,
    required this.language,
    required this.style,
    this.marks = const [],
    this.suggestions = const [],
    this.takes = const [],
    this.recordingAid = RecordingAid.script,
    NoteDeck? notes,
    DateTime? updatedAt,
  }) : notes = notes ?? NoteDeck(const []),
       updatedAt = updatedAt ?? DateTime.now();

  factory ScriptDocument.create({
    String title = '',
    String text = '',
    ScriptLanguage language = ScriptLanguage.en,
    CoachingStyle style = CoachingStyle.presentation,
    RecordingAid recordingAid = RecordingAid.script,
  }) => ScriptDocument(
    id: newId(),
    title: title,
    text: text,
    language: language,
    style: style,
    recordingAid: recordingAid,
  );

  final String id;
  final String title;
  final String text;
  final ScriptLanguage language;
  final CoachingStyle style;
  final List<Mark> marks;
  final List<Suggestion> suggestions;
  final List<Take> takes;
  final RecordingAid recordingAid;
  final NoteDeck notes;
  bool get usesNotes => recordingAid == RecordingAid.notes;
  bool get stageReady => usesNotes ? notes.ready : wordCount > 0;
  String get contentSummary => usesNotes ? '${notes.cards.length} cards' : '$wordCount words';
  final DateTime updatedAt;

  late final List<Token> tokens = tokenize(text);

  late final int wordCount = tokens.where((t) => t.isWord).length;

  /// Marks the user has not reviewed yet.
  int get pendingCount => marks.where((m) => !m.accepted).length;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = usesNotes ? (notes.cards.firstOrNull?.title.trim() ?? '') : text.trim().split('\n').first;
    if (firstLine.isEmpty) {
      return usesNotes ? 'Untitled notes' : 'Untitled script';
    }
    return firstLine.length > 40 ? '${firstLine.substring(0, 40)}…' : firstLine;
  }

  /// The script text covered by tokens [start]..[end].
  String textOf(int start, int end) => text.substring(tokens[start].start, tokens[end].end);

  ScriptDocument copyWith({
    String? title,
    ScriptLanguage? language,
    CoachingStyle? style,
    List<Mark>? marks,
    List<Suggestion>? suggestions,
    List<Take>? takes,
    RecordingAid? recordingAid,
    NoteDeck? notes,
  }) => ScriptDocument(
    id: id,
    title: title ?? this.title,
    text: text,
    language: language ?? this.language,
    style: style ?? this.style,
    marks: marks ?? this.marks,
    suggestions: suggestions ?? this.suggestions,
    takes: takes ?? this.takes,
    recordingAid: recordingAid ?? this.recordingAid,
    notes: notes ?? this.notes,
  );

  /// Replaces the text and moves every mark and suggestion to follow the
  /// words it was attached to. Marks on removed words are dropped.
  ScriptDocument withText(String newText) {
    if (newText == text) return this;
    final newTokens = tokenize(newText);
    final map = alignTokens(tokens, newTokens);
    return ScriptDocument(
      id: id,
      title: title,
      text: newText,
      language: language,
      style: style,
      marks: normalizeMarks(remapMarks(marks, map), newTokens.length),
      suggestions: [for (final s in suggestions) ?_remapSuggestion(s, map, newText, newTokens)],
      takes: takes,
      recordingAid: recordingAid,
      notes: notes,
    );
  }

  Suggestion? _remapSuggestion(Suggestion s, List<int?> map, String newText, List<Token> newTokens) {
    if (s.end >= map.length) return null;
    final start = map[s.start];
    final end = map[s.end];
    if (start == null || end == null || end < start) return null;
    final covered = newText.substring(newTokens[start].start, newTokens[end].end);
    if (covered != s.original) return null;
    return Suggestion(
      id: s.id,
      kind: s.kind,
      start: start,
      end: end,
      original: s.original,
      replacement: s.replacement,
      note: s.note,
    );
  }

  /// Applies [suggestion]'s rewrite and removes it from the list.
  ScriptDocument applySuggestion(Suggestion suggestion) {
    final replacement = suggestion.replacement;
    if (replacement == null || suggestion.end >= tokens.length) {
      return dismissSuggestion(suggestion);
    }
    final from = tokens[suggestion.start].start;
    final to = tokens[suggestion.end].end;
    if (text.substring(from, to) != suggestion.original) {
      return dismissSuggestion(suggestion);
    }
    final newText = text.replaceRange(from, to, replacement);
    return dismissSuggestion(suggestion).withText(newText);
  }

  ScriptDocument dismissSuggestion(Suggestion suggestion) => copyWith(
    suggestions: [
      for (final s in suggestions)
        if (s.id != suggestion.id) s,
    ],
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'title': title,
    'text': text,
    'language': language.name,
    'style': style.name,
    'recordingAid': recordingAid.name,
    if (notes.cards.isNotEmpty) 'notes': notes.toJson(),
    'marks': [for (final m in marks) m.toJson()],
    'suggestions': [for (final s in suggestions) s.toJson()],
    'takes': [for (final t in takes) t.toJson()],
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ScriptDocument.fromJson(Map<String, Object?> json) {
    List<T> listOf<T>(String key, T? Function(Map<String, Object?>) parse) => [
      for (final item in (json[key] as List<Object?>? ?? const []))
        if (item is Map<String, Object?>) ?parse(item),
    ];

    final text = json['text'] as String? ?? '';
    final tokenCount = tokenize(text).length;
    return ScriptDocument(
      id: json['id'] as String? ?? newId(),
      title: json['title'] as String? ?? '',
      text: text,
      language: ScriptLanguage.fromName(json['language'] as String?),
      style: CoachingStyle.fromName(json['style'] as String?),
      recordingAid: json['recordingAid'] == 'notes' ? RecordingAid.notes : RecordingAid.script,
      notes: json['notes'] is Map<String, Object?> ? NoteDeck.fromJson(json['notes']! as Map<String, Object?>) : null,
      marks: normalizeMarks(listOf('marks', Mark.fromJson), tokenCount),
      suggestions: listOf('suggestions', Suggestion.fromJson),
      takes: listOf('takes', Take.fromJson),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

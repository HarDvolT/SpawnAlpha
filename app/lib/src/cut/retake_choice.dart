import '../model/cut_plan.dart';

SourceRange _range(Object? value) {
  if (value is! Map || value['startUs'] is! int || value['endUs'] is! int) {
    throw const FormatException('Invalid retake range');
  }
  try {
    return SourceRange(
      start: Duration(microseconds: value['startUs'] as int),
      end: Duration(microseconds: value['endUs'] as int),
    );
  } on ArgumentError {
    throw const FormatException('Invalid retake range');
  }
}

class RetakeOption {
  RetakeOption({
    required this.firstWord,
    required this.lastWord,
    required this.text,
    required this.preview,
    required this.complete,
    this.removal,
  }) {
    if (firstWord < 0 ||
        lastWord < firstWord ||
        lastWord >= 100000 ||
        text.isEmpty ||
        text.length > 4 * 1024 * 1024 ||
        (removal != null &&
            (removal!.start > preview.start || removal!.end < preview.end))) {
      throw const FormatException('Invalid retake option');
    }
  }
  final int firstWord, lastWord;
  final String text;
  final SourceRange preview;
  final SourceRange? removal;
  final bool complete;
  Map<String, Object?> toJson() => {
    'firstWord': firstWord,
    'lastWord': lastWord,
    'text': text,
    'preview': preview.toJson(),
    'complete': complete,
    'removal': ?removal?.toJson(),
  };
  factory RetakeOption.fromJson(Object? value) {
    if (value is! Map ||
        value['firstWord'] is! int ||
        value['lastWord'] is! int ||
        value['text'] is! String ||
        value['complete'] is! bool) {
      throw const FormatException('Invalid retake option');
    }
    return RetakeOption(
      firstWord: value['firstWord'] as int,
      lastWord: value['lastWord'] as int,
      text: value['text'] as String,
      preview: _range(value['preview']),
      complete: value['complete'] as bool,
      removal: value['removal'] == null ? null : _range(value['removal']),
    );
  }
}

/// Null selection keeps every attempt. Exactly one complete alternative may be
/// selected, only when every discarded alternative has a safe removal range.
class RetakeChoice {
  RetakeChoice({
    required this.id,
    required List<RetakeOption> options,
    this.selected,
  }) : options = List.unmodifiable(options) {
    if (!RegExp(r'^section-[0-9]+-[0-9]+$').hasMatch(id) ||
        id.length > 128 ||
        options.length < 2 ||
        options.length > 10000 ||
        (selected != null && !canSelect(selected!))) {
      throw const FormatException('Invalid retake choice');
    }
    for (var i = 1; i < options.length; i++) {
      if (options[i].firstWord <= options[i - 1].lastWord ||
          options[i].preview.start < options[i - 1].preview.end) {
        throw const FormatException('Overlapping retake options');
      }
    }
  }
  final String id;
  final List<RetakeOption> options;
  final int? selected;
  bool canSelect(int index) =>
      index >= 0 &&
      index < options.length &&
      options[index].complete &&
      options.indexed.every(
        (item) => item.$1 == index || item.$2.removal != null,
      );
  RetakeChoice withSelected(int? index) =>
      RetakeChoice(id: id, options: options, selected: index);
  Iterable<RetakeOption> get discarded => selected == null
      ? const []
      : options.indexed
            .where((item) => item.$1 != selected)
            .map((item) => item.$2);
  Map<String, Object?> toJson() => {
    'id': id,
    'options': options.map((o) => o.toJson()).toList(),
    'selected': ?selected,
  };
  factory RetakeChoice.fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['options'] is! List ||
        (value['options'] as List).length > 10000 ||
        (value['selected'] != null && value['selected'] is! int)) {
      throw const FormatException('Invalid retake choice');
    }
    return RetakeChoice(
      id: value['id'] as String,
      options: (value['options'] as List).map(RetakeOption.fromJson).toList(),
      selected: value['selected'] as int?,
    );
  }
}

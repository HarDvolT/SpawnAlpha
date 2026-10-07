import 'dart:convert';

import '../cut/clean_plan.dart' show CleanPlan, speechOnCut, speechOnCleanCut;

import '../model/cut_plan.dart';
import '../model/note_timeline.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../transcription/script_alignment.dart';
import '../transcription/word_timing.dart';

class ChapterText {
  const ChapterText(this.time, this.title);
  final Duration time;
  final String title;
  Map<String, Object?> toJson() => {
    'timeUs': time.inMicroseconds,
    'title': title,
  };
}

class PublishingText {
  PublishingText({
    required this.language,
    required this.duration,
    required this.title,
    required this.description,
    required List<ChapterText> chapters,
    this.notice,
    this.notes = false,
  }) : chapters = List.unmodifiable(chapters) {
    if (duration <= Duration.zero ||
        duration > const Duration(hours: 24) ||
        title.length > 512 ||
        description.length > 10000 ||
        chapters.length > 1000 ||
        !_text(title) ||
        !_text(description)) {
      throw const FormatException('Invalid publishing text');
    }
    var previous = const Duration(microseconds: -1);
    for (final chapter in chapters) {
      if (chapter.time < Duration.zero ||
          chapter.time >= duration ||
          chapter.time <= previous ||
          chapter.title.length > 512 ||
          !_text(chapter.title) ||
          chapter.title.trim().isEmpty ||
          chapter.title.contains('\n') ||
          chapter.title.contains('\r')) {
        throw const FormatException('Invalid chapter');
      }
      previous = chapter.time;
    }
  }
  final ScriptLanguage language;
  final Duration duration;
  final String title, description;
  final List<ChapterText> chapters;
  final String? notice;
  final bool notes;
  PublishingText copyWith({
    String? title,
    String? description,
    List<ChapterText>? chapters,
  }) => PublishingText(
    language: language,
    duration: duration,
    title: title ?? this.title,
    description: description ?? this.description,
    chapters: chapters ?? this.chapters,
    notice: notice,
    notes: notes,
  );
  String get chapterText =>
      chapters.map((c) => '${chapterStamp(c.time)} ${c.title}').join('\n');
  String get combined => [
    title,
    description,
    if (chapters.isNotEmpty) chapterText,
  ].where((s) => s.trim().isNotEmpty).join('\n\n');
  Map<String, Object?> toJson() => {
    'version': 1,
    'language': language.name,
    'durationUs': duration.inMicroseconds,
    'title': title,
    'description': description,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'notes': notes,
  };
}

bool _text(String value) =>
    !RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]')
        .hasMatch(value) &&
    utf8.decode(utf8.encode(value)) == value;
String _short(String value, int limit) {
  final plain = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return plain.runes.length <= limit
      ? plain
      : '${String.fromCharCodes(plain.runes.take(limit - 1))}…';
}

String chapterStamp(Duration time) {
  if (time.isNegative) throw ArgumentError('Negative chapter time');
  final seconds = time.inSeconds;
  return '${seconds >= 3600 ? '${seconds ~/ 3600}:' : ''}${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Frozen card clock validation, independent of its local metadata reader.
List<NoteMoment> chapterNoteMoments(
  Object? json,
  ScriptDocument snapshot,
  Duration duration,
) {
  if (!snapshot.usesNotes ||
      json is! List ||
      json.isEmpty ||
      json.length > 50000) {
    throw const FormatException('Invalid card clock');
  }
  final result = <NoteMoment>[];
  var previous = -1;
  for (final item in json) {
    if (item is! Map ||
        item.length != 2 ||
        item['cardIndex'] is! int ||
        item['timeUs'] is! int ||
        (item['cardIndex'] as int) < 0 ||
        (item['cardIndex'] as int) >= snapshot.notes.cards.length ||
        (item['timeUs'] as int) <= previous ||
        (item['timeUs'] as int) >= duration.inMicroseconds ||
        (result.isEmpty && item['timeUs'] != 0)) {
      throw const FormatException('Invalid card clock');
    }
    previous = item['timeUs'] as int;
    result.add(
      NoteMoment(item['cardIndex'] as int, Duration(microseconds: previous)),
    );
  }
  return List.unmodifiable(result);
}

PublishingText publishingFromSpeech({
  required WordTranscript source,
  required CutPlan plan,
  ScriptDocument? snapshot,
  bool aligned = false,
  List<NoteMoment> noteMoments = const [],
  CleanPlan? clean,
}) {
  if (source.duration != plan.sourceDuration ||
      source.language != plan.language ||
      snapshot != null && snapshot.language != source.language) {
    throw const FormatException('Publishing clock mismatch');
  }
  if (clean != null &&
      jsonEncode(clean.asCutPlan().toJson()) != jsonEncode(plan.toJson())) {
    throw const FormatException('Publishing cut mismatch');
  }
  final kept = clean == null
      ? speechOnCut(source, plan)
      : speechOnCleanCut(source, clean);
  final labels = <int, String>{};
  final identities = <int, int>{};
  String? notice;
  if (snapshot != null && snapshot.usesNotes) {
    if (noteMoments.isEmpty) {
      notice = 'Card timing is unavailable. Chapters were not guessed.';
    } else {
      chapterNoteMoments(
        noteMoments.map((m) => m.toJson()).toList(),
        snapshot,
        source.duration,
      );
      for (var i = 0, card = 0; i < source.words.length; ++i) {
        while (card + 1 < noteMoments.length &&
            noteMoments[card + 1].time <= source.words[i].start) {
          ++card;
        }
        final index = noteMoments[card].index;
        final title = _short(snapshot.notes.cards[index].title, 100);
        if (title.isNotEmpty) {
          labels[i] = title;
          identities[i] = index;
        }
      }
    }
  } else if (snapshot != null && aligned) {
    final tokenSection = <int, int>{}, sections = <int, String>{};
    var section = 0;
    final title = <String>[];
    for (final token in snapshot.tokens) {
      tokenSection[token.index] = section;
      if (token.isWord && title.length < 8) title.add(token.text);
      if (token.endsParagraph || token.index == snapshot.tokens.length - 1) {
        sections[section] = _short(title.join(' '), 100);
        title.clear();
        ++section;
      }
    }
    ScriptAlignment? alignment;
    try {
      alignment = alignTranscript(snapshot, source);
    } on FormatException {
      notice = 'Section timing is unavailable. Chapters were not guessed.';
    }
    for (final word in alignment?.words ?? const <AlignedWord>[]) {
      final spoken = source.words[word.spokenIndex];
      if (word.match != WordMatch.exact ||
          word.tokenIndex == null ||
          !(spoken.corrected || (spoken.confidence ?? 0) >= .6)) {
        continue;
      }
      final section = tokenSection[word.tokenIndex]!;
      if (sections[section]?.isNotEmpty == true) {
        labels[word.spokenIndex] = sections[section]!;
        identities[word.spokenIndex] = section;
      }
    }
  } else {
    notice = 'Section timing is unavailable. Chapters were not guessed.';
  }
  final chapters = <ChapterText>[];
  int? previousSection;
  var output = Duration.zero;
  for (final range in plan.ranges) {
    var lo = 0, hi = source.words.length;
    while (lo < hi) {
      final middle = (lo + hi) ~/ 2;
      if (source.words[middle].end <= range.start) {
        lo = middle + 1;
      } else {
        hi = middle;
      }
    }
    for (
      var i = lo;
      i < source.words.length && source.words[i].start < range.end;
      ++i
    ) {
      final identity = identities[i], label = labels[i];
      if (identity == null || label == null || identity == previousSection) {
        continue;
      }
      previousSection = identity;
      final time = chapters.isEmpty
          ? Duration.zero
          : output + source.words[i].start - range.start;
      if (chapters.isNotEmpty &&
          time.inSeconds == chapters.last.time.inSeconds) {
        final last = chapters.removeLast();
        chapters.add(
          ChapterText(last.time, _short('${last.title} / $label', 120)),
        );
      } else {
        if (chapters.length >= 1000) {
          throw const FormatException('Too many sections');
        }
        chapters.add(ChapterText(time, label));
      }
    }
    output += range.duration;
  }
  final actual = kept.words.map((w) => w.text);
  final title = snapshot?.title.trim().isNotEmpty == true
      ? snapshot!.title
      : chapters.firstOrNull?.title ?? actual.take(8).join(' ');
  return PublishingText(
    language: plan.language,
    duration: plan.duration,
    title: _short(title, 120),
    description: _short(actual.take(120).join(' '), 2000),
    chapters: chapters,
    notice: notice,
    notes: snapshot?.usesNotes ?? false,
  );
}

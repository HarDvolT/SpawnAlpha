import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/note_timeline.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/recording/floating_prompter.dart';

NoteDeck fixtureNotes(ScriptLanguage language) => NoteDeck([
  NoteCard(id: 'opening', title: switch (language) {
    ScriptLanguage.en => 'Opening', ScriptLanguage.fr => 'Ouverture', ScriptLanguage.ar => 'البداية',
  }, body: switch (language) {
    ScriptLanguage.en => 'Why it matters\nA useful example', ScriptLanguage.fr => 'Pourquoi c’est utile\nUn exemple concret', ScriptLanguage.ar => 'لماذا هذا مهم\nمثال مفيد',
  }),
  NoteCard(id: 'closing', title: switch (language) {
    ScriptLanguage.en => 'Next steps', ScriptLanguage.fr => 'Prochaines étapes', ScriptLanguage.ar => 'الخطوة التالية',
  }, body: '1\n2'),
]);

void main() {
  for (final language in ScriptLanguage.values) {
    test('private deck round trip, copy and script compatibility $language', () {
      final original = ScriptDocument.create(text: 'Existing script', language: language)
          .copyWith(recordingAid: RecordingAid.notes, notes: fixtureNotes(language));
      final saved = ScriptDocument.fromJson(jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>);
      expect(saved.usesNotes, isTrue);
      expect(saved.stageReady, isTrue);
      expect(saved.notes.cards.first.body, original.notes.cards.first.body);
      expect(saved.text, 'Existing script');
      final edited = saved.copyWith(title: 'Later edit').withText('Changed script');
      expect(edited.notes.cards.first.title, original.notes.cards.first.title);
      expect(edited.usesNotes, isTrue);
      expect(FloatingPresentation.decode(FloatingPresentation(script: edited).encode()).script.notes.cards.length, 2);
      expect(edited.copyWith(recordingAid: RecordingAid.script).text, 'Changed script');
      final legacy = original.toJson()..remove('recordingAid')..remove('notes');
      expect(ScriptDocument.fromJson(legacy).usesNotes, isFalse);
    });
    test('manual navigation and immutable reorder $language', () {
      final deck = fixtureNotes(language), c = NoteController(fixtureNotes(language));
      expect(c.previous(), isFalse);
      expect(c.next(), isTrue);
      expect(c.index, 1);
      expect(c.next(), isFalse);
      expect(c.index, 1);
      expect(c.previous(), isTrue);
      c.next(); c.restart();
      expect(c.index, 0);
      final moved = deck.move(0, 1);
      expect(moved.cards.first.id, 'closing');
      expect(deck.cards.first.id, 'opening');
      expect(() => deck.cards.add(NoteCard.create()), throwsUnsupportedError);
      expect(moved.remove(1).cards, hasLength(1));
      expect(deck.replace(0, deck.cards.first.copyWith(body: 'New')).cards.first.body, 'New');
      expect(deck.cards.first.body, isNot('New'));
    });
  }
  test('empty, oversized and duplicate decks are rejected or not stage ready', () {
    expect(NoteDeck(const []).ready, isFalse);
    expect(NoteDeck([NoteCard.create()]).ready, isFalse);
    expect(NoteController(NoteDeck(const [])).next(), isFalse);
    expect(() => NoteDeck(List.generate(201, (_) => NoteCard.create())), throwsFormatException);
    expect(() => NoteDeck([NoteCard(id: 'same'), NoteCard(id: 'same')]), throwsFormatException);
    expect(() => NoteCard.fromJson({'id': 'private', 'body': ['private'], 'title': ''}), throwsFormatException);
    expect(() => NoteDeck.fromJson({'version': 2, 'cards': []}), throwsFormatException);
  });
  test('pause browsing coalesces on resume and same-clock changes replace', () {
    final clock = NoteTimeline(3);
    expect(clock.observe(1, const Duration(seconds: 2), paused: false), isTrue);
    clock.observe(2, const Duration(seconds: 3), paused: true);
    clock.observe(0, const Duration(seconds: 3), paused: true);
    clock.observe(2, const Duration(seconds: 3), paused: true);
    expect(clock.moments, hasLength(2));
    clock.observe(2, const Duration(seconds: 3), paused: false);
    expect(clock.moments.last.index, 2);
    clock.observe(1, const Duration(seconds: 3), paused: false);
    expect(clock.moments, hasLength(3));
    expect(clock.moments.last.index, 1);
    expect(() => clock.observe(3, const Duration(seconds: 3), paused: false), throwsFormatException);
    expect(() => clock.observe(1, const Duration(seconds: 1), paused: false), throwsFormatException);
  });
}

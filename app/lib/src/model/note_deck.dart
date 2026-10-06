import 'mark.dart';

/// Private talking points, independent of script tokens and delivery marks.
class NoteCard {
  NoteCard({required this.id, this.title = '', this.body = ''});
  factory NoteCard.create({String title = '', String body = ''}) => NoteCard(id: newId(), title: title, body: body);
  final String id, title, body;
  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;
  List<String> get points => body.split('\n').where((s) => s.trim().isNotEmpty).toList(growable: false);
  NoteCard copyWith({String? title, String? body}) =>
      NoteCard(id: id, title: title ?? this.title, body: body ?? this.body);
  Map<String, Object?> toJson() => {'id': id, 'title': title, 'body': body};
  factory NoteCard.fromJson(Map<String, Object?> json) {
    final id = json['id'], title = json['title'], body = json['body'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        body is! String ||
        title.length + body.length > NoteDeck.maxCardLength) {
      throw const FormatException('Unreadable note card');
    }
    return NoteCard(id: id, title: title, body: body);
  }
}

class NoteDeck {
  NoteDeck(Iterable<NoteCard> cards) : cards = List.unmodifiable(cards) {
    if (this.cards.length > maxCards ||
        this.cards.map((c) => c.id).toSet().length != this.cards.length ||
        this.cards.any((c) => c.id.isEmpty || c.title.length + c.body.length > maxCardLength)) {
      throw const FormatException('Invalid note deck');
    }
  }
  static const maxCards = 200, maxCardLength = 65536;
  final List<NoteCard> cards;
  bool get ready => cards.isNotEmpty && cards.every((c) => !c.isEmpty);
  NoteDeck replace(int index, NoteCard card) => NoteDeck([
    for (var i = 0; i < cards.length; i++)
      if (i == index) card else cards[i],
  ]);
  NoteDeck add(NoteCard card) => NoteDeck([...cards, card]);
  NoteDeck remove(int index) => NoteDeck([
    for (var i = 0; i < cards.length; i++)
      if (i != index) cards[i],
  ]);
  NoteDeck move(int from, int to) {
    if (from < 0 || to < 0 || from >= cards.length || to >= cards.length) {
      return this;
    }
    final next = [...cards];
    next.insert(to, next.removeAt(from));
    return NoteDeck(next);
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'cards': [for (final c in cards) c.toJson()],
  };
  factory NoteDeck.fromJson(Map<String, Object?> json) {
    final cards = json['cards'];
    if (json['version'] != 1 ||
        cards is! List ||
        cards.length > maxCards ||
        cards.any((c) => c is! Map<String, Object?>)) {
      throw const FormatException('Unreadable note deck');
    }
    return NoteDeck(cards.map((c) => NoteCard.fromJson(c as Map<String, Object?>)));
  }
}

/// Manual, bounded navigation. The last card never ends a take.
class NoteController {
  NoteController(this.deck);
  final NoteDeck deck;
  int _index = 0;
  int get index => _index;
  NoteCard? get card => deck.cards.isEmpty ? null : deck.cards[_index];
  bool get canPrevious => _index > 0;
  bool get canNext => _index + 1 < deck.cards.length;
  bool previous() => canPrevious ? (--_index >= 0) : false;
  bool next() => canNext ? (++_index < deck.cards.length) : false;
  void restart() => _index = 0;
}

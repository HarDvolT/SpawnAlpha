import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/token.dart';

void main() {
  group('tokenize', () {
    test('keeps punctuation on words and records offsets', () {
      final text = 'Hello, world!  Bye.';
      final tokens = tokenize(text);
      expect(tokens.map((t) => t.text), ['Hello,', 'world!', 'Bye.']);
      expect(text.substring(tokens[1].start, tokens[1].end), 'world!');
      expect(tokens.map((t) => t.bare), ['hello', 'world', 'bye']);
    });

    test('counts line breaks around tokens', () {
      final tokens = tokenize('One\ntwo\n\nthree');
      expect(tokens[0].lineBreaksAfter, 1);
      expect(tokens[1].lineBreaksBefore, 1);
      expect(tokens[1].endsParagraph, isTrue);
      expect(tokens[2].lineBreaksBefore, 2);
      expect(tokens[2].lineBreaksAfter, 0);
    });

    test('detects sentence and clause ends in all three languages', () {
      final tokens = tokenize('Done. "Really?" Wait, هل انتهيت؟ نعم، طبعاً «fin.»');
      expect(tokens[0].endsSentence, isTrue);
      expect(tokens[1].endsSentence, isTrue, reason: 'closing quote after ?');
      expect(tokens[2].endsClause, isTrue);
      expect(tokens[4].endsSentence, isTrue, reason: 'Arabic question mark');
      expect(tokens[5].endsClause, isTrue, reason: 'Arabic comma');
      expect(tokens[7].endsSentence, isTrue, reason: 'French guillemets');
    });

    test('a lone dash is not a word', () {
      final tokens = tokenize('this — that');
      expect(tokens[1].isWord, isFalse);
      expect(tokens[1].endsClause, isTrue);
    });

    test('flags words in capitals', () {
      final tokens = tokenize('This is HUGE and AI ok');
      expect(tokens[2].isShouted, isTrue);
      expect(tokens[4].isShouted, isFalse, reason: 'two letters is an acronym, not shouting');
    });
  });

  group('normalizeWord', () {
    test('folds Arabic letter variants and strips diacritics', () {
      expect(normalizeWord('أولاً،'), 'اولا');
      expect(normalizeWord('الخطوةُ'), 'الخطوه');
      expect(normalizeWord('إلى'), 'الي');
    });

    test('lowercases and keeps French accents and elisions', () {
      expect(normalizeWord("L’étape,"), "l'étape");
      expect(normalizeWord('«Premièrement»'), 'premièrement');
    });
  });

  group('sentenceRanges', () {
    test('splits on sentence punctuation and on line breaks', () {
      final tokens = tokenize('First line\nSecond one. Third one');
      expect(sentenceRanges(tokens), [
        const TokenRange(0, 1),
        const TokenRange(2, 3),
        const TokenRange(4, 5),
      ]);
      expect(sentenceAt(tokens, 3), const TokenRange(2, 3));
    });
  });

  group('ScriptLanguage.detect', () {
    test('tells the three languages apart', () {
      expect(ScriptLanguage.detect('Today I want to show you the fastest way to edit your videos.'),
          ScriptLanguage.en);
      expect(ScriptLanguage.detect("Aujourd'hui je vais vous montrer la méthode la plus rapide pour les vidéos."),
          ScriptLanguage.fr);
      expect(ScriptLanguage.detect('اليوم سأريكم أسرع طريقة لتعديل الفيديو الخاص بكم.'), ScriptLanguage.ar);
      expect(ScriptLanguage.detect('Hi'), isNull);
    });
  });
}

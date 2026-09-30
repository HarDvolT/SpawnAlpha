import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/markup/local_markup_engine.dart';
import 'package:spawnalpha/src/markup/markup_engine.dart';
import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';

ScriptDocument script(String text, ScriptLanguage language, CoachingStyle style) =>
    ScriptDocument.create(text: text, language: language, style: style);

Future<ScriptDocument> markedUp(String text, ScriptLanguage language, CoachingStyle style) async {
  final s = script(text, language, style);
  return applyMarkup(s, await const LocalMarkupEngine().markup(s));
}

/// The marked words, as text, for each mark of [kind].
List<String> marked(ScriptDocument s, MarkKind kind) => [
      for (final m in s.marks)
        if (m.kind == kind) s.textOf(m.start, m.end),
    ];

void main() {
  test('every proposed mark is pending and from the local engine', () async {
    final s = await markedUp('Sales grew 40% this year. That is the story.', ScriptLanguage.en,
        CoachingStyle.presentation);
    expect(s.marks, isNotEmpty);
    expect(s.marks.every((m) => !m.accepted && m.origin == MarkOrigin.local && m.note != null), isTrue);
  });

  group('presentation', () {
    test('stresses numbers with their unit and slows down for figures', () async {
      final s = await markedUp(
        'Last year we grew revenue by forty percent. Our team did it in 12 months. So what comes next?',
        ScriptLanguage.en,
        CoachingStyle.presentation,
      );
      expect(marked(s, MarkKind.stress), containsAll(['forty percent.', '12 months.']));
      expect(marked(s, MarkKind.slower), ['Our team did it in 12 months.']);
      expect(marked(s, MarkKind.pauseLong), contains('percent.'));
      expect(marked(s, MarkKind.pauseLong), contains('months.'));
      expect(marked(s, MarkKind.energy), ['So what comes next?']);
    });

    test('never places a gap mark after the last word', () async {
      final s = await markedUp('One point. Two points.', ScriptLanguage.en, CoachingStyle.presentation);
      final last = s.tokens.length - 1;
      expect(s.marks.where((m) => m.kind.isGap && m.end == last), isEmpty);
    });
  });

  group('tutorial', () {
    test('pauses between steps and stresses the action', () async {
      final s = await markedUp(
        'First, open the Settings app. Then tap Network. Finally, restart the router.',
        ScriptLanguage.en,
        CoachingStyle.tutorial,
      );
      expect(marked(s, MarkKind.pauseLong), ['app.', 'Network.']);
      expect(marked(s, MarkKind.stress), containsAll(['open', 'tap', 'restart']));
    });

    test('slows down on technical terms', () async {
      final s = await markedUp(
        'Now run npm install inside the project folder. Then edit config.yaml and set maxRetries to 3.',
        ScriptLanguage.en,
        CoachingStyle.tutorial,
      );
      expect(marked(s, MarkKind.slower), ['config.yaml', 'maxRetries']);
    });

    test('recognizes French steps and imperatives', () async {
      final s = await markedUp(
        "D'abord, ouvrez l'application. Ensuite, cliquez sur Réglages. Enfin, redémarrez.",
        ScriptLanguage.fr,
        CoachingStyle.tutorial,
      );
      expect(marked(s, MarkKind.pauseLong), ["l'application.", 'Réglages.']);
      expect(marked(s, MarkKind.stress), containsAll(['ouvrez', 'cliquez', 'redémarrez.']));
    });

    test('recognizes Arabic steps and imperatives', () async {
      final s = await markedUp(
        'أولاً، افتح التطبيق. ثم اضغط على الإعدادات. وأخيراً، أعد تشغيل الجهاز.',
        ScriptLanguage.ar,
        CoachingStyle.tutorial,
      );
      expect(marked(s, MarkKind.pauseLong), ['التطبيق.', 'الإعدادات.']);
      expect(marked(s, MarkKind.stress), containsAll(['افتح', 'اضغط', 'أعد']));
    });
  });

  group('short social video', () {
    test('opens and closes with energy and lets the hook land', () async {
      final s = await markedUp(
        'Stop scrolling. This one trick saves you ten hours a week. Follow for more.',
        ScriptLanguage.en,
        CoachingStyle.shortSocial,
      );
      expect(marked(s, MarkKind.energy), ['Stop scrolling.', 'Follow for more.']);
      expect(marked(s, MarkKind.pauseShort), contains('scrolling.'));
      expect(marked(s, MarkKind.stress), contains('ten hours'));
    });

    test('offers a shorter hook when the opener runs long', () async {
      final s = await markedUp(
        'So today I wanted to sit down and talk to you about something that has been on my mind for a while now. '
        'It matters.',
        ScriptLanguage.en,
        CoachingStyle.shortSocial,
      );
      expect(s.suggestions.where((g) => g.kind == SuggestionKind.hook), hasLength(1));
    });
  });

  group('breaths', () {
    test('land on a comma once the sentence runs long', () async {
      final s = await markedUp(
        'We looked at every single option on the table for the new office in town, '
        'and in the end we picked the one closest to the station.',
        ScriptLanguage.en,
        CoachingStyle.presentation,
      );
      expect(marked(s, MarkKind.breath), ['town,']);
    });

    test('fall back to a conjunction when there is no comma', () async {
      final s = await markedUp(
        'Nous avons regardé chaque option possible pour le nouveau bureau en ville pendant des mois '
        "et des mois avec toute l'équipe mais nous avons finalement choisi le plus proche de la gare.",
        ScriptLanguage.fr,
        CoachingStyle.presentation,
      );
      expect(marked(s, MarkKind.breath), ["l'équipe"]);
    });
  });

  group('tighten suggestions', () {
    test('cut filler and move the capital onto the next word', () async {
      final s = await markedUp('Basically, we need to act. We did it in order to grow.', ScriptLanguage.en,
          CoachingStyle.presentation);
      final byOriginal = {for (final g in s.suggestions) g.original: g.replacement};
      expect(byOriginal['Basically, we'], 'We');
      expect(byOriginal['in order to'], 'to');
      final applied = s.applySuggestion(s.suggestions.firstWhere((g) => g.original == 'in order to'));
      expect(applied.text, 'Basically, we need to act. We did it to grow.');
    });

    test('work in French and Arabic', () async {
      final fr = await markedUp('On travaille afin de gagner.', ScriptLanguage.fr, CoachingStyle.presentation);
      expect(fr.suggestions.single.replacement, 'pour');
      final ar = await markedUp('نحن نعمل يعني كل يوم.', ScriptLanguage.ar, CoachingStyle.presentation);
      expect(ar.suggestions.single.original, 'يعني كل');
      expect(ar.suggestions.single.replacement, 'كل');
    });
  });

  test('an empty script gets no marks', () async {
    final s = await markedUp('   ', ScriptLanguage.en, CoachingStyle.presentation);
    expect(s.marks, isEmpty);
  });
}

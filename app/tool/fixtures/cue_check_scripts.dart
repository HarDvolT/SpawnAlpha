import 'package:spawnalpha/src/model/coaching_style.dart';
import 'package:spawnalpha/src/model/mark.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/token.dart';

/// A short, accepted-mark script for checking every cue on real hardware.
/// Test content only: no markup provider, user script or saved take is involved.
ScriptDocument cueCheckScript(ScriptLanguage language) {
  final lines = switch (language) {
    ScriptLanguage.en => const [
      'Important words deserve emphasis.',
      'Let this short pause land.',
      'Hold a longer pause here.',
      'Breathe before the next line.',
      'Slow down and give these words room.',
      'Speed up through this familiar idea.',
      'Lift the energy and finish with conviction.',
      'You have now seen every delivery cue.',
    ],
    ScriptLanguage.fr => const [
      'Important : faites ressortir ce mot.',
      'Laissez cette courte pause respirer.',
      'Gardez ici une pause plus longue.',
      'Respirez avant la prochaine phrase.',
      'Ralentissez et donnez de la place aux mots.',
      'Accélérez sur cette idée familière.',
      'Montez en énergie et terminez avec conviction.',
      'Vous avez maintenant vu chaque indication.',
    ],
    ScriptLanguage.ar => const [
      'مهم: قل هذه الكلمة بوضوح.',
      'اترك هذه الوقفة القصيرة تأخذ وقتها.',
      'توقف هنا مدة أطول قليلاً.',
      'خذ نفساً قبل الجملة التالية.',
      'تمهل وأعط هذه الكلمات وقتاً كافياً.',
      'أسرع عند شرح هذه الفكرة المألوفة.',
      'ارفع حماسك واختم كلامك بثقة.',
      'لقد شاهدت الآن كل إشارات الإلقاء.',
    ],
  };
  const kinds = [
    MarkKind.stress,
    MarkKind.pauseShort,
    MarkKind.pauseLong,
    MarkKind.breath,
    MarkKind.slower,
    MarkKind.faster,
    MarkKind.energy,
  ];
  final text = lines.join('\n\n');
  final marks = <Mark>[];
  var start = 0;
  for (var i = 0; i < kinds.length; i++) {
    final end = start + tokenize(lines[i]).length - 1;
    final kind = kinds[i];
    marks.add(
      kind.isGap
          ? Mark.gap(id: 'cue-check-${kind.id}', kind: kind, after: end)
          : Mark(
              id: 'cue-check-${kind.id}',
              kind: kind,
              start: start,
              end: kind == MarkKind.stress ? start : end,
            ),
    );
    start = end + 1;
  }
  return ScriptDocument(
    id: 'cue-check-${language.name}',
    title: switch (language) {
      ScriptLanguage.en => 'Delivery cue check',
      ScriptLanguage.fr => 'Essai des indications',
      ScriptLanguage.ar => 'تجربة إشارات الإلقاء',
    },
    text: text,
    language: language,
    style: CoachingStyle.presentation,
    marks: normalizeMarks(marks, tokenize(text).length),
  );
}

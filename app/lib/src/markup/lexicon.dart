import '../model/script_language.dart';
import '../model/token.dart';

/// Word lists the on-device markup uses to find steps, actions, claims and
/// calls to action. Entries can be phrases of several words; they are
/// normalized with [normalizeWord] when loaded, so they may be written with
/// accents, hamza or diacritics.
class Lexicon {
  Lexicon._(this.language, Map<String, List<String>> lists, Map<String, String> tightenings)
      : stepMarkers = PhraseSet(lists['steps']!),
        actionVerbs = PhraseSet(lists['actions']!),
        emphasis = PhraseSet(lists['emphasis']!),
        conclusion = PhraseSet(lists['conclusion']!),
        callToAction = PhraseSet(lists['cta']!),
        conjunctions = PhraseSet(lists['conjunctions']!),
        numberWords = PhraseSet(lists['numbers']!),
        units = PhraseSet(lists['units']!),
        tightenings = {
          for (final e in tightenings.entries) PhraseSet.split(e.key).join(' '): e.value,
        };

  final ScriptLanguage language;

  /// Words that open a new step: "first", "then", "ensuite", "ثم".
  final PhraseSet stepMarkers;

  /// Instructions in a tutorial: "click", "cliquez", "اضغط".
  final PhraseSet actionVerbs;

  /// Words that carry a claim: "never", "only", "jamais", "فقط".
  final PhraseSet emphasis;

  /// Words that open a conclusion: "so", "therefore", "donc", "لذلك".
  final PhraseSet conclusion;

  final PhraseSet callToAction;

  /// Places where a breath fits when a sentence has no comma.
  final PhraseSet conjunctions;

  final PhraseSet numberWords;

  /// Words that belong with a number: "percent", "million", "٪".
  final PhraseSet units;

  /// Wordy phrases and a shorter way to say them. An empty replacement
  /// means the phrase can go.
  final Map<String, String> tightenings;

  /// The forms of [token] worth looking up: French elisions (l', d', qu')
  /// and the Arabic "and"/"so" prefixes (و, ف) are stripped as fallbacks.
  List<String> formsOf(Token token) {
    final bare = token.bare;
    final forms = [bare];
    switch (language) {
      case ScriptLanguage.en:
        if (bare.endsWith("'s")) forms.add(bare.substring(0, bare.length - 2));
      case ScriptLanguage.fr:
        final elision = _frenchElision.firstMatch(bare);
        if (elision != null) forms.add(elision.group(1)!);
      case ScriptLanguage.ar:
        if (bare.length > 3 && (bare.startsWith('و') || bare.startsWith('ف'))) {
          forms.add(bare.substring(1));
        }
    }
    return forms;
  }

  /// The longest phrase of [set] that starts at token [index], or null.
  List<String>? phraseAt(PhraseSet set, List<Token> tokens, int index) {
    List<String>? best;
    for (final form in formsOf(tokens[index])) {
      for (final phrase in set.startingWith(form)) {
        if (phrase.length <= (best?.length ?? 0) || index + phrase.length > tokens.length) continue;
        var ok = true;
        for (var k = 1; k < phrase.length; k++) {
          if (tokens[index + k].bare != phrase[k]) {
            ok = false;
            break;
          }
        }
        if (ok) best = phrase;
      }
    }
    return best;
  }

  /// How many tokens from [index] match a phrase in [set]; 0 for none.
  int matchAt(PhraseSet set, List<Token> tokens, int index) => phraseAt(set, tokens, index)?.length ?? 0;

  bool isNumber(Token token) =>
      token.hasDigit || formsOf(token).any((f) => numberWords.startingWith(f).isNotEmpty);

  /// A percent sign written as its own word, as French typography does.
  bool isPercentSign(Token token) => token.text == '%' || token.text == '٪';

  late final PhraseSet tighteningPhrases = PhraseSet(tightenings.keys);

  static final _frenchElision = RegExp(r"^(?:l|d|j|m|n|s|t|c|qu|jusqu|lorsqu|puisqu)'(.+)$");

  static final Map<ScriptLanguage, Lexicon> _cache = {};

  static Lexicon of(ScriptLanguage language) => _cache.putIfAbsent(
        language,
        () => switch (language) {
          ScriptLanguage.en => Lexicon._(language, _english, _englishTightenings),
          ScriptLanguage.fr => Lexicon._(language, _french, _frenchTightenings),
          ScriptLanguage.ar => Lexicon._(language, _arabic, _arabicTightenings),
        },
      );
}

/// A set of phrases indexed by their first word.
class PhraseSet {
  PhraseSet(Iterable<String> phrases) {
    for (final p in phrases) {
      final words = split(p);
      if (words.isEmpty) continue;
      _byFirst.putIfAbsent(words.first, () => []).add(words);
    }
  }

  final Map<String, List<List<String>>> _byFirst = {};

  List<List<String>> startingWith(String word) => _byFirst[word] ?? const [];

  static List<String> split(String phrase) => [
        for (final w in phrase.split(RegExp(r'\s+')))
          if (normalizeWord(w) case final n when n.isNotEmpty) n,
      ];
}

const _english = {
  'steps': [
    'first', 'firstly', 'second', 'secondly', 'third', 'thirdly', 'then', 'next', 'after that',
    'afterwards', 'finally', 'lastly', 'step', 'now', 'once', 'to start', 'to finish',
  ],
  'actions': [
    'click', 'tap', 'open', 'close', 'select', 'choose', 'press', 'type', 'enter', 'drag', 'drop',
    'run', 'install', 'save', 'copy', 'paste', 'add', 'remove', 'delete', 'create', 'set', 'turn',
    'go', 'scroll', 'pick', 'check', 'uncheck', 'download', 'upload', 'connect', 'restart',
    'launch', 'start', 'stop', 'cut', 'mix', 'pour', 'stir', 'measure', 'place', 'insert',
    'attach', 'plug', 'unplug', 'hold', 'release', 'swipe', 'rename', 'move', 'fill', 'write',
  ],
  'emphasis': [
    'never', 'always', 'every', 'only', 'most', 'best', 'worst', 'none', 'must', 'biggest',
    'fastest', 'new', 'free', 'guaranteed', 'secret', 'simple', 'easy', 'key', 'critical',
    'important', 'huge', 'massive', 'proven', 'instantly', 'today', 'everything', 'nothing',
    'nobody', 'everyone', 'mistake', 'problem', 'why', 'stop', 'exactly', 'really', 'more', 'less',
    'double', 'half', 'twice', 'record',
  ],
  'conclusion': [
    'so', 'therefore', "that's why", 'that is why', 'in short', 'the bottom line', 'bottom line',
    "here's the thing", 'imagine', 'remember', 'in the end', 'to sum up', 'in conclusion',
  ],
  'cta': [
    'follow', 'subscribe', 'like', 'comment', 'share', 'link', 'join', 'try', 'download',
    'sign up', 'save this', 'tag', 'check out', 'book', 'buy', 'get',
  ],
  'conjunctions': [
    'and', 'but', 'or', 'because', 'so', 'which', 'while', 'when', 'although', 'though',
    'unless', 'until', 'where', 'whereas', 'since', 'if',
  ],
  'numbers': [
    'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven',
    'twelve', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
    'hundred', 'thousand', 'million', 'billion', 'trillion', 'half', 'double', 'twice', 'triple',
  ],
  'units': [
    'percent', 'per cent', 'million', 'billion', 'thousand', 'hundred', 'dollars', 'euros',
    'times', 'minutes', 'hours', 'days', 'weeks', 'months', 'years', 'seconds',
  ],
};

const _englishTightenings = {
  'basically': '',
  'actually': '',
  'literally': '',
  'kind of': '',
  'sort of': '',
  'in order to': 'to',
  'due to the fact that': 'because',
  'at this point in time': 'now',
  'in the event that': 'if',
  'for the purpose of': 'to',
  'is able to': 'can',
  'are able to': 'can',
  'at the end of the day': '',
  'it is important to note that': '',
  'needless to say': '',
};

const _french = {
  'steps': [
    "d'abord", 'premièrement', 'deuxièmement', 'troisièmement', 'ensuite', 'puis', 'après',
    'après ça', 'enfin', 'finalement', 'étape', 'maintenant', 'pour commencer', 'pour finir',
  ],
  'actions': [
    'cliquez', 'clique', 'appuyez', 'appuie', 'ouvrez', 'ouvre', 'fermez', 'ferme',
    'sélectionnez', 'sélectionne', 'choisissez', 'choisis', 'tapez', 'tape', 'saisissez',
    'saisis', 'entrez', 'glissez', 'glisse', 'faites', 'fais', 'lancez', 'lance', 'installez',
    'installe', 'enregistrez', 'enregistre', 'copiez', 'copie', 'collez', 'colle', 'ajoutez',
    'ajoute', 'supprimez', 'supprime', 'créez', 'crée', 'allez', 'va', 'cochez', 'coche',
    'téléchargez', 'télécharge', 'redémarrez', 'versez', 'verse', 'mélangez', 'mélange',
    'coupez', 'coupe', 'mesurez', 'placez', 'place', 'insérez', 'branchez', 'branche',
    'maintenez', 'déplacez', 'remplissez', 'écrivez', 'écris', 'renommez',
  ],
  'emphasis': [
    'jamais', 'toujours', 'chaque', 'tous', 'toutes', 'seul', 'seule', 'seulement', 'meilleur',
    'meilleure', 'pire', 'aucun', 'aucune', 'doit', 'essentiel', 'essentielle', 'crucial',
    'important', 'importante', 'énorme', 'gratuit', 'gratuite', 'nouveau', 'nouvelle', 'secret',
    'simple', 'facile', 'clé', 'prouvé', "aujourd'hui", 'vraiment', 'tout', 'rien', 'personne',
    'erreur', 'problème', 'pourquoi', 'exactement', 'plus', 'moins', 'double', 'moitié', 'record',
  ],
  'conclusion': [
    'donc', 'alors', 'ainsi', 'bref', 'en résumé', 'voilà pourquoi', "c'est pourquoi",
    'imaginez', 'imagine', 'retenez', 'retiens', 'au final', 'en conclusion', 'pour conclure',
  ],
  'cta': [
    'abonnez', 'abonne', 'likez', 'like', 'commentez', 'commente', 'partagez', 'partage', 'lien',
    'suivez', 'suis', 'rejoignez', 'rejoins', 'essayez', 'essaie', 'inscrivez', 'inscris',
    'téléchargez', 'enregistre', 'réservez',
  ],
  'conjunctions': [
    'et', 'mais', 'ou', 'car', 'donc', 'parce', 'qui', 'que', 'quand', 'lorsque', 'pendant',
    'alors', 'puisque', 'bien', 'si', 'où', 'tandis',
  ],
  'numbers': [
    'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix', 'onze', 'douze',
    'vingt', 'trente', 'quarante', 'cinquante', 'soixante', 'cent', 'cents', 'mille', 'million',
    'millions', 'milliard', 'milliards', 'moitié', 'double', 'triple',
  ],
  'units': [
    'pour cent', 'pourcent', 'million', 'millions', 'milliard', 'milliards', 'mille',
    'euros', 'dollars', 'fois', 'minutes', 'heures', 'jours', 'semaines', 'mois', 'ans',
    'années', 'secondes',
  ],
};

const _frenchTightenings = {
  'en fait': '',
  'du coup': '',
  'franchement': '',
  'il faut savoir que': '',
  'afin de': 'pour',
  'dans le but de': 'pour',
  'à l\'heure actuelle': "aujourd'hui",
  'en ce qui concerne': 'pour',
  'est en mesure de': 'peut',
  'sont en mesure de': 'peuvent',
  'au jour d\'aujourd\'hui': "aujourd'hui",
  'il est important de noter que': '',
};

const _arabic = {
  'steps': [
    'أولاً', 'أولا', 'ثانياً', 'ثانيا', 'ثالثاً', 'ثالثا', 'ثم', 'بعد ذلك', 'بعدها', 'بعدين',
    'أخيراً', 'أخيرا', 'وأخيراً', 'الخطوة', 'خطوة', 'الآن', 'في البداية', 'في النهاية',
  ],
  'actions': [
    'اضغط', 'اضغطي', 'انقر', 'انقري', 'افتح', 'افتحي', 'أغلق', 'اختر', 'اختاري', 'حدد',
    'اكتب', 'اكتبي', 'أدخل', 'اسحب', 'شغل', 'ثبت', 'احفظ', 'انسخ', 'الصق', 'أضف', 'أضيفي',
    'احذف', 'أنشئ', 'اذهب', 'روح', 'قم', 'تحقق', 'حمل', 'أعد', 'ضع', 'ضعي', 'امزج', 'اخلط',
    'قطع', 'صب', 'قس', 'أدرج', 'وصل', 'انتقل', 'املأ', 'غير',
  ],
  'emphasis': [
    'أبداً', 'أبدا', 'دائماً', 'دائما', 'كل', 'فقط', 'أفضل', 'أهم', 'أكبر', 'أسرع', 'جميع',
    'يجب', 'مهم', 'ضروري', 'أساسي', 'سر', 'سهل', 'بسيط', 'مجاني', 'مجانا', 'جديد', 'حقاً',
    'حقا', 'اليوم', 'لماذا', 'خطأ', 'مشكلة', 'تماماً', 'تماما', 'أكثر', 'أقل', 'ضعف', 'نصف',
    'لا شيء', 'الجميع',
  ],
  'conclusion': [
    'لذلك', 'لذا', 'إذن', 'باختصار', 'تخيل', 'تخيلوا', 'تذكر', 'تذكروا', 'الخلاصة',
    'والخلاصة', 'في النهاية', 'ولهذا', 'لهذا',
  ],
  'cta': [
    'اشترك', 'اشتركوا', 'تابع', 'تابعوا', 'شارك', 'شاركوا', 'علق', 'علقوا', 'الرابط', 'جرب',
    'جربوا', 'انضم', 'انضموا', 'احفظ', 'حمل', 'احجز',
  ],
  'conjunctions': [
    'لكن', 'ولكن', 'أو', 'لأن', 'الذي', 'التي', 'الذين', 'عندما', 'بينما', 'حيث', 'حتى', 'إذا',
    'لو', 'كما', 'ثم',
  ],
  'numbers': [
    'واحد', 'اثنان', 'اثنين', 'ثلاثة', 'ثلاث', 'أربعة', 'أربع', 'خمسة', 'خمس', 'ستة', 'ست',
    'سبعة', 'سبع', 'ثمانية', 'تسعة', 'عشرة', 'عشر', 'عشرين', 'عشرون', 'مئة', 'مائة', 'ألف',
    'آلاف', 'مليون', 'ملايين', 'مليار', 'نصف', 'ضعف',
  ],
  'units': [
    'بالمئة', 'بالمائة', 'في المئة', 'في المائة', 'مليون', 'مليار', 'ألف', 'دولار',
    'يورو', 'درهم', 'دينار', 'ريال', 'مرة', 'مرات', 'دقيقة', 'دقائق', 'ساعة', 'ساعات', 'يوم',
    'أيام', 'أسبوع', 'شهر', 'أشهر', 'سنة', 'سنوات', 'ثانية',
  ],
};

const _arabicTightenings = {
  'في الحقيقة': '',
  'في الواقع': '',
  'بصراحة': '',
  'يعني': '',
  'من أجل أن': 'لكي',
  'بالإضافة إلى ذلك': 'كما',
  'في الوقت الحالي': 'الآن',
  'من الجدير بالذكر أن': '',
};

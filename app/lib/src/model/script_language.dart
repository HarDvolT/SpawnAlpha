/// The languages a script can be written in.
enum ScriptLanguage {
  en('English', isRtl: false),
  fr('Français', isRtl: false),
  ar('العربية', isRtl: true);

  const ScriptLanguage(this.label, {required this.isRtl});

  /// The language's name, written in that language.
  final String label;
  final bool isRtl;

  static ScriptLanguage fromName(String? name) =>
      ScriptLanguage.values.firstWhere((l) => l.name == name, orElse: () => ScriptLanguage.en);

  static final _arabicLetter = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
  static final _latinLetter = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿŒœ]');
  static final _frenchAccent = RegExp(r'[àâæçéèêëîïôœùûüÿÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸ]');
  static final _frenchWord = RegExp(
    r"\b(le|la|les|des|du|une|est|et|pour|avec|vous|nous|dans|pas|qui|que|sur|c'est|d'|l')\b",
    caseSensitive: false,
  );
  static final _englishWord = RegExp(
    r"\b(the|and|you|your|is|are|to|of|with|this|that|for|it's|we|in|on)\b",
    caseSensitive: false,
  );

  /// Guesses the language of [text] from its letters and common words.
  /// Returns null when there is too little text to tell.
  static ScriptLanguage? detect(String text) {
    final arabic = _arabicLetter.allMatches(text).length;
    final latin = _latinLetter.allMatches(text).length;
    if (arabic + latin < 12) return null;
    if (arabic > latin) return ScriptLanguage.ar;
    final french = _frenchWord.allMatches(text).length + _frenchAccent.allMatches(text).length;
    final english = _englishWord.allMatches(text).length;
    return french > english ? ScriptLanguage.fr : ScriptLanguage.en;
  }
}

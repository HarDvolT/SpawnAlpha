/// The coaching style chosen for a script. It sets how the script is marked
/// up and the pace the prompter aims for.
enum CoachingStyle {
  shortSocial(
    label: 'Short social video',
    goal: 'Grab attention in the first seconds and keep the energy high',
    minWpm: 160,
    maxWpm: 190,
    shortPause: Duration(milliseconds: 350),
    longPause: Duration(milliseconds: 700),
    wordsPerBreath: 14,
  ),
  presentation(
    label: 'Presentation',
    goal: 'Sound confident and persuasive',
    minWpm: 130,
    maxWpm: 150,
    shortPause: Duration(milliseconds: 500),
    longPause: Duration(milliseconds: 1200),
    wordsPerBreath: 12,
  ),
  tutorial(
    label: 'Tutorial',
    goal: 'Be clear and easy to follow',
    minWpm: 120,
    maxWpm: 140,
    shortPause: Duration(milliseconds: 450),
    longPause: Duration(milliseconds: 1000),
    wordsPerBreath: 12,
  );

  const CoachingStyle({
    required this.label,
    required this.goal,
    required this.minWpm,
    required this.maxWpm,
    required this.shortPause,
    required this.longPause,
    required this.wordsPerBreath,
  });

  final String label;
  final String goal;

  /// The words-per-minute range a good delivery stays inside.
  final int minWpm;
  final int maxWpm;

  final Duration shortPause;
  final Duration longPause;

  /// Roughly how many words a speaker can say comfortably before the
  /// markup should offer a breath.
  final int wordsPerBreath;

  int get targetWpm => (minWpm + maxWpm) ~/ 2;

  static CoachingStyle fromName(String? name) => CoachingStyle.values
      .firstWhere((s) => s.name == name, orElse: () => CoachingStyle.presentation);
}

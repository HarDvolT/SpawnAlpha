/// What a sound check heard: the speaker read a line while the chosen
/// microphone listened (docs/design/recording.md, "Setting up a take").
enum SoundVerdict {
  /// A good speaking level.
  heard,

  /// Something, but too quiet to be the speaker at a normal distance.
  quiet,

  /// Nothing: the wrong microphone, a muted one, or access blocked.
  silent,
}

abstract final class SoundCheck {
  /// How long the check listens while the speaker reads a line.
  static const listenFor = Duration(milliseconds: 2500);

  /// Speech at arm's length reaches about -30 dBFS RMS on a working
  /// microphone; a room with nobody talking stays below -60.
  static const heardDb = -45.0;
  static const quietDb = -62.0;

  static SoundVerdict judge(double loudestRmsDb) => loudestRmsDb >= heardDb
      ? SoundVerdict.heard
      : loudestRmsDb >= quietDb
          ? SoundVerdict.quiet
          : SoundVerdict.silent;
}

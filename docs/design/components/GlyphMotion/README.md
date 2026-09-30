# GlyphMotion

The signature motion of each cue glyph: the second half of every cue's shape.

- **Use** wherever a cue glyph arrives, is pressed, or is reached by the take. The motions are defined once as `.sa-sig-*` classes, and in Flutter as one `CueMotion` per cue.
- **The seven motions:**
  - **Grow** for Stress;
  - **Tap** for Pause;
  - **Hold** for Long pause;
  - **Flow** for Breathe;
  - **Sink** for Slow down;
  - **Dart** for Speed up;
  - **Spark** for Lift energy.

  Each one acts out what the cue asks of the voice.
- **Arrival:** every glyph arrives with the shared `sa-arrive` entrance on `spring-snappy`, before its signature.
- **Playback:** signatures play **once** per trigger. Only this legend loops them.
- **Reduced motion:** no signatures play. Arrivals become fades.
- **Don't** give two cues the same motion, or use a signature motion for anything that isn't its cue.

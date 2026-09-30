# Countdown

Three beats before a take starts. The numerals land wide and settle. At "go" the ring collapses into the `stage-rec` tally, which flies into the HUD or bottom bar.

- **Use** before every take, in every mode:
  - over the camera preview;
  - or centred on the recorded display, hidden from capture, when recording the screen.
- **Consumer provides** the number of beats (3 by default; 0 turns it off in settings) and where the tally lands.
- **The numeral** is the `countdown` style: the display face at weight 900, tabular, in `stage-text`, on a translucent black disc. A `stage-text` ring sweeps once per `dur-beat`.
- **Motion:**
  - Each numeral arrives at width 150 and scale 1.35, and settles to width 100 and scale 1 on `spring-pop`.
  - At "go" the tally flies to its place.
  - On phones each beat gives a light haptic tick, and "go" a stronger one.
  - Reduced motion swaps numerals without scaling, and steps the ring in quarters.
- **Cancel:** Space, or a tap on Cancel, stops it at any beat, and nothing is recorded.
- **Don't** play a sound: the microphone may already be open.

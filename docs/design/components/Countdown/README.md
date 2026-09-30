# Countdown

Three beats before a take starts. At "go", the ring collapses into the `stage-rec` tally, which settles into the HUD or bottom bar.

- **Use** before every take, in every mode: over the camera preview, or centred on the recorded display (and hidden from capture) when recording the screen.
- **Consumer provides** the number of beats (3 by default; 0 turns it off in settings) and where the tally lands.
- The number is `stage-text` at 76px, weight 700, tabular, on a translucent black disc. A `stage-text` ring sweeps once per `dur-beat`.
- Motion: each number arrives at 1.15× and settles over 200ms. At "go" the tally flies to its place over `dur-base`. On phones each beat gives a light haptic tick and "go" a stronger one. Reduced motion swaps numbers without scaling and steps the ring in quarters.
- Space, or a tap on Cancel, stops it at any beat and nothing is recorded.
- **Don't** play a sound: the microphone may already be open.

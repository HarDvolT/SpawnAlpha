# RecordScreen

The phone camera screen, end to end: set-up, countdown, the take under the lens, and the Director's Cut toast when you stop.

- **Use** as the reference for Camera mode on Android and iOS.
- **Consumer provides** the camera preview, the prompter controller, the take number and the handlers.
- **Prompter:**
  - A glass panel right under the lens, `radius-lg`, three lines of `stage-s`.
  - The reading line is on the first line, with a caret. The next lines fade under a gradient.
  - The glass blurs the feed but never hides the speaker.
- **Under the panel:** glass pills for the timecode (tally and signal-face timer) and the mode (Camera, Screen, Both).
- **Bottom:**
  - the take number in the display face (T3);
  - the record button (RecordButton) in the centre;
  - the camera flip.
- **Countdown:** full-screen numerals in the display face, landing wide (see Countdown).
- **When you stop:** the record button shows saving, then a glass toast rises with "Director's Cut ready", the duration change and a Review link.
- **Don't** float anything else over the preview, or put controls between the lens and the script.

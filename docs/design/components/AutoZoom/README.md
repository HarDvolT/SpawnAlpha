# AutoZoom

Screen recordings, edited from telemetry: zooms that start before the click, a smooth cursor, directional motion blur, click ripples, keystroke badges and a backdrop.

- **Use** in the Director's Cut for Screen and Screen + camera takes, and as the effect chips on the recording set-up screen.
- **Consumer provides** the take's telemetry (cursor at 60 Hz, clicks, key-burst times, modifier chords, window rects) and the effect switches.
- **Zooms:**
  - A cluster of two or more events within 1.3s and 30% of the screen gets one zoom, to `zoom-default` (1.8×, never above `zoom-max`), on `spring-camera`.
  - Zooms start `zoom-lead` (300ms) before the first event and hold `zoom-hold` (1.4s) after the last.
  - A lone click gets a ripple, not a zoom.
  - The view is clamped to the recorded screen.
- **Cursor:**
  - It is smoothed with a 70ms follow and drawn at `cursor-scale` (1.5×).
  - It fades after `cursor-idle` (1.5s).
  - It has a soft amber halo, and `ripple` rings on click.
- **Motion blur:**
  - Blur is directional along the camera's movement and proportional to its speed, capped at `blur-max`.
  - A zoom adds only a little.
  - A still frame is never blurred.
- **Keystrokes:** glass keycaps for modifier chords only (Ctrl+S). Letters are never shown or logged.
- **Backdrop:** the screen is inset 6% on a wallpaper, with rounded corners and a deep shadow.
- **Timeline:** zoom segments in `cue` amber, click dots in `ink`, and shortcuts in `cue-pause`.
- **Don't** zoom on every click. **Don't** blur text that is being read (a zoom holding still is never blurred). **Don't** show typed text.

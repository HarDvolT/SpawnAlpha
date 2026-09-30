# RecordingHud

The floating glass pill that controls a desktop recording.

- **Use** in Screen and Screen + camera modes on desktop, at the bottom centre of the recorded display. Camera mode uses the bottom bar instead.
- **Contents:**
  - tally and timer;
  - Pause and Stop;
  - the microphone meter;
  - prompter show or hide, Companion, and Lock.
- **Consumer provides** the recording state, elapsed time, microphone level and the handlers. The window hosting it must be:
  - always on top;
  - excluded from capture (`WDA_EXCLUDEFROMCAPTURE` on Windows);
  - click-through everywhere except its buttons.
- **Surface:** glass (`stage-glass`, 16px blur, `stage-glass-edge`), `radius-lg`, `shadow-float`.
- **Type and colour:** the timer is `timecode` in the signal face, in `stage-text`. Stop's icon is `stage-rec`.
- **Tally:** steady `stage-rec` with a soft glow. It never blinks, and becomes a hollow ring while paused.
- **Meter:** the microphone meter is a 40 × 3px bar in `stage-chrome-text` that turns `warning` near clipping.
- **Lock** makes the Prompter window click-through, and the global shortcuts (Ctrl+Shift+Space and friends) keep working. **Companion** switches the Prompter window to the cursor companion. With a camera on, it starts docked and warns before following.
- **Don't** put the script, the countdown or notifications in the HUD.

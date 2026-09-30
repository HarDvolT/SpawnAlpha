# RecordingHud

The floating pill that controls a desktop recording: tally and timer, Pause, Stop, microphone meter, prompter show or hide, and Lock.

- **Use** in Screen and Screen + camera modes on desktop, at the bottom centre of the recorded display. Camera mode uses the bottom bar instead.
- **Consumer provides** the recording state, elapsed time, microphone level and the handlers. The window hosting it must be always on top, excluded from capture (`WDA_EXCLUDEFROMCAPTURE` on Windows) and click-through everywhere except its buttons.
- `stage-chrome` fill, `stage-chrome-text` icons, `radius-lg`, `shadow-float`. The timer is `timecode` in `stage-text`; Stop's icon is `stage-rec`.
- The tally is steady `stage-rec`. In the HUD only, it may breathe between 100% and 70% opacity over 2s. It becomes a hollow ring while paused.
- The microphone meter is a 40 × 3px bar in `stage-chrome-text` that turns `warning` near clipping.
- Lock makes the Prompter window click-through; the global shortcuts (Ctrl+Shift+Space and friends) keep working.
- **Don't** put the script, the countdown or notifications in the HUD.

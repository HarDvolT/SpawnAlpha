# Motion

Motion in SpawnAlpha has one job on the Stage, to carry timing, and one in the Studio, to show cause and effect. Everything else stays still.

## Rules

- **On the Stage, only timing moves**: the scroll, the hold badge and the countdown. Cues never animate as they pass the reading line. Nothing blinks.
- **In the Studio, motion answers an action**: a sheet rises because a word was tapped; cues draw in because the markup ran. Nothing moves on its own.
- Use the duration tokens (`dur-instant` to `dur-slow`) with `ease-standard` for things arriving, `ease-exit` for things leaving and `ease-press` for presses and morphs. Timing that belongs to the delivery (holds, beats) comes from the delivery timeline, not from these tokens.
- Animate opacity and transform only, so it stays smooth on phones while the camera runs.

## The moments

### 1. The director's pass (markup arrives)
When a markup pass returns, its cues draw into the script **in reading order**, like a pen moving down the page. Each cue fades from 0 to 50% opacity (its pending strength) over `dur-quick` with `ease-standard`; glyphs also scale from 0.6 to 1. Cues start `dur-stagger` apart, and the whole pass is capped at 800ms: with many cues, the stagger shrinks. The text itself never moves.

### 2. Accepting a cue
A pending cue goes to full opacity over `dur-quick` and settles from scale 0.96 to 1, like ink drying. **Accept all** runs the same settle across the script in reading order, capped at 400ms. Removing a cue fades it out over `dur-quick` with `ease-exit`.

### 3. The word sheet
Tapping a word tints it (`tint-select`) at once, and the sheet rises from the bottom over `dur-base` (`ease-standard`). On desktop the sheet is a popover under the word that scales from 0.96 to 1. Closing it reverses the motion over `dur-quick` with `ease-exit`.

### 4. Going on stage
Opening the prompter or the recorder takes `dur-slow`. The Studio chrome fades out (`ease-exit`), the ground dims to `stage`, and the script column eases from the editor's position and size to its stage position and size (`ease-standard`). The reading line draws in from the leading edge over `dur-base` at the end. Coming back reverses it.

### 5. The scroll
Within a line the scroll moves at constant speed (`ease-scroll`), reaching the next line as the line's last word ends. During a hold it stops dead: the stillness is the cue. Speed changes blend over 300ms. In Voice mode the scroll glides to the recognised word over `dur-base`.

### 6. The hold badge
When the scroll reaches a pause or breath, the badge fades and rises 4px into place over `dur-quick`. Its ring empties **linearly over exactly the hold's length**, so the speaker can see how long to wait. It leaves over `dur-quick` as the next word starts.
- Pause: `stage-pause` ring.
- Long pause: `stage-pause`, the badge a size larger.
- Breathe: `stage-breath`, and the badge swells from scale 1 to 1.06 and back over the hold, like an inhale.

### 7. The countdown
Three beats of `dur-beat`. Each number arrives at scale 1.15 and settles to 1 over 200ms while a ring sweeps once around it over the beat. At "go", the ring collapses into the `rec` tally dot and the dot moves to its place in the HUD or bottom bar over `dur-base`. On phones, each beat gives a light haptic tick, and "go" a stronger one. Space or a tap on Cancel stops it at any beat.

### 8. The record button
Idle, a filled `rec` disc inside a ring. On press it squeezes to 0.92 over `dur-instant`. When recording starts, the disc morphs into a rounded square (`radius-sm`) over `dur-base` (`ease-press`). While saving, the ring turns into a spinner.

### 9. The tally
The REC dot is steady while recording: a blinking red light pulls the eye. It becomes a hollow ring while paused. In the HUD only, the dot may breathe between 100% and 70% opacity over 2 seconds, so a speaker glancing at a second screen can see the take is live.

### 10. The take saved sheet
It rises over `dur-base`. The duration counts up from 0 to the take's length over 400ms, once.

## Reduced motion

When the system asks for reduced motion:
- Replace every scale and slide with a plain fade over `dur-quick`.
- The director's pass shows every cue at once; Accept all switches at once.
- Countdown numbers swap without scaling; the ring still sweeps (it carries time), as a stepped arc.
- The breathe swell and the HUD breathing stop.
- The prompter scroll and the hold badge's emptying ring stay, because they are the function.

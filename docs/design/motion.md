# Motion

Motion in SpawnAlpha has three jobs:
- **On the Stage** it carries timing and tells you what to do with your voice.
- **In the Studio** it shows cause and effect.
- **In the Cut** it directs the viewer's eye.

If a motion does none of these, it does not ship.

## Rules

- **Springs for anything a person touches or the take drives.** Use the `spring` family (mass, stiffness, damping, as Flutter's `SpringDescription` takes them). Fixed durations (`dur-*`) are for fades and colour changes only.

  | Spring | Values | Use |
  |---|---|---|
  | `spring-snappy` | 1 520 36 | Presses, toggles, chips, glyphs arriving |
  | `spring-smooth` | 1 260 32 | Sheets, cards, shared-element moves (no overshoot) |
  | `spring-pop` | 1 380 18 | The only bouncy spring: stressed words popping |
  | `spring-camera` | 1 90 19 | Zooms and pans in the Cut |
  | `spring-follow` | 1 140 24 | The cursor companion |

- **Never reflow text to animate it.**
  - Words may paint (colour, opacity, marker swipe) and may scale inside room reserved for them up front.
  - A line never re-wraps because something moved.
  - Animate transform, opacity and paint only, so frames stay smooth on phones while the camera runs.
- **On the Stage, motion is subtle and earned.**
  - The scroll carries time.
  - A glyph plays its signature when the take reaches it.
  - A stressed word grows as it nears the reading line.
  - Nothing blinks, bounces on its own, or shows a toast while you are live.
- **In the Studio, motion answers an action.** A sheet rises because a word was tapped, and cues draw in because the markup ran.
- **In the Cut, motion is bold.** Captions pop, zooms glide in and blur follows speed. The viewer is not reading a prompter, so this is where the big animation lives.

## Signature motions

Every cue has one motion. It plays **once**, whenever the cue:
- arrives, during the director's pass;
- is pressed, in the editor;
- is reached by the take, on the Stage.

Only the legend (GlyphMotion) loops them.

| Cue | Motion | What it looks like | Length |
|---|---|---|---|
| Stress | **Grow** | Swells to 1.18 and settles at 1 on `spring-pop` | ~500ms |
| Pause | **Tap** | The bars press down to 62% height and spring back, like a baton tap | ~300ms |
| Long pause | **Hold** | The disc swells 8% and a ring expands off it and fades | ~1s |
| Breathe | **Flow** | The air lines drift 3px forward and brighten, then settle | ~1.2s |
| Slow down | **Sink** | The arrows settle 4px lower and rise back | ~900ms |
| Speed up | **Dart** | The arrows shoot up and out, then drop back in from below | ~500ms |
| Lift energy | **Spark** | The bolt flashes to 1.28, tilts, glows, and settles | ~400ms |

Glyphs **arrive** with one shared entrance, `sa-arrive`: from scale 0.3 and 6px low to rest, on `spring-snappy`. A pending glyph arrives at 50% opacity.

## The moments

### 1. The director's pass (markup arrives)
- When a markup pass returns, its marks land **in reading order**, like a pen moving down the page:
  - marker swipes draw across stressed words in the reading direction (420ms);
  - tints paint in;
  - glyphs arrive, then play their signature.
- Marks start about 70ms apart; with many marks the stagger shrinks so the whole pass takes at most 1.2s.
- Each director's note writes on in the margin 260ms after its mark. It is revealed in the reading direction over 700ms, like a pencil stroke.
- The text itself never moves.

### 2. Accepting cues
- A pending cue paints to full strength: the marker goes from 34% to 72% and glyphs go to 100%.
- **Accept all** runs across the script in reading order, capped at 400ms.
- Removing a cue fades it out over `dur-quick` with `ease-exit`. A marker swipe retracts against the reading direction.

### 3. The word sheet
- Tapping a word tints it (`tint-select`) at once, and the sheet rises on `spring-smooth`.
- On desktop it is a popover under the word that scales from 0.96.
- Closing it reverses the motion over `dur-quick`.

### 4. Going on stage
- Opening the prompter or the recorder is a shared-element move on `spring-smooth`:
  - the Studio chrome fades out (`ease-exit`);
  - the ground dims to `stage`;
  - the script column travels from its editor position to its stage position.
- The reading line draws in from the leading edge at the end.
- Coming back reverses it.

### 5. The kinetic prompter
The text stands still during holds. The stillness is the cue. How the text moves between holds is the speaker's choice (Line step, Smooth or One phrase; see Prompter).

On top of the motion, and only when Kinetic is on (the default):
- **Liveness.** Each word has a liveness from 0 to 1: a smoothstep over its distance to the reading line, reaching 0 about 1.8 lines ahead.
- **Lines ahead.** Text more than three lines ahead sits back at reduced opacity.
- **Stress** grows toward 1.08 as it nears the line, into room reserved beside it. As it is spoken it **punches** (to 1.3 and back on `spring-pop`, with a glow) while an underline **slams** across it and fades.
- **Energy runs** glow while live, and each word **hops** as it is spoken.
- **Faster runs** lean forward (skew −9°) while speed lines stream through their tint.
- **Slower runs** float gently down and up on a 2.6s cycle, and the tint breathes.
- **Gap glyphs** play their signature (a quick "hit" at 1.5×) as the hold starts. During a pause the next few words **wait** at 32% until it ends.

Kinetic can be switched to **Still**, which keeps only the motion, the guide and the holds. Reduced motion forces Still.

### 5b. The guide
- **The bouncing dot** arcs from word to word and lands on each as it starts, squashing a little. It **becomes each cue** as it reaches it:
  - it climbs and slams onto a stressed word, growing and turning amber, with a shockwave and a strike across the word;
  - it springs into the pause sign on a pause glyph while a timer ring drains;
  - it inhales and exhales on a breath;
  - it announces each run with the run's glyph, then turns heavy with echoes (slower), light with streaks (faster), or pulsing with sparks (energy);
  - it grows a microphone and bobs while voice pace waits.

  At a line return, it fades from the last word (or gap glyph) to the next line's first word without crossing the text. Cue timing and text layout stay fixed; reduced motion jumps directly with no fade. Full rules in Prompter, "The bouncing dot".
- **The underline** fills across the current word in the reading direction over the word's time.
- **The spotlight** fades words in and out over `dur-quick`.
- Reduced motion: the dot jumps without arcs or effects, and the underline appears full.

### 6. The hold badge
- The badge fades and rises into place on `spring-snappy` as the hold starts.
- Its ring empties **linearly over exactly the hold's length**.
- Breathe swells the badge from 1 to 1.06 and back over the hold, like an inhale.

### 7. The countdown
- There are three beats of `dur-beat`.
- Each numeral, in the display face at weight 900, **lands wide and settles**: from width 150 and scale 1.35 to width 100 and scale 1 on `spring-pop`, while a ring sweeps once around it.
- At "go" the ring collapses into the tally dot, which flies to its place in the HUD.
- On phones each beat gives a light haptic tick, and "go" a stronger one.

### 8. The record button
- The button squeezes to 0.9 on press.
- When recording starts, the disc morphs to a rounded square on an overshooting spring (320ms).
- While saving, the ring becomes a spinner, which is replaced by the finish toast.

### 9. The tally
- The tally is steady while recording and a hollow ring while paused.
- In the HUD it has a soft glow, and never blinks.

### 10. The cursor companion
- The companion trails the pointer on `spring-follow`, on the side the pointer is **not** heading towards, and flips away from screen edges.
- After 2s without movement it docks under the lens and widens to three lines. It re-attaches on the next move.
- With the camera on, it stays docked by default. If you turn following on (after the one-time warning), it follows, and it shows an "eyes to the lens" reminder under the header.

### 11. Finishing: the Director's Cut arrives
- When you stop, the finish screen rises on `spring-smooth` and the edit **plays out in front of you** instead of behind a spinner:
  1. dead air hatches in along the timeline;
  2. fillers flash red;
  3. the discarded retake greys out;
  4. then everything flagged **collapses** (800ms) and the timeline tightens.
- The duration rolls from the take's length to the cut's length. Its numerals narrow to width 70 while rolling and spring back to 100.
- The edit list fills in, item by item, as each pass completes. Zoom marks and the caption bar draw along the timeline last.
- Turning an item's switch off reverses just that change, and the duration rolls again.

### 12. Captions in the Cut
- **Cue captions:** words rise 10px and fade in as spoken. Stressed words pop from 0.55 to 1.22 to 1 on `spring-pop`, in amber, at width 125.
- **Punch captions:** one to three words at a time. Each chunk snaps in from 0.8 to 1.06 to 1, and a stressed word stands alone and larger.
- **Karaoke captions:** the whole line waits dimmed and fills word by word, with an amber underline sweeping each word over its spoken length.
- Phrases leave on the gap cue that ends them, with a 160ms fade.

### 13. Zooms, cursor and blur in the Cut
- **Zooms**:
  - Zooms move on `spring-camera` to `zoom-default` (1.8×).
  - They start `zoom-lead` (300ms) **before** the activity they frame, because the edit knows the future.
  - They hold `zoom-hold` (1.4s) after it ends.
  - A single isolated click gets a ripple, not a zoom. Zooming on every click makes viewers seasick.
  - Clusters of events pan instead of zooming out and back in.
- **The cursor** is replaced by a smoothed one:
  - it is an exponential follow with a 70ms time constant, which removes hand jitter;
  - it is drawn at `cursor-scale` (1.5×);
  - it fades out after `cursor-idle` (1.5s) of stillness.
- **Motion blur** is directional:
  - pans smear along their direction;
  - zooms add only a little;
  - it is proportional to camera speed, capped at `blur-max`, and zero whenever the frame is still.
- **Click ripples** are an amber ring growing to 4.4× and fading over 420ms, with a soft halo under the cursor.
- **Keystroke badges** are glass keycaps that rise on a spring for shortcuts. Individual letters are never shown.

## Haptics (phones)

- Light tick: each countdown beat, and accepting a cue.
- Medium: go, and stop.
- Success pattern: the Director's Cut ready.
- There are never haptics during a take apart from go and stop. A buzz would be picked up by the microphone.

## Reduced motion

When the system asks for reduced motion:
- Replace every scale, slide and spring overshoot with a plain fade over `dur-quick`.
- The director's pass shows every mark at once, and notes appear without the write-on.
- The kinetic prompter switches to Still. Signature motions don't play.
- Countdown numerals swap without scaling. The ring still sweeps, as a stepped arc, because it carries time.
- The companion jumps to its new place instead of trailing.
- The finish screen shows the finished timeline, with the duration already at its final value.
- The prompter scroll and the hold ring stay, because they are the function.

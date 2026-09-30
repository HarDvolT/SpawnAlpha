# Prompter

The prompter is the product's centre: a script in large type that scrolls at the pace the markup planned, holds at every pause and shows every cue as the speaker reaches it.

## Anatomy

From top to bottom, on `stage` (or on `stage-glass` over a camera preview):

1. **Read zone.** Everything above the reading line, faded to `read-fade` with a gradient toward the top. Spoken words use `stage-text-read`.
2. **Hold badge.** A pill just above the reading line that appears only while the scroll holds: PAUSE, LONG PAUSE or BREATHE, in the cue's colour, with a ring that empties over the length of the hold.
3. **Reading line.** A hairline in `stage-line` at `reading-line` (30% from the top by default, adjustable 20% to 45%), with a caret in the leading gutter. The line being spoken is centred on it as it starts, and drifts up through it as it is read.
4. **Script column.** `stage-text` in a Stage style, weight 500, never wider than `column-max` under a camera. Cues are drawn inline (see the cue vocabulary).
5. **Pace gutter.** The leading `gutter` (left in left-to-right scripts, right in Arabic) carries a 6px rounded bar beside every slower or faster run, in `stage-slower` or `stage-faster`.
6. **Control bar.** `stage-chrome` along the bottom. It holds:
   - back to start, and play or pause;
   - speed −/+, with the speed and words per minute in `meter`;
   - time left in `timecode`;
   - Timed/Manual, Kinetic/Still, text size and mirror.

   On phones it hides 3 seconds after playback starts and returns on a tap.

## How the scroll moves

- **Timed** (build step 1): each word gets `60 / wpm` seconds, weighted by its length. Slow-down runs stretch words ×1.25 and speed-up runs squeeze them ×0.8. After a word the scroll holds for its gap cue: the style's short or long pause, 350ms for a breath. Unmarked punctuation adds a natural beat: 500ms at a paragraph end, 250ms at a sentence end, 120ms at a comma.
- Within a line the scroll moves at a constant speed (`ease-scroll`) and reaches the next line exactly as the line's last word ends. During a hold it stands still. That stillness is the pause cue; the badge only names it.
- **Manual**: the speaker scrolls by drag, wheel or keys. The word under the reading line becomes the current word, so switching back to Timed continues from there. A drag or wheel during Timed playback pauses it.
- **Voice** (build step 3): the reading line follows speech recognition.
  - The scroll glides to the recognised word on `spring-smooth`.
  - A thin `stage-stress` underline glides under the word being heard, so the speaker sees the prompter listening.
  - If the speaker goes off script, it waits and the badge reads "Waiting for: <next words>".
  - It never jumps backwards on its own.
- Speed changes (the −/+ buttons, the arrow keys) blend over 300ms, never a jump. Speed runs from 0.5× to 2.0× in 0.1 steps, shown as "1.2× · 156 wpm".

## Cues on the stage

- Only accepted cues appear on the stage. If proposals are unreviewed when the speaker goes on stage, ask once: Accept all, or Leave them out.
- Stressed words are `stage-stress`, weight 700, 1.15× size. Energy runs are `stage-energy`. Pace runs carry a `stage-tint-slower` or `stage-tint-faster` tint and a gutter bar. Pause and breath glyphs sit in the gap after the word.
- With Kinetic on (the default), cues come alive as the reading line reaches them; see below. With Still, the hold badge is the only cue that moves.

## Kinetic text

The prompter should feel alive without ever making you lose your place. Kinetic text follows three hard rules:
1. **No reflow.** Line breaks are fixed when the script is laid out. Nothing that animates may change a line's width or wrap a word. Stressed words reserve their growing room (a 0.16em side margin) up front.
2. **Only near the reading line.** Each word has a liveness from 0 to 1: a smoothstep over its distance to the reading line, reaching 0 about 1.8 lines ahead. Effects scale with liveness, so the text you are about to say wakes up and everything else stays calm. Text more than three lines ahead sits back.
3. **Small on the Stage, big in the Cut.** The prompter's motion is a hint for your voice. The big pops belong to the captions viewers see.

| Cue | As it nears the line | When the take reaches it |
|---|---|---|
| Stress | grows toward 1.08× | pops once (to 1.16×, `spring-pop`) |
| Lift energy | a soft glow builds around the words | glow holds through the run |
| Speed up | thin speed lines drift through the tint | the gutter bar brightens |
| Slow down | the tint breathes slowly | the gutter bar glows |
| Pause, Long pause, Breathe | none | the glyph plays its signature (a quick hit) as the hold starts, and the badge appears |

**Still** mode keeps only the scroll and the holds. Reduced motion forces Still, and some speakers will prefer it. It is one tap in the control bar.

## Sizes and distance

| Style | Size | Use |
|---|---|---|
| `stage-s` | 32px | Over a phone camera preview; small desktop prompter window |
| `stage-m` | 44px | Default: a laptop at arm's length |
| `stage-l` | 60px | 1.5 to 3 m away, or teleprompter glass |
| `stage-xl` | 80px | Beyond 3 m or a large monitor |

The +/− size buttons step 4px between 24px and 96px. Arabic uses line height 1.6 at every size.

## Mirror

For beam-splitter teleprompter glass, Mirror flips the whole stage horizontally: text, cues, the gutter, badges. `stage` is true black because black is invisible on the glass. The control bar stays unmirrored and moves to a second screen or is hidden when a remote is connected.

## Keyboard (desktop)

| Key | Action |
|---|---|
| Space | Play or pause; in the recorder, start or stop the take |
| ↑ / ↓ | Faster or slower (Timed); one line up or down (Manual) |
| ← / → | Previous or next sentence |
| T | Switch Timed and Manual |
| Home | Back to the start |
| M | Mirror |
| + / − | Larger or smaller text |
| Esc | Leave the stage (asks first while recording) |

## The cursor companion (screen only)

For screen recordings, the prompter can ride beside the mouse, so your eyes never leave the work. For the placement rules, see Recording.
- **Shape:** a glass card, 300px wide, two lines of `stage-s`-sized text (16px on desktop). It has a tally, a state label (FOLLOWING, DOCKED) and a small hold ring.
- **Movement:**
  - It trails the pointer on `spring-follow`, 26px to the side and 22px below.
  - It sits on the side the pointer is **not** heading to, and flips away from screen edges and upward near the bottom.
  - After 2s without movement it docks under the lens, widens to three lines, and re-attaches on the next move.
- **Visibility:** it is always hidden from capture, like every prompter window.
- **Camera on:**
  - The card stays docked under the lens by default, because eyes that follow the mouse look shifty on camera.
  - **Follow anyway** turns following on after a one-time warning.
  - While following on camera, the card shows an "Eyes to the lens" reminder, and docks after 2s of stillness as usual.

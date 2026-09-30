# Prompter

The prompter is the product's centre: a script in large type that scrolls at the pace the markup planned, holds at every pause and shows every cue as the speaker reaches it.

## Anatomy

From top to bottom, on `stage` (or `stage-scrim` over a camera preview):

1. **Read zone.** Everything above the reading line, faded to `read-fade` with a gradient toward the top. Spoken words use `stage-text-read`.
2. **Hold badge.** A pill just above the reading line that appears only while the scroll holds: PAUSE, LONG PAUSE or BREATHE, in the cue's colour, with a ring that empties over the length of the hold.
3. **Reading line.** A hairline in `stage-line` at `reading-line` (30% from the top by default, adjustable 20% to 45%), with a caret in the leading gutter. The line being spoken is centred on it as it starts, and drifts up through it as it is read.
4. **Script column.** `stage-text` in a Stage style, weight 500, never wider than `column-max` under a camera. Cues are drawn inline (see the cue vocabulary).
5. **Pace gutter.** The leading `gutter` (left in left-to-right scripts, right in Arabic) carries a 6px rounded bar beside every slower or faster run, in `stage-slower` or `stage-faster`.
6. **Control bar.** `stage-chrome` along the bottom: back to start, play or pause, speed −/+ with the speed and words per minute in `meter`, time left in `timecode`, Timed/Manual, text size and mirror. On phones it hides 3 seconds after playback starts and returns on a tap.

## How the scroll moves

- **Timed** (build step 1): each word gets `60 / wpm` seconds, weighted by its length. Slow-down runs stretch words ×1.25 and speed-up runs squeeze them ×0.8. After a word the scroll holds for its gap cue: the style's short or long pause, 350ms for a breath. Unmarked punctuation adds a natural beat: 500ms at a paragraph end, 250ms at a sentence end, 120ms at a comma.
- Within a line the scroll moves at a constant speed (`ease-scroll`) and reaches the next line exactly as the line's last word ends. During a hold it stands still. That stillness is the pause cue; the badge only names it.
- **Manual**: the speaker scrolls by drag, wheel or keys. The word under the reading line becomes the current word, so switching back to Timed continues from there. A drag or wheel during Timed playback pauses it.
- **Voice** (build step 3): the reading line follows speech recognition. The scroll glides to the recognised word over `dur-base`; if the speaker goes off script, it waits and the badge reads "Waiting for: <next words>". It never jumps backwards on its own.
- Speed changes (the −/+ buttons, the arrow keys) blend over 300ms, never a jump. Speed runs from 0.5× to 2.0× in 0.1 steps, shown as "1.2× · 156 wpm".

## Cues on the stage

- Only accepted cues appear on the stage. If proposals are unreviewed when the speaker goes on stage, ask once: Accept all, or Leave them out.
- Stressed words are `stage-stress`, weight 700, 1.15× size. Energy runs are `stage-energy`. Pace runs carry a `stage-tint-slower` or `stage-tint-faster` tint and a gutter bar. Pause and breath glyphs sit in the gap after the word.
- Cues don't animate as the reading line passes them. The hold badge is the only cue that moves.

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

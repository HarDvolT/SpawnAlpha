# Prompter

The prompter is the product's centre: a script in large type that scrolls at the pace the markup planned, holds at every pause and shows every cue as the speaker reaches it.

## Anatomy

From top to bottom, on `stage` (or on `stage-glass` over a camera preview):

1. **Read zone.** Everything above the reading line, faded to `read-fade` with a gradient toward the top. Spoken words use `stage-text-read`.
2. **Hold badge.** A pill just above the reading line that appears only while the scroll holds: PAUSE, LONG PAUSE or BREATHE, in the cue's colour, with a ring that empties over the length of the hold.
3. **Reading line.** A hairline in `stage-line` at `reading-line` (30% from the top by default, adjustable 20% to 45%), with a caret in the leading gutter. The line being spoken sits on it (Line step) or drifts up through it (Smooth). With Voice pace, the caret pulses while the prompter is waiting for the voice.
4. **Script column.** `stage-text` in a Stage style, weight 500, never wider than `column-max` under a camera. Cues are drawn inline (see the cue vocabulary).
5. **Pace gutter.** The leading `gutter` (left in left-to-right scripts, right in Arabic) carries a 6px rounded bar beside every slower or faster run, in `stage-slower` or `stage-faster`.
6. **Control bar.** `stage-chrome` along the bottom. It holds:
   - back to start, and play or pause;
   - speed −/+, with the speed and words per minute in `meter`;
   - time left in `timecode`;
   - Guide, Motion, Pace (Voice, Timed, Manual), Align (Left, Center, Right), Kinetic/Still, text size and mirror;
   - with Voice pace, the microphone's name and a level meter.

   On phones it hides 3 seconds after playback starts and returns on a tap.

## Three choices: guide, motion and pace

The speaker picks how the prompter leads them. These are settings, remembered per device, and they can be changed on the stage without stopping.

| Choice | Options | Default approved 2026-10-05 |
|---|---|---|
| **Guide**: which word to say now | Dot, Underline, Spotlight, Off | Dot |
| **Motion**: how the text moves | Line step, Smooth, One phrase | One phrase |
| **Pace**: what drives the timeline | Voice, Timed, Manual | Voice when a microphone works, else Timed |
| **Cues** | Kinetic, Still | Kinetic |
| **Align**: where lines sit in the script column | Left, Center, Right | Center |

The owner tried the choices and approved these defaults (see `docs/status.md`). Saved
choices continue to win. Older settings with no motion or alignment now start with
One phrase and Center; explicit automatic alignment still follows reading direction.

Alignment is a physical position, separate from reading direction: Arabic stays right to
left even when aligned left or centred. A chosen alignment applies to practice and recording,
including One phrase, and is saved per device. Changing it remeasures word and cue anchors
immediately without moving the playback position or changing line breaks. The controls use
the existing Stage segmented choices. The desktop recording rail offers the same Align row.

## Pace: what drives the timeline

- **Timed:** each word gets `60 / wpm` seconds, weighted by its length. Slow-down runs stretch words ×1.25 and speed-up runs squeeze them ×0.8. After a word the timeline holds for its gap cue: the style's short or long pause, 350ms for a breath. Unmarked punctuation adds a natural beat: 500ms at a paragraph end, 250ms at a sentence end, 120ms at a comma.
- **Voice** (level-based, from build step 1): the same timeline, but it moves only while the microphone hears speech.
  - Voice activity: an adaptive noise floor, speech at 12 dB above it (at least −50 dBFS), 60ms to start and 350ms of quiet to stop.
  - Planned holds still run out in silence, because the silence is the cue. After a hold, the prompter waits for the voice on the next word, and the guide shows it is waiting ("Waiting for your voice").
- **Voice following** (build step 3): speech recognition replaces the level. The guide jumps to the recognised word, it never goes backwards on its own, and off-script speech makes it wait.
- **Manual:** the speaker scrolls by drag, wheel or keys. The word under the reading line becomes the current word, so switching back continues from there. A drag or wheel during playback pauses it.
- Speed changes (the −/+ buttons, the arrow keys) blend over 300ms, never a jump. Speed runs from 0.5× to 2.0× in 0.1 steps, shown as "1.2× · 156 wpm".

## Motion: how the text moves

- **Line step**: the current line sits on the reading line and stays there while it is read. When the next line starts, the text glides up one line (an exponential glide, time constant 90ms). Your eyes never chase moving words.
- **Smooth:** the classic prompter. The text moves at constant speed within a line (`ease-scroll`) and reaches the next line as its last word ends. It stands still during a hold.
- **One phrase:** only the phrase being spoken, set 1.25× larger and centred (or in the saved alignment), sitting on the reading line until the next phrase starts, with the next phrase dimmed underneath and everything else hidden. With Dot or Underline, the entire current phrase stays bright as the guide moves: do not dim its earlier words. Spotlight retains its explicit word focus. Keep the text hidden during initial measurement or a layout change so the full script never flashes at full brightness. A phrase ends at a gap cue, at the end of a sentence or line, at a clause end once it has four words, and at eight words at most. Best on a phone held close, or for short videos. Cue timing stays the same.
- In every motion the text stands still during a hold. That stillness is the pause cue; the badge and the guide only name it.

## The guide: which word to say now

The guide marks the current word. It is always one mark, never two, and it follows the timeline exactly.

- **Dot** (default): a small ball that bounces from word to word, and acts out each cue. The rules are below.
- **Underline:** a bar under the current word that fills across it in the reading direction as the word is spoken. Words already said on the line dim to `stage-text-read`.
- **Spotlight:** the current word at full strength, the next word at 70%, everything else on the line at 32%. The calmest guide; good for experienced speakers.
- **Off:** only the reading line. For speakers who read ahead and find any mark distracting.

### The bouncing dot

The dot **becomes each cue** as it reaches it: it grows, takes the cue's colour, shows the cue's glyph inside itself and moves the way the speaker should. Between cues it is a small white ball (`stage-text`), so its colour and size always mean something.

| Moment | What the dot does | What it tells the speaker |
|---|---|---|
| A word starts | Lands on the word (just above it, a third in from the leading edge) with a small squash, then arcs to the next word so it arrives as that word starts. | say this word now |
| Into a stressed word | Climbs higher (0.95em), then drops hard, turning `stage-stress` and growing to 1.8×. It lands with a hard squash, a shockwave, and an amber **strike** drawn across the word. It settles to 1.2× while the word lasts. | hit this word |
| A pause or long pause | Drops onto the pause glyph and **grows into the pause sign**: a `stage-pause` disc (2.3×, long pause 2.9×) with the pause bars inside, springing in. A **timer ring** around it drains over exactly the hold. It shrinks back and hops on in the last 160ms when the next word is on the same line; a line return uses the fade below. | stop until the ring runs out |
| A breath | Lands on the breath glyph and **inhales**: it swells to 2.6× in `stage-breath` with the breath glyph inside, then exhales back over the hold. | breathe in, then go |
| A slower run opens | Grows for a moment with the slow chevrons inside, in `stage-slower`. | slow down from here |
| In a slower run | Heavy: 1.3×, low long arcs (0.3em), with three fading **echoes** behind it, like slow motion. | keep it slow |
| A faster run opens | Grows for a moment with the fast chevrons inside, in `stage-faster`. | speed up from here |
| In a faster run | Light: 0.8×, short skips (0.18em), stretched along its path, with **streaks** behind it. | keep it quick |
| An energy run opens | Grows for a moment with the bolt inside, in `stage-energy`. | lift your energy |
| In an energy run | Pulses three times a second (up to 1.25× plus the beat), bouncy arcs (0.7em), throwing **sparks**. | stay up |
| A new line | Holds above the last word, briefly fades out there, then fades in above the next line's first word as that word starts. No diagonal return across the text. The fade on each side uses at most the 160ms hop time, capped at a quarter of the spoken word; after a gap, fade out on its glyph in the last 160ms of the hold. Trails never join different lines. | start reading the next line |
| Voice pace, waiting | Grows to 1.9× with a **microphone** inside, above the next word, and bobs until the voice starts. | your turn to speak |

- Resting size: about 0.4 of the type size (18px at 44px text), with a soft glow in its own colour. Signs are drawn in `stage` black on the grown disc, from the cue vocabulary's glyphs.
- Positions come from the laid-out word boxes, never from animated ones, so the kinetic effects never throw it off. It is painted above the read-zone fade, so it is never dimmed.
- Right to left: it travels right to left, lands a third in from the word's right edge, and the strike draws from the right.
- **Still** keeps the dot's size, colour, signs and timer ring, and drops the extras: shockwave, strike, echoes, streaks and sparks.
- **Reduced motion:** the dot jumps from word to word with no arcs, squash, pulsing or bobbing. It still shows each cue's colour, sign and full size, and the timer ring still drains.

## Cues on the stage

- Only accepted cues appear on the stage. If proposals are unreviewed when the speaker goes on stage, ask once: Accept all, or Leave them out.
- Stressed words are `stage-stress`, weight 700, 1.15× size. Energy runs are `stage-energy`. Pace runs carry a `stage-tint-slower` or `stage-tint-faster` tint and a gutter bar. Pause and breath glyphs sit in the gap after the word.
- With Kinetic on (the default), cues come alive as the reading line reaches them; see below. With Still, the hold badge is the only cue that moves.

## Kinetic text

The prompter should feel alive without ever making you lose your place. Kinetic text follows three hard rules:
1. **No reflow.** Line breaks are fixed when the script is laid out. Nothing that animates may change a line's width or wrap a word. Every effect is a transform, a colour, an opacity or a shadow drawn over the laid-out text. Stressed words reserve their growing room (0.2em of letter spacing on the spaces beside them) up front.
2. **Only near the reading line.** Each word has a liveness from 0 to 1: a smoothstep over its distance to the reading line, reaching 0 about 1.8 lines ahead. Effects scale with liveness, so the text you are about to say wakes up and everything else stays calm. Text more than three lines ahead sits back.
3. **Each effect acts out its cue.** An effect must make the speaker do the thing, not just decorate the word. If it could mean two cues, it is wrong.

| Cue | As it nears the line | When the take reaches it | What it tells the speaker |
|---|---|---|---|
| Stress | grows toward 1.08× | **punches**: up to 1.3× and back on `spring-pop`, with a glow, while an underline **slams** across it and fades | hit this word |
| Lift energy | a soft glow builds | each word **hops** as it is spoken, glow held through the run | lift, brighter |
| Speed up | thin speed lines drift through the tint | the words **lean forward** (skew −9°) and the lines stream | move on, faster |
| Slow down | the tint breathes | the words **float** gently down and up on a long cycle | slow, heavy |
| Pause, Long pause | none | the glyph **hits**, and the next words (up to six) **wait** at 32% until the hold ends | stop here |
| Breathe | none | the glyph hits, and the hold badge swells like an inhale | breathe in |

**Still** mode keeps only the motion, the guide and the holds. Reduced motion forces Still, and some speakers will prefer it. It is one tap in the control bar.

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
| V | Voice pace on or off |
| G | Next guide (Dot, Underline, Spotlight, Off) |
| K | Kinetic or Still |
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

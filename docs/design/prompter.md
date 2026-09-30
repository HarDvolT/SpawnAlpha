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
   - Guide, Motion, Pace (Voice, Timed, Manual), Kinetic/Still, text size and mirror;
   - with Voice pace, the microphone's name and a level meter.

   On phones it hides 3 seconds after playback starts and returns on a tap.

## Three choices: guide, motion and pace

The speaker picks how the prompter leads them. These are settings, remembered per device, and they can be changed on the stage without stopping.

| Choice | Options | Proposed default |
|---|---|---|
| **Guide**: which word to say now | Dot, Underline, Spotlight, Off | Dot |
| **Motion**: how the text moves | Line step, Smooth, One phrase | Line step |
| **Pace**: what drives the timeline | Voice, Timed, Manual | Voice when a microphone works, else Timed |
| **Cues** | Kinetic, Still | Kinetic |

The defaults are proposals until the owner has tried them (see `docs/status.md`).

## Pace: what drives the timeline

- **Timed:** each word gets `60 / wpm` seconds, weighted by its length. Slow-down runs stretch words ×1.25 and speed-up runs squeeze them ×0.8. After a word the timeline holds for its gap cue: the style's short or long pause, 350ms for a breath. Unmarked punctuation adds a natural beat: 500ms at a paragraph end, 250ms at a sentence end, 120ms at a comma.
- **Voice** (level-based, from build step 1): the same timeline, but it moves only while the microphone hears speech.
  - Voice activity: an adaptive noise floor, speech at 12 dB above it (at least −50 dBFS), 60ms to start and 350ms of quiet to stop.
  - Planned holds still run out in silence, because the silence is the cue. After a hold, the prompter waits for the voice on the next word, and the guide shows it is waiting ("Waiting for your voice").
- **Voice following** (build step 3): speech recognition replaces the level. The guide jumps to the recognised word, it never goes backwards on its own, and off-script speech makes it wait.
- **Manual:** the speaker scrolls by drag, wheel or keys. The word under the reading line becomes the current word, so switching back continues from there. A drag or wheel during playback pauses it.
- Speed changes (the −/+ buttons, the arrow keys) blend over 300ms, never a jump. Speed runs from 0.5× to 2.0× in 0.1 steps, shown as "1.2× · 156 wpm".

## Motion: how the text moves

- **Line step** (proposed default): the current line sits on the reading line and stays there while it is read. When the next line starts, the text glides up one line (an exponential glide, time constant 90ms). Your eyes never chase moving words.
- **Smooth:** the classic prompter. The text moves at constant speed within a line (`ease-scroll`) and reaches the next line as its last word ends. It stands still during a hold.
- **One phrase:** only the phrase being spoken, large and centred on the reading line, with the next phrase small underneath. Phrases break at gap cues and sentence ends. Best on a phone held close, or for short videos.
- In every motion the text stands still during a hold. That stillness is the pause cue; the badge and the guide only name it.

## The guide: which word to say now

The guide marks the current word. It is always one mark, never two, and it follows the timeline exactly.

- **Dot** (proposed default): a small ball that bounces from word to word, and acts out each cue. The rules are below.
- **Underline:** a bar under the current word that fills across it in the reading direction as the word is spoken. Words already said on the line dim to `stage-text-read`.
- **Spotlight:** the current word at full strength, the next word at 70%, everything else on the line at 32%. The calmest guide; good for experienced speakers.
- **Off:** only the reading line. For speakers who read ahead and find any mark distracting.

### The bouncing dot

The dot is white (`stage-text`). It takes a cue's colour only while it acts that cue out, so its colour always means something.

| Moment | What the dot does |
|---|---|
| A word starts | It lands on the word (just above it, a third of the way in from the leading edge) with a small squash, then arcs toward the next word so it arrives as that word starts |
| A stressed word | It jumps higher (36px arc instead of 22px), lands in `stage-stress`, and the landing throws a ring that grows and fades (`burst`) |
| A slower run | Low, long arcs (14px), in `stage-slower` |
| A faster run | Short skips (9px), in `stage-faster` |
| An energy run | It throws small sparks in `stage-energy` as it travels |
| A new line | An 18px arc down to the start of the next line |
| A pause or long pause | It hops onto the pause glyph and rests there. A ring in `stage-pause` closes around it over exactly the length of the hold |
| A breath | It rests on the breath glyph and swells in `stage-breath` like an inhale, then settles |
| The last 160ms of a hold | It hops on to the next word, so the speaker sees the restart coming |
| Voice pace, waiting | It hovers over the next word and bobs gently until the voice starts |

- Size: about 0.4 of the type size (18px at 44px text), with a soft glow in its own colour.
- It never covers a letter: it rides above the x-height, and its arcs stay within the line gap.
- Positions come from the laid-out word boxes, never from animated ones, so the kinetic effects never throw it off.
- Right to left: it travels right to left, and lands a third of the way in from the word's right edge.
- Reduced motion: the dot jumps from word to word with no arc, squash, burst or sparks.

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

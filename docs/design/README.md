SpawnAlpha is a teleprompter and recorder that coaches delivery: the AI marks up a script with delivery cues, the prompter shows those cues while you record your camera, your screen or both, and the review checks the take against them. This system covers every surface of it: the Studio where scripts are written and reviewed, and the Stage where they are performed. "SpawnAlpha" is a working name.

Three further sections go deeper: **Prompter** (how the stage reads), **Recording** (how the prompter works with camera, screen and screen-plus-camera recording) and **Motion** (every animation and its timing).

## Principles

1. **The script is the star.** Text gets the space, the contrast and the largest type. Chrome recedes; on the Stage it all but disappears.
2. **Every cue has a shape.** A cue is recognisable in peripheral vision, at arm's length, by its glyph and treatment first and its colour second. Never mark a cue by colour alone.
3. **Eyes on the lens.** The reading line and a narrow text column sit as close to the camera as the device allows. Nothing on the Stage pulls the gaze away from it.
4. **Quiet while live.** While recording, the only things that move are the ones that carry timing: the scroll, a hold badge, the countdown. No toasts, no bouncing, no blinking.
5. **The AI proposes, you decide.** Proposed cues are drawn faded until accepted. The person edits, accepts or removes every one.
6. **Three languages, one system.** English, French and Arabic are first-class. Right-to-left mirrors layout and cue placement, never the meaning of a cue.

## Two worlds: Studio and Stage

- **Studio** is where scripts are written, marked up and reviewed: library, editor, settings, review. It follows the device theme with `paper`, `surface`, `ink` in Studio light and Studio dark.
- **Stage** is where scripts are performed: the prompter, the countdown, the recording HUD, the camera view. It is always dark, whatever the device theme: `stage`, `stage-text`, `stage-chrome`. Never show Studio surfaces on the Stage, and never put Stage black inside the Studio.
- Going from Studio to Stage is a deliberate, animated change (see Motion). Coming back returns to the exact screen the person left.

## Content fundamentals

- **Voice.** A calm, direct director who respects the performer. Short sentences, plain words, second person ("you"). The app never says "I".
- **Cues are named by what the speaker does**, as imperatives: *Pause*, *Long pause*, *Breathe*, *Stress*, *Slow down*, *Speed up*, *Lift energy*. Use exactly these names everywhere: the editor sheet, the legend, the hold badge (in capitals only on the Stage: PAUSE, LONG PAUSE, BREATHE), the review.
- **Notes on cues are short reasons**, written as the director would say them: "Let the key point sink in", "Pause between steps", "Numbers stick when stressed". No more than six words.
- **Buttons state exactly what happens**, in sentence case: "Mark up with Claude", "Accept all", "Record", "Save key". A result confirms in the past tense: "Take saved".
- **Errors say what went wrong and how to fix it**, without apology: "Could not reach Ollama at localhost:11434. Is it running?" "Stop the recording first."
- **Numbers** use digits and real units: "142 wpm", "0:33", "3 takes", "12,000". Timers use tabular figures in `timecode`.
- **No emoji** in the interface or in cue notes.
- **Script text is sacred.** The app never rewrites the script silently: rewrites are suggestions with Apply and Dismiss.

## Colour

- Studio: set pages on `paper`, cards and sheets on `surface`, fields on `surface-sunk`. Text is `ink`, secondary `ink-2`, meta `ink-3`. Dividers are `line`; any border that marks a control's edge is `line-strong`.
- The one primary action per screen is filled `primary` with `on-primary` text. Everything else is outlined (`line-strong`) or plain.
- `cue` amber is the signature. Use it for the brand mark, the stressed word, and the Accept-all fill (with `on-cue` text). Never set text in `cue` on a light ground; use `cue-stress` for amber-family text.
- `rec` is the tally light. It appears only while a camera or screen is live: the REC dot, the running timer, the stop button. Never use it for errors (`danger`) or decoration.
- `success` and `warning` belong to the delivery review and always travel with an icon (check, alert), never colour alone.
- Stage: script text is `stage-text` on `stage`, or on `stage-scrim` over a camera preview. Spoken words fade to `stage-text-read`. The reading line is `stage-line`. Cues on the stage use the `stage-` cue tokens (`stage-stress`, `stage-pause`, `stage-breath`, `stage-slower`, `stage-faster`, `stage-energy`, their tints) and the tally is `stage-rec`: the stage never changes with the Studio theme.
- Keyboard focus is a 2px solid `focus` ring with a 2px gap, on every interactive element in the Studio. On the Stage the ring is `stage-text`.

## The cue vocabulary

Every cue has a fixed glyph, colour and treatment. The same cue looks the same in the editor, on the prompter, in the legend and in the review. The colours below are the Studio tokens; on the stage each has a `stage-` twin (`cue-pause` becomes `stage-pause`).

| Cue | Where it sits | Treatment | Glyph | Colour |
|---|---|---|---|---|
| Stress | on 1 to 3 words | weight 700, 1.15× size | none; the word is the cue | `cue-stress` |
| Pause | after a word | glyph in the gap | pause bars | `cue-pause` |
| Long pause | after a word | larger glyph in the gap | pause bars in a disc | `cue-pause` |
| Breathe | after a word | glyph in the gap | air | `cue-breath` |
| Slow down | over a run of words | tint behind the words, label at the start, bar in the gutter | double arrow down + "slow" | `cue-slower`, `tint-slower` |
| Speed up | over a run of words | tint, label, gutter bar | double arrow up + "fast" | `cue-faster`, `tint-faster` |
| Lift energy | over a run of words | words coloured, bolt at the start | bolt | `cue-energy` |

- A **proposed** (not yet accepted) cue is drawn at half opacity, and a proposed stress also gets a dotted underline. Accepting it animates it to full strength (see Motion).
- Draw glyphs inside the text as icon-font characters, joined to their word by a narrow no-break space (U+202F), so they wrap with the word and keep their side in right-to-left text.
- Pace and energy runs cover whole sentences unless the person shortens them.

## Typography

- Set everything in the `reading` family, Readex Pro. It was designed for reading proficiency and draws Latin and Arabic as one family, so a French and an Arabic script sit on the same prompter at the same colour and weight. `mono` (IBM Plex Mono) is for timecodes and meters only.
- Studio text uses `display`, `title-lg`, `title`, `body`, `body-sm`, `label`, `caption`. The editor's Marks view uses `script-edit`, or `script-edit-ar` for Arabic.
- The prompter uses the Stage styles: `stage-m` by default, `stage-s` over a phone's camera preview, `stage-l` or `stage-xl` at a distance or on glass. Stage text is weight 500; stressed words are 700.
- Arabic: line height 1.6 at every stage size (`stage-m-ar`), no letter-spacing, no capitals or italics (none exist). Emphasis is weight and colour only. Keep digits as the script writes them.
- Keep prompter lines short: at most `column-max` (about 34 characters) under a camera, so viewers can't see the eyes scanning.

## Space, shape and elevation

- Spacing follows `space-1` to `space-8` (4px base). Phones use a `space-4` side gutter, desktops `space-5`, and the prompter `space-7` on desktop.
- Shapes: `radius-xs` for tints behind words, `radius-sm` for chips and cue pills, `radius-md` for buttons, inputs and cards, `radius-lg` for sheets and the HUD, `radius-full` for the record button, hold badges and the camera bubble.
- Cards are flat with a `line` border. Only floating things cast `shadow-float`: the recording HUD, the prompter window, sheets.
- The Stage has no cards and no shadows: text on black, controls on `stage-chrome`.

## States

- Hover: lift the fill 4% toward `ink`. Pressed: 8%, with a `dur-instant` press.
- Disabled: 38% opacity; never hide a control that exists but can't be used now.
- Selected word in the editor: `tint-select` behind it while its sheet is open.
- Pending cue: half opacity, dotted underline on stress. Accepted: full.
- Recording: `rec` dot and running `timecode`; nothing else in the interface changes colour.

## Iconography

- Use Material Symbols Rounded throughout (Material Icons "rounded" in Flutter), at 20px in the Studio and 0.7× the text size inside script text.
- Cue glyphs: `pause_rounded` (Pause), `pause_circle_rounded` (Long pause), `air_rounded` (Breathe), `keyboard_double_arrow_down_rounded` (Slow down), `keyboard_double_arrow_up_rounded` (Speed up), `bolt_rounded` (Lift energy). Reuse these glyphs for the same cue everywhere and never for anything else.
- Recording modes: `videocam_rounded` (Camera), `screen_share_rounded` (Screen), `picture_in_picture_alt_rounded` (Screen + camera).
- No emoji, no illustrations inside the Stage.
- There is no logo yet. Set the name in `reading` at weight 700 with `-0.02em` tracking, in `ink`, next to a `cue` amber square with `radius-xs` corners.

## Right to left

- An Arabic script runs right to left in the editor and on the prompter, whatever the app's own language.
- Mirror position, not meaning: the reading caret and the pace gutter move to the right edge; the Slow down arrow still points down.
- Wrap mixed-direction labels (an Arabic title inside an English subtitle) in first-strong isolates (U+2068 … U+2069).

## Accessibility

- Text meets 4.5:1 on its grounds in both Studio themes and on the Stage; glyphs, borders and focus rings meet 3:1. Every cue colour on the Stage exceeds 7:1 on `stage`.
- Cues never rely on colour: each has its own glyph or treatment. Review results pair `success` and `warning` with icons.
- Honour reduced motion (see Motion). The prompter scroll keeps moving because it is the function, not decoration.
- Every control is reachable by keyboard on desktop, with the prompter shortcuts listed in the Prompter section.

## Using this system in the app

The Flutter app implements these tokens as a theme: colours as `ColorScheme` plus a `CueColors` extension, the type styles as a `TextTheme` plus stage styles, and durations and easings as constants. Name them after the tokens here, so `cue-slower` is `CueColors.slower` and `dur-quick` is `Motion.quick`.

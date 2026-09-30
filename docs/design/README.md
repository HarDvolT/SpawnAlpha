SpawnAlpha is a teleprompter and recorder that coaches delivery and then edits the take for you. The AI marks up a script with delivery cues. The prompter shows those cues while you record your camera, your screen or both. When you stop, the **Director's Cut** is already waiting: silences trimmed, the best retake kept, zooms on your clicks, captions from your script. You check it and publish. "SpawnAlpha" is a working name.

This system covers every surface: the **Studio** where scripts are written and reviewed, the **Stage** where they are performed, and the **Cut**, which is what your viewers see. Four sections go deeper:
- **Prompter** covers how the stage reads, including kinetic text.
- **Recording** covers camera, screen, both, and the cursor companion.
- **Motion** covers springs, signature motions and every animated moment.
- **Director's Cut** covers the automatic edit, captions, zooms and export.

## Principles

1. **The script is the edit.** The cues you perform to also drive the cut: pauses mark where captions break and where silence is kept, stress picks the words that pop, pace sets caption width, and clicks and "here" set the zooms. Mark the script once and the edit follows from it.
2. **Finished when you stop.** The Director's Cut is ready the moment a take ends. Every automatic change is listed, can be undone, and is never hidden. If the edit is unsure, it asks one clear question instead of guessing.
3. **Every cue has a shape and a motion.** A cue is known at a glance by its glyph and at the corner of the eye by its signature motion. Colour comes third. A cue is never marked by colour alone.
4. **Motion you can read.** Everything that moves carries meaning: the scroll carries time, a glyph's motion says what to do with your voice, a number that rolls shows what changed. Nothing moves for decoration.
5. **Eyes on the lens.** The reading line and a narrow column sit as close to the camera as the device allows. Anything that would pull your eyes away (such as a prompter chasing the mouse) is off while the camera is on.
6. **The AI proposes, you decide.** Proposals are drawn faded until you accept them. The script is never rewritten silently.
7. **Three languages, one system.** English, French and Arabic are first-class. Right to left mirrors layout and placement, never the meaning of a cue.

## Three surfaces: Studio, Stage and Cut

- **Studio** is where scripts are written, marked up and reviewed: the library, editor, settings and the finish screen. It follows the device theme, using `paper`, `surface` and `ink` in Studio light and Studio dark. It feels like a director's desk: paper, a marker, pencil notes in the margin.
- **Stage** is where scripts are performed: the prompter, countdown, recording HUD, camera view and cursor companion.
  - It is always true black, whatever the device theme, using `stage`, `stage-text` and the `stage-` cue tokens.
  - Anything floating over live pixels is **glass** (`stage-glass`, blurred, with a `stage-glass-edge`).
  - Never show Studio surfaces on the Stage, and never put Stage black inside the Studio.
- **Cut** is the rendered video: captions, zooms, cursor effects and the backdrop. It uses the `caption-` tokens, the `screen-fx` family and the `ripple` colour, all fixed so an export looks the same whatever the theme.
- Going from Studio to Stage is a deliberate, animated change (see Motion), and so is coming back to the finish screen when you stop.

## What makes it feel premium

- **One hero per screen.** Each screen has one thing in the display face or one live preview. Everything else is quiet.
- **Springs for anything a person touches.** Sheets, glyphs, toggles and the record button settle on springs (see Motion). Fixed-duration tweens are only for fades.
- **Numbers roll, text paints, glyphs arrive.** Durations count to their new value, a marker swipe draws across a stressed word, and cue glyphs land on the snappy spring. Change is shown, not just stated.
- **Show the work instead of a spinner.** While the edit runs, its list fills in item by item and the timeline tightens in front of you.
- **Glass over live pixels, flat on paper.** Glass is for surfaces over a camera or screen. Studio cards are flat with a hairline border.
- **Real content in every empty state.** A new user sees a sample script already marked up, never a blank page.
- **Tabular signal type for anything that changes every frame**, so timers and meters never jitter.

## Content fundamentals

- **Voice.** A calm, direct director who respects the performer. Use short sentences, plain words and the second person ("you"). The app never says "I".
- **Cues are named by what the speaker does**, as imperatives: *Pause*, *Long pause*, *Breathe*, *Stress*, *Slow down*, *Speed up*, *Lift energy*.
  - Use exactly these names everywhere.
  - On the Stage they appear in capitals: PAUSE, LONG PAUSE, BREATHE.
- **Director's notes** are the AI's reason for a cue, pencilled in the margin.
  - Lower case, at most six words, fragments are fine: "the number is the story", "slow. let them do the maths", "lift! this is the turn".
  - Notes explain; they never instruct the app.
- **The edit list says what was done, in the past tense**, with a count and the rule: "Dead air trimmed · 41 s · Gaps over 0.7 s. Your 9 marked pauses stay."
- **Buttons state exactly what happens**, in sentence case: "Mark up with Claude", "Accept all", "Record", "Export 2 videos".
- **Errors say what went wrong and how to fix it**, without apology: "Could not reach Ollama at localhost:11434. Is it running?"
- **Numbers** use digits and real units: "142 wpm", "0:33", "3 takes", "12,000". Timers use tabular figures in the signal face.
- **No emoji** in the interface, the cue notes or the captions (unless the person adds them).
- **Script text is sacred.** Rewrites are suggestions with Apply and Dismiss. A caption follows what was said, and the edit flags any place where that differs from the script.

## Colour

- **Studio grounds and text.**
  - Pages sit on `paper`, cards and sheets on `surface`, and fields on `surface-sunk`.
  - Text is `ink`, secondary text `ink-2`, and meta text `ink-3`.
  - Dividers are `line`. Borders that mark a control's edge are `line-strong`.
- **One primary action per screen**, filled `primary` with `on-primary` text. The one exception is the **ship** action (Accept all, Export), which is filled `cue` amber with `on-cue` text. Everything else is outlined or plain.
- **`cue` amber is the signature.** Use it for:
  - the brand square;
  - the marker swipe behind stressed words in the Studio;
  - stressed words on the Stage (`stage-stress`);
  - the zoom and ripple marks in the Cut.
  Never set text in `cue` on a light ground; use `cue-stress` for amber-family text.
- **`rec` is the tally light.** It appears only while a camera or screen is live. Never use it for errors (`danger`) or decoration.
- **`success` and `warning`** belong to the review and the edit list, and always travel with an icon.
- **On the Stage**:
  - Script text is `stage-text` on `stage`, or on `stage-glass` over live video.
  - Spoken words fade to `stage-text-read`.
  - Cues use the `stage-` twins, and the tally is `stage-rec`.
  - The Stage never changes with the Studio theme.
- **In the Cut**, captions are `caption-text` with a shadow, stressed caption words are `stage-stress`, Karaoke may use `caption-plate`, and clicks and zooms are `ripple`.
- **Keyboard focus** is a 2px solid `focus` ring with a 2px gap on every interactive element. On the Stage the ring is `stage-text`.

## The cue vocabulary

Every cue has a fixed glyph, colour, treatment and signature motion. The same cue looks and moves the same in the editor, on the prompter, in the legend and in the review. Colours below are the Studio tokens; on the stage each has a `stage-` twin.

| Cue | Where | Studio treatment | Stage treatment | Glyph | Signature motion |
|---|---|---|---|---|---|
| Stress | 1 to 3 words | amber marker swipe, weight 700 | `stage-stress`, weight 700, 1.15× size | none; the word is the cue | **Grow**: swells on the beat |
| Pause | after a word | glyph in the gap | glyph in the gap | pause bars | **Tap**: a baton tap |
| Long pause | after a word | larger glyph | larger glyph | bars in a disc | **Hold**: a held ring |
| Breathe | after a word | glyph in the gap | glyph in the gap | air | **Flow**: air moves through |
| Slow down | a run | tint, "slow" label, gutter bar | tint breathes, gutter bar glows | double arrow down | **Sink**: settles lower |
| Speed up | a run | tint, "fast" label, gutter bar | tint with moving speed lines | double arrow up | **Dart**: shoots off, returns |
| Lift energy | a run | words coloured, bolt at start | words glow | bolt | **Spark**: flashes, glows |

- **Proposed cues:** a proposed cue is drawn at half strength. A proposed stress is a marker swipe at 34% instead of 72%. Accepting it paints it to full strength.
- **Glyphs in text:** draw glyphs as icon-font characters inside the text, joined to their word by a narrow no-break space (U+202F), so they wrap with the word and keep their side in right-to-left text.
- **When signatures play:** a signature motion plays **once**, when the cue arrives (the director's pass), when it is pressed, and on the Stage when the take reaches it. Only the legend loops them.

## Typography: four voices

The type system has four voices, and each has one job.

| Voice | Family | Job | Never |
|---|---|---|---|
| **Display** | Anybody (width 50 to 150), Reem Kufi for Arabic | One hero per screen: the finish-screen headline, the duration, the countdown, the wordmark, and every caption in the Cut | script text on the Stage; body copy |
| **Reading** | Readex Pro | Everything you read: the UI, the script in the editor, the prompter | decoration |
| **Signal** | Martian Mono | What changes every frame, or what the Stage labels: timecodes, meters, hold badges, REC, counts in the edit list | sentences |
| **Pencil** | Caveat, Aref Ruqaa for Arabic | The director's margin notes, and annotations in design docs | buttons, labels, anything you must act on |

- **Display width carries pace.** Anybody's width axis is part of the language:
  - Slow runs set wide (width 118).
  - Fast runs set narrow (82).
  - Stressed caption words go to 125, and 135 in Punch captions.
  - Countdown numerals land at 150 and settle to 100 within the beat.
  - The wordmark sits at 112 and weight 800.
- **Readex Pro** was designed for reading proficiency and draws Latin and Arabic as one family, so French and Arabic scripts share a prompter at the same colour and weight. Stage text is weight 500 and stressed words are 700.
- **Studio styles:** `display` and `title-lg` are in the display face; `title`, `body`, `body-sm`, `label` and `caption` are in Reading. The editor uses `script-edit`, or `script-edit-ar` for Arabic.
- **Stage styles:** the prompter uses `stage-m` by default, `stage-s` over a phone camera, and `stage-l` or `stage-xl` at a distance.
- **Arabic:**
  - Line height is 1.6 at every stage size (`stage-m-ar`), with no letter-spacing, no capitals and no italics.
  - Emphasis is weight and colour only. In captions it adds kashida (tatweel) stretching.
  - Keep digits as the script writes them.
- **Line length:** keep prompter lines to `column-max` (about 34 characters) under a camera, so viewers can't see the eyes scanning.

## Glass

- Glass is for surfaces floating over live pixels. That includes:
  - the prompter panel over a phone camera;
  - the recording HUD;
  - the cursor companion;
  - the timecode and mode pills;
  - keystroke badges in the Cut.
- Glass is `stage-glass` with a 16px background blur at 140% saturation, a 1px `stage-glass-edge` inner line and `shadow-float`.
- Glass never sits on paper, and never stacks on glass.

## Space, shape and elevation

- **Spacing** follows `space-1` to `space-8` (4px base). Gutters:
  - phones use `space-4`;
  - desktops use `space-5`;
  - the desktop prompter uses `space-7`.
- **Radii:**
  - `radius-xs` for tints and marker swipes;
  - `radius-sm` for chips and cue pills;
  - `radius-md` for buttons, inputs, cards and the companion;
  - `radius-lg` for sheets, the HUD and the phone prompter panel;
  - `radius-full` for the record button, hold badges and the camera bubble.
- **Elevation:** Studio cards are flat with a `line` border. Only floating things cast `shadow-float`. The Stage has no cards: text on black, and glass over video.

## States

- **Hover** lifts the fill 4% toward `ink`. **Pressed** is 8% with a spring press.
- **Disabled** is 38% opacity. Never hide a control that exists but can't be used right now; say why beside it, as the cursor companion does when the camera is on.
- **Selected word** in the editor has `tint-select` behind it while its sheet is open.
- **Cue states:** pending is half strength; accepted is full; removed fades out.
- **Recording** shows the `rec` tally and a running timecode. Nothing else changes colour.
- **The edit list:** each change has a switch. Turning one off undoes that change, and the duration rolls to its new value.

## Iconography

- **Style:** use Material Symbols Rounded throughout (Material Icons "rounded" in Flutter), at 20px in the Studio and 0.7× the text size inside script text.
- **Cue glyphs.** Reuse these for the same cue everywhere and never for anything else:
  - `pause` for Pause;
  - `pause_circle` for Long pause;
  - `air` for Breathe;
  - `keyboard_double_arrow_down` for Slow down;
  - `keyboard_double_arrow_up` for Speed up;
  - `bolt` for Lift energy.
- **Recording modes:** `videocam` (Camera), `screen_share` (Screen), `picture_in_picture_alt` (Screen + camera), and `visibility_off` for "Hidden from recording".
- **Director's Cut:**
  - `auto_awesome` for the Cut itself;
  - `content_cut` for trims;
  - `graphic_eq` for fillers;
  - `replay` for retakes;
  - `zoom_in` for zooms;
  - `closed_caption` for captions;
  - `crop_portrait` for the vertical version.
- **Limits:** no emoji, and no illustrations on the Stage.
- **Wordmark:** there is no logo yet. Set the name in the display face at weight 800 and width 112, in `ink`, next to a `cue` amber square with `radius-xs` corners.

## Right to left

- An Arabic script runs right to left in the editor, on the prompter and in captions, whatever the app's own language.
- Mirror position, not meaning.
  - The reading caret, the pace gutter and the margin notes move to the other side.
  - The pencil arrows flip.
  - The Slow down arrow still points down.
- Arabic stressed words in captions stretch with kashida after the first joining letter, and never by letter-spacing.
- Wrap mixed-direction labels in first-strong isolates (U+2068 … U+2069).

## Accessibility

- **Contrast:**
  - Text meets 4.5:1 on its grounds in both Studio themes, on the Stage and on glass.
  - Glyphs, borders and focus rings meet 3:1.
  - Every cue colour on the Stage exceeds 7:1 on `stage`.
  - Captions carry a shadow, so they stay legible on any footage.
- **No colour-only signals:** cues each have their own glyph or treatment, and review results pair colour with icons.
- **Reduced motion:** the app honours it (see Motion). Kinetic text, signature motions and spring overshoot turn off. The prompter scroll and the hold ring stay, because they are the function. Exported video is content, not interface, so its motion follows the edit settings, with a "Calm" preset.
- **Keyboard:** every control is reachable by keyboard on desktop, with the prompter shortcuts listed in the Prompter section.

## Using this system in the app

The Flutter app implements these tokens as a theme:
- **Colours** as a `ColorScheme` plus a `CueColors` extension.
- **Type** as a `TextTheme` plus stage, caption, signal and pencil styles, with `fontFamilyFallback` for Arabic (Reem Kufi behind Anybody, Aref Ruqaa behind Caveat). The fonts are bundled, not fetched.
- **Springs** as `SpringDescription(mass, stiffness, damping)` from the `spring` family.
- **Durations and easings** as constants.

Name them after the tokens here: `cue-slower` becomes `CueColors.slower`, `spring-pop` becomes `Springs.pop`, and `dur-quick` becomes `Motion.quick`.

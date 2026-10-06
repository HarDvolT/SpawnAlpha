# CaptionStyles

Captions burned into the Cut, written from the script, timed to the take, and shaped by the cues.

- **Use** in the Director's Cut and in export. Captions are part of the video, so they use the fixed `caption-` tokens, not the Studio theme.
- **Consumer provides** the aligned words (script token, start and end time), their cues, the style, the frame's aspect ratio and the language.
- **Styles:**
  - **Readable** (first Windows export): static complete phrases, at most two
    lines, with the fixed caption plate and tight shadow. Actual saved words,
    including corrections, drive the cut clock. This uses Cue's base type;
    its full word motion and Cue/Punch remain subsequent slices.
  - **Cue** (16:9 default): up to 7 words in the lower third. Words rise in as they are spoken, and stressed words pop in amber.
  - **Punch** (9:16 default): one to three words at a time, centred, big. A stressed word stands alone and larger (width 135).
  - **Karaoke** (tutorials): the whole line waits dimmed and fills word by word, with an amber underline sweeping each word over its spoken length. It has an optional `caption-plate`.

## Windows Karaoke export

The export style choice offers Readable and Karaoke when saved actual words
exist. Readable remains the initial choice until Cue/Punch are complete.
Karaoke uses the same immutable phrase and exact saved word intervals on the
cut clock. It keeps the complete shaped line stable, dims words not yet spoken,
and fills each word at its start. The amber underline advances linearly across
its actual duration, reversing direction for RTL glyph runs. No underline is
invented in a gap. A fixed caption plate stays on for legibility.

Use `caption-waiting` for dim text and the existing `ripple` amber for the
underline. Its thickness/gap are export tokens. Shaping and ink bounds include
Arabic diacritics, mixed text and surrogate pairs. Never derive word times by
dividing a phrase or split words to fit. If timed words are missing or invalid,
the export fails safely and offers retry; it never fabricates Karaoke timing.
SRT/VTT remain complete phrases with original wording. History remembers the
chosen video style; older records are Readable. Cue/Punch cue motion, stress
and pace styling remain to build.
- **Cues shape the text:**
  - Phrases break at gap cues and sentence ends.
  - Stress is `stage-stress`, weight 800, width 125, and pops on `spring-pop`.
  - Slow runs set wide (118) and fast runs narrow (82).
  - Arabic stress stretches with kashida (tatweel) after the first joining letter.
- **Type:** captions are in the display face (Anybody, with Reem Kufi for Arabic), always in `caption-text` with the caption shadow.
- **Safe zones** in 9:16: keep text out of the top 13%, bottom 21% and right 14%, where the platform UI sits.
- **Don't** caption from the transcript when the script exists. When speech and script differ, follow the speech and flag it on the finish screen.

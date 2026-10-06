# CaptionStyles

Captions burned into the Cut, written from the script, timed to the take, and shaped by the cues.

- **Use** in the Director's Cut and in export. Captions are part of the video, so they use the fixed `caption-` tokens, not the Studio theme.
- **Consumer provides** the aligned words (script token, start and end time), their cues, the style, the frame's aspect ratio and the language.
- **Styles:**
  - **Readable** (first Windows export): static complete phrases, at most two
    lines, with the fixed caption plate and tight shadow. Actual saved words,
    including corrections, drive the cut clock. This uses Cue's base type.
  - **Cue** (16:9 default): up to 7 words in the lower third. Words rise in as they are spoken, and stressed words pop in amber.
  - **Punch** (9:16 default): one to three words at a time, centred, big. A stressed word stands alone and larger (width 135).
  - **Karaoke** (tutorials): the whole line waits dimmed and fills word by word, with an amber underline sweeping each word over its spoken length. It has an optional `caption-plate`.

## Windows Karaoke export

The export style choice offers Readable, Cue, Punch and Karaoke when saved
actual words exist. Cue starts selected for wide/feed output and Punch for
portrait until the person chooses a style. Later format changes preserve an
explicit style choice. Readable remains the default for older saved exports.
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
chosen video style; older records are Readable. Karaoke also uses reliable
accepted stress, energy and pace cues under the same rules as Cue/Punch.

## Windows Cue/Punch delivery captions

Cues come only from the take's frozen Script and its usable alignment. Exact
matches with reliable recognition or an explicit wording correction may carry
accepted stress/pace/energy cues. Changed/added/uncertain words keep actual
wording without borrowed emphasis. Notes and computer-only have no script cues.
The same source-word identity survives removals/reordered kept ranges; never
re-align only the shortened transcript and assign cues to the wrong retake.
Accepted gap cues end phrases. Punch keeps one to three actual words, with a
stressed word alone. Subtitle phrases stay complete and preserve actual speech.

Motion is a deterministic function of the export clock and the spring tokens.
Cue words rise from `caption-rise` at their actual start; Punch chunks pop in.
Stress uses the pop spring with fixed start/maximum scale tokens. Typography
and the maximum motion envelope are fitted before drawing, never reflowed
during animation. Reserve the envelope inside the same safe zones and in
spaces beside stressed words, so pops cannot touch their neighbors. Still
captions retain word timing/color but omit transforms; system reduced-motion
preference starts Still. Arabic stress uses three decorative tatweels after
the first joining letter (after its diacritics), without changing saved words
or subtitle text. Anybody pace uses the caption width tokens. Reem Kufi has
no width axis, so Arabic pace uses proportional static type size instead;
shaping and the complete motion envelope are fitted before drawing. All four
Windows styles use the fixed caption plate/shadow for contrast. Do not invent
performance scores from these visual cues.
- **Cues shape the text:**
  - Phrases break at gap cues and sentence ends.
  - Stress is `stage-stress`, weight 800, width 125, and pops on `spring-pop`.
  - Slow runs set wide (118) and fast runs narrow (82).
  - Arabic stress stretches with kashida (tatweel) after the first joining letter.
- **Type:** captions are in the display face (Anybody, with Reem Kufi for Arabic), always in `caption-text` with the caption shadow.
- **Safe zones** in 9:16: keep text out of the top 13%, bottom 21% and right 14%, where the platform UI sits.
- **Wording:** follow saved actual speech, including explicit corrections. The
  frozen script supplies reliable accepted cues; mismatches remain visible in
  review. Never substitute unsaid script words into captions.

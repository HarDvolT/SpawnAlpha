# CaptionStyles

Captions burned into the Cut, written from the script, timed to the take, and shaped by the cues.

- **Use** in the Director's Cut and in export. Captions are part of the video, so they use the fixed `caption-` tokens, not the Studio theme.
- **Consumer provides** the aligned words (script token, start and end time), their cues, the style, the frame's aspect ratio and the language.
- **Styles:**
  - **Cue** (16:9 default): up to 7 words in the lower third. Words rise in as they are spoken, and stressed words pop in amber.
  - **Punch** (9:16 default): one to three words at a time, centred, big. A stressed word stands alone and larger (width 135).
  - **Karaoke** (tutorials): the whole line waits dimmed and fills word by word, with an amber underline sweeping each word over its spoken length. It has an optional `caption-plate`.
- **Cues shape the text:**
  - Phrases break at gap cues and sentence ends.
  - Stress is `stage-stress`, weight 800, width 125, and pops on `spring-pop`.
  - Slow runs set wide (118) and fast runs narrow (82).
  - Arabic stress stretches with kashida (tatweel) after the first joining letter.
- **Type:** captions are in the display face (Anybody, with Reem Kufi for Arabic), always in `caption-text` with the caption shadow.
- **Safe zones** in 9:16: keep text out of the top 13%, bottom 21% and right 14%, where the platform UI sits.
- **Don't** caption from the transcript when the script exists. When speech and script differ, follow the speech and flag it on the finish screen.

# DirectorsCut

The finish screen: what you see when you stop. The edit is already done. It plays out in front of you, and every change is listed and can be undone.

- **Use** after every take. It replaces the old "Take saved" sheet.
- **Consumer provides** the take, the EDL from the auto-edit pipeline (see Director's Cut), the list of changes with counts, the open questions, and the export formats.
- **Headline** is in `display` ("Ready to publish."). The duration rolls from the take's length to the cut's length in the display face: its width narrows to 70 while rolling and springs back.
- **Preview:** the 16:9 cut with its captions, and the 9:16 version inset.
- **Edit list:**
  - One row per pass: dead air, fillers, retakes, zooms, captions, the vertical version.
  - Each row has an icon, a past-tense title, a count pill in the signal face, the rule in one line, and a switch.
  - Turning a switch off undoes only that change, and the duration rolls again.
- **One question:** at most three per take, shown as a dashed card with the choices as buttons.
- **Timeline:** the take as recorded.
  - Dead air hatches in, fillers flash red and the discarded retake greys out.
  - Then everything flagged collapses and the timeline tightens.
  - Zoom marks and the caption bar draw in last.
  - Marked pauses stay, in `cue-pause`.
- **Export row:** format toggles (16:9, 9:16, 4:5, each with its platforms in the signal face), "Open in editor", and the amber ship action ("Export 2 videos").
- **Don't** show a spinner while the edit runs: show the list filling in. **Don't** auto-publish anything.

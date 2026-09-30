# MarkedScript

The script page in the editor's Marks view: the text with its cues, and the director's pencil notes in the margin explaining why.

- **Use** in the editor only. The prompter uses the Prompter component.
- **Consumer provides** the tokens, the marks (pending and accepted, each with its optional note), the selected word, and a tap handler that opens the word sheet.
- **Text:** set in `script-edit`, or `script-edit-ar` for Arabic, right to left, on `surface` in `ink`.
- **Stress** is an amber **marker swipe** (`.sa-marker`): a band over the lower 44% of the word at 72% `cue`, or 34% while proposed. Other cues use their glyphs and tints, at half strength while proposed.
- **Margin notes** use the pencil voice (`note`, or `note-ar` in Aref Ruqaa):
  - Each sits level with its cue's line, pushed down if it would overlap the note above.
  - Each has a pencil arrow pointing back at the text, flipped in right-to-left scripts.
  - A note is lower case, at most six words.
  - The margin is on the trailing side, and folds under the text on narrow screens.
- **The director's pass:**
  - Marks land in reading order about 70ms apart, with the whole pass at most 1.2s: swipes draw, tints paint, and glyphs arrive (`sa-arrive`) at half strength.
  - Each note writes on 260ms after its mark.
  - Accept all paints everything to full strength in reading order, capped at 400ms.
- **The tapped word** gets `tint-select` while its sheet is open.
- **Don't** move or reflow words while marks animate. Only paint and glyphs change.

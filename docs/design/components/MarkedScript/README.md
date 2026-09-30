# MarkedScript

The script with its cues in the editor's Marks view, where the person reviews what the markup proposed.

- **Use** in the editor only; the prompter uses the Prompter component.
- **Consumer provides** the tokens, the marks (pending and accepted), the selected word and a tap handler that opens the word sheet.
- Set text in `script-edit` (Latin and French) or `script-edit-ar` (Arabic, right to left) on `surface`, in `ink`.
- Draw proposed cues at half opacity, and a proposed stress with a dotted underline. Accepted cues are full strength.
- The tapped word gets `tint-select` while its sheet is open.
- Motion: when a markup pass returns, cues draw in in reading order, 18ms apart and capped at 800ms in total (the director's pass). Accepting settles a cue from 0.96 to full size over `dur-quick`. Accept all runs the settle through the script, capped at 400ms.
- **Don't** move or re-flow the words while cues animate; only the cues change.

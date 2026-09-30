# CueGlyphs

The seven delivery cues and the only way each one may be drawn: Stress, Pause, Long pause, Breathe, Slow down, Speed up and Lift energy.

- **Use** wherever a cue appears: the prompter, the editor's Marks view, the legend, the word sheet and the review. A cue must look the same in all of them.
- **Consumer provides** the script tokens and the list of accepted (and, in the editor, pending) marks. Gap cues (Pause, Long pause, Breathe) attach to the word before the gap; span cues (Stress, Slow down, Speed up, Lift energy) cover a run of words.
- **Glyphs** are Material Symbols Rounded, drawn as characters inside the text and joined to their word by a narrow no-break space (U+202F), never as floating widgets. That keeps them on the correct side in Arabic.
- **Stress** is drawn as an amber marker swipe in the Studio, and as `stage-stress` weight 700 on the Stage.
- **Motion:** every glyph has a signature motion (see GlyphMotion).
- **Colour** comes from the `cue-*` tokens: dark values on the stage, darker values in Studio light. Slow down and Speed up also tint their words (`tint-slower`, `tint-faster`).
- **Do** keep a cue's glyph when its colour can't be seen (printouts, colour blindness). **Don't** reuse a cue glyph or colour for anything that isn't that cue.

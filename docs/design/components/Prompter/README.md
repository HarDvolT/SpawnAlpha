# Prompter

The stage: the script in large type, led word by word by a guide, holding at every pause, and acting out every cue near the reading line.

- **Use** for practice, for camera recording (as a glass panel over the preview) and for screen recording (inside the Prompter window or the cursor companion). The Prompter section of this system is its full specification.
- **Consumer provides**:
  - the script tokens and the accepted marks;
  - the coaching style, for words per minute and pause lengths;
  - the speaker's choices: Guide, Motion, Pace and Cues (below), plus the speed, the Stage size and the mirror;
  - with Voice pace, whether the microphone hears speech right now.
- **Four choices, one tap each in the control bar:**
  - **Guide:** Dot (a ball that bounces from word to word and acts out each cue), Underline (fills across the current word), Spotlight (only the current and next word lit), Off.
  - **Motion:** Line step (the line stays put on the reading line, then glides up), Smooth (the classic scroll), One phrase (only the current phrase, large).
  - **Pace:** Voice (moves only while you speak; holds still run out), Timed, Manual.
  - **Cues:** Kinetic or Still.
- **The dot** is white, and takes a cue's colour only while it acts that cue out: it jumps high into a stressed word and bursts, floats low in slow runs, skips in fast ones, sparks in energy runs, rests on a pause glyph while a ring closes, swells on a breath, and bobs while it waits for your voice.
- **Kinetic cues** act out what to do: stress punches and slams an underline, energy words hop, fast runs lean forward, slow runs float, and a pause makes the next words wait.
- **Layout:** the column is at most `column-max` wide under a camera, with the pace gutter on the leading side. Arabic runs right to left, guide included.
- **Don't** let any animation change a line's width or wrap: every effect is drawn over the laid-out text. **Don't** show two guides at once, blink anything, or show toasts on the stage.

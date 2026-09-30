# Prompter

The stage: the script in large type, scrolling on the delivery timeline, holding at every pause, and coming alive near the reading line.

- **Use** for practice, for camera recording (as a glass panel over the preview) and for screen recording (inside the Prompter window or the cursor companion). The Prompter section of this system is its full specification.
- **Consumer provides**:
  - the script tokens and the accepted marks;
  - the coaching style, for words per minute and pause lengths;
  - the scroll mode (Timed, Manual or Voice) and the speed;
  - Kinetic or Still, the Stage size, and whether it is mirrored.
- **Scroll:**
  - The line being spoken sits on the reading line, at `reading-line` from the top. Words above it fade to `stage-text-read` under a gradient.
  - The scroll follows spoken time. It moves within a line and stands still during a hold, while the hold badge's ring empties over the hold.
- **Kinetic (the default):**
  - Words wake up as they near the reading line: stress grows toward 1.08× and pops once as it is spoken.
  - Energy runs glow, speed-up runs show moving speed lines, and slow-down runs breathe.
  - Gap glyphs hit as their hold starts.
  - Text more than three lines ahead sits back.
  - Still keeps only the scroll and the holds.
- **Layout:** the column is at most `column-max` wide under a camera, with the pace gutter on the leading side.
- **Controls** sit on `stage-chrome` along the bottom: back to start, play or pause, speed with its readout ("1.2× · 156 wpm"), time left, Timed/Manual, Kinetic/Still, text size and mirror.
- **Don't** let any animation change a line's width or wrap. Stressed words reserve their growing room up front. **Don't** blink anything, or show toasts on the stage.

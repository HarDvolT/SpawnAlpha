# Prompter

The stage: the script in large type, scrolling on the delivery timeline, holding at every pause and showing every accepted cue.

- **Use** for practice, for camera recording (as a panel over the preview) and for screen recording (inside the Prompter window). The Prompter section of this system is its full specification.
- **Consumer provides** the script tokens, the accepted marks, the coaching style (for words per minute and pause lengths), the scroll mode (Timed, Manual or Voice), the speed, the Stage size and whether it is mirrored.
- The line being spoken is centred on the reading line, at `reading-line` from the top. Words above it fade to `stage-text-read` under a gradient.
- The column is at most `column-max` wide under a camera, with the pace gutter on the leading side: left for left-to-right scripts, right for Arabic.
- The scroll moves at constant speed within a line and stands still during a hold. The hold badge appears above the reading line and its ring empties over the length of the hold.
- Controls sit on `stage-chrome` along the bottom: back to start, play or pause, speed −/+ with the readout ("1.2× · 156 wpm"), time left, Timed/Manual, text size and mirror.
- **Don't** animate cues as they pass the reading line, highlight the current word, or show anything that blinks.

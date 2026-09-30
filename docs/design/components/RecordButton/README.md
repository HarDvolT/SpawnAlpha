# RecordButton

The one button that starts and stops a take: a red disc in a ring that morphs into a rounded square while recording.

- **Use** once per recording screen, bottom centre on phones and in the desktop bottom bar. In screen modes the HUD's Stop button replaces it while recording.
- **Consumer provides** the state (idle, counting down, recording, saving) and the press handler. Space triggers it on desktop.
- Colours: `rec` in the Studio, `stage-rec` on the stage, inside a 4px ring in `ink` (Studio) or `stage-text` (stage). Size 68px, `radius-full`.
- Motion: press squeezes to 0.92 over `dur-instant`. Starting a take morphs the disc into a `radius-sm` square over `dur-base` (`ease-press`). Saving turns the ring into a spinner.
- The accessible label says what the press will do: "Record", "Stop", "Cancel countdown".
- **Don't** use `rec` red for any other button.

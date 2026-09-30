# Design language

SpawnAlpha's design language covers every surface of the app:
- the **Studio**: library, editor, settings, review and the finish screen;
- the **Stage**: prompter, countdown, recording HUD, camera and screen recording, and the cursor companion;
- the **Cut**: the edited video's captions, zooms and cursor effects.

**Version 2** (2026-09-30) added:
- **Four type voices:**
  - Anybody for display, whose width axis carries pace;
  - Readex Pro for reading;
  - Martian Mono for signal;
  - Caveat and Aref Ruqaa for the pencil notes.
- **Glass** for anything floating over live pixels.
- **Springs** for all motion a person drives, and a **signature motion per cue**.
- The **kinetic prompter**, which never reflows text.
- The **cursor companion**, for screen-only recording.
- The **Director's Cut**: automatic edit, captions, auto-zoom and the finish screen.

The product direction behind it, and the open decisions, are in [roadmap.md](roadmap.md).

- **Visual reference (live previews and animations):** the "SpawnAlpha Design Language" design-system artifact, <https://claude.ai/artifact/9giSmh3bZYpFsTk9jLkYFr>. It is private to the project owner until they share it.
- **Source files for agents:** [`docs/design/`](design/). They mirror the artifact's `project/` folder exactly, so they are the same content.

| File | What it covers |
|---|---|
| [design/README.md](design/README.md) | The brand book: principles, voice, colour, the cue vocabulary, type, shape, states, iconography, right to left, accessibility |
| [design/prompter.md](design/prompter.md) | The prompter's anatomy, the scroll (Timed, Manual, Voice), sizes, mirror mode, keyboard |
| [design/recording.md](design/recording.md) | Camera, Screen and Screen + camera modes; where the prompter goes in each; hiding it from capture; the recording flow |
| [design/motion.md](design/motion.md) | Springs, the signature motion of each cue, every animated moment, haptics and reduced motion |
| [design/autoedit.md](design/autoedit.md) | The Director's Cut: the auto-edit pipeline (align, clean, polish, review, export), captions, zooms, guarantees and honest limits |
| [design/tokens.json](design/tokens.json) | All tokens: colours per theme (including glass and caption colours), the four font families and type styles, spacing, radii, shadow, durations, easings, springs, prompter constants, and the screen-effect defaults |
| [design/components/](design/components/) | A guideline (`README.md`) and a live `preview.html` for each of the 20 components and the cover |

## Changing it

1. Edit the files in `docs/design/`.
2. Run `node docs/design/render-previews.mjs` and look at `docs/design/screenshots/` in both themes.
3. Republish the artifact from the same files: the Artifact tool, `url` above, `root` = a folder whose `project/` is a copy of `docs/design/` (plus the artifact's `project/design-system.json`, read from the artifact first). Only send the files you changed.

Previews that animate need time before a screenshot; `render-previews.mjs` waits per component. Write invisible characters in previews with `String.fromCharCode(...)`, never literally.

The Flutter app doesn't use these tokens yet; `docs/status.md` tracks that work.

# Design language

SpawnAlpha's design language covers every surface of the app: the **Studio** (library, editor, settings, review) and the **Stage** (prompter, countdown, recording HUD, camera and screen recording).

- **Visual reference (live previews and animations):** the "SpawnAlpha Design Language" design-system artifact, <https://claude.ai/artifact/9giSmh3bZYpFsTk9jLkYFr>. It is private to the project owner until they share it.
- **Source files for agents:** [`docs/design/`](design/). They mirror the artifact's `project/` folder exactly, so they are the same content.

| File | What it covers |
|---|---|
| [design/README.md](design/README.md) | The brand book: principles, voice, colour, the cue vocabulary, type, shape, states, iconography, right to left, accessibility |
| [design/prompter.md](design/prompter.md) | The prompter's anatomy, the scroll (Timed, Manual, Voice), sizes, mirror mode, keyboard |
| [design/recording.md](design/recording.md) | Camera, Screen and Screen + camera modes; where the prompter goes in each; hiding it from capture; the recording flow |
| [design/motion.md](design/motion.md) | Every animation, with durations, easings and reduced-motion behaviour |
| [design/tokens.json](design/tokens.json) | All tokens: colours per theme, type styles, spacing, radii, shadow, durations, easings, prompter constants |
| [design/components/](design/components/) | A guideline (`README.md`) and a live `preview.html` per component |

## Changing it

1. Edit the files in `docs/design/`.
2. Run `node docs/design/render-previews.mjs` and look at `docs/design/screenshots/` in both themes.
3. Republish the artifact from the same files: the Artifact tool, `url` above, `root` = a folder whose `project/` is a copy of `docs/design/` (plus the artifact's `project/design-system.json`, read from the artifact first). Only send the files you changed.

The Flutter app doesn't use these tokens yet; `docs/status.md` tracks that work.

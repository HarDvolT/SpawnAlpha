# Status

Last updated: 2026-09-30

## Where we are

**Build step 1 of 4 (script markup and coached prompter): code complete, not yet run on a real
device.** (The build order is in [product-brief.md](product-brief.md#build-order).)

| Area | State |
|---|---|
| Flutter app scaffold (`app/`: Android, iOS, Windows) | Done |
| Data model: tokens, marks, script document, marks remapped through edits | Done, tested |
| On-device markup engine (EN, FR, AR; three coaching styles) | Done, tested |
| AI markup engines: Claude (native API) plus one OpenAI-compatible engine for OpenAI, Gemini, Mistral, Ollama, LM Studio and custom servers | Done, tested against mock HTTP servers. **Not yet run against any live API or local server.** |
| Settings: provider picker, server address, per-provider keys, model list, connection test | Done, checked in screenshots |
| Delivery timeline, prompter controller, scroll maths | Done, tested |
| Prompter widget: cues, reading line, pause badge, pace bars, mirror, RTL | Done, tested (widget tests plus rendered screenshots) |
| Editor: write, style and language, markup, review marks and suggestions | Done, tested (widget test of the main flow) |
| Practice prompter screen with keyboard shortcuts | Done |
| Camera recording screen (countdown, prompter overlay, saves takes) | Written. **Untested: no camera in CI; needs a real Windows and Android run.** |
| Storage: scripts as JSON files, settings, API key in secure storage | Done |
| Design language (Studio and Stage tokens, cue vocabulary, prompter, recording modes, motion, 14 components) | Done in `docs/design/` and the design-system artifact. **Not yet applied to the Flutter app.** |
| Screen and Screen + camera recording | Designed (`docs/design/recording.md`). Not built. |

85 tests pass (`cd app && flutter test`), and `flutter analyze` is clean.

## Next steps

0. **Apply the design language to the app** (`docs/design-language.md`):
   - the tokens as a Flutter theme (`ColorScheme` plus `CueColors` and stage colours);
   - Readex Pro and IBM Plex Mono bundled as font assets;
   - the new cue colours and glyphs (Long pause becomes `pause_circle`);
   - the always-dark stage;
   - the motion list (director's pass, accept settle, hold badge ring, countdown, record morph);
   - the pending banner and the record screen layout per mode.

   Re-render `app/tool/screenshots_test.dart` and compare with the artifact previews.

1. **Run it on real hardware** (can't be done in a Linux container):
   - Windows: `flutter run -d windows`. Check camera recording through
     `camera_windows`, the keyboard shortcuts, and where the takes are saved.
   - Android phone: check the camera and microphone permission prompts, the
     front camera preview with the prompter overlay, and the recording files.
   - iOS: the same checks as Android (needs a Mac).
2. **Try the AI engines for real.** Use Claude and at least one other cloud
   provider with real keys, and Ollama or LM Studio with a small local model
   (for example a 7B or 8B instruct model). Compare the markup on the three
   samples, and note which local models follow the JSON format reliably. Check
   the phone-to-computer case (LAN address) and the error messages (bad key,
   server off, context too small).
3. Polish found while testing: an in-app list of takes with playback (needs a
   video player that supports Windows), and an easier way to extend a pace or
   energy span beyond one sentence.
4. Then **build step 2, the delivery review**: whisper.cpp transcription with
   word timings, aligned to the script tokens (the `Take` records already
   point at the files). See OpenScreen in the brief for reusable parts.

## Decisions

- 2026-09-30: The recorder records three ways: **Camera**, **Screen** and **Screen + camera**
  (screen and camera as separate files, with the layout chosen after recording). The prompter
  works in all three and is never visible to the viewer: in the screen modes it is a floating
  window excluded from capture (`WDA_EXCLUDEFROMCAPTURE` on Windows), as OpenScreen does for its
  HUD and Notes windows. Full detail: `docs/design/recording.md`.
- 2026-09-30: Design language v1. The Studio follows the device theme; the Stage is always
  dark and true black. Readex Pro (one family for Latin and Arabic) and IBM Plex Mono. Each cue
  has a fixed glyph and colour, and no cue relies on colour alone. On the Stage, only timing
  moves. The artifact holds the live previews; `docs/design/` mirrors it for agents.
- 2026-09-30: The Flutter app lives in `app/`, leaving the repo root free for docs and any
  later backend.
- 2026-09-30: Marks are anchored to token indices, not character offsets or inline tags. Text
  edits remap them with a word-level diff (see [architecture.md](architecture.md)).
- 2026-09-30: The markup has two engines: an on-device rule-based one (free, offline) and Claude
  (cloud, higher quality). Until the subscription backend exists, users bring their own Claude
  API key, which is kept in the platform's secure storage. The default model is
  `claude-opus-5-5`, and the model id is a setting. The brief's open question about which cloud
  model to use is still open.
- 2026-09-30: Users can pick any AI provider for markup: Claude, OpenAI, Gemini, Mistral, a
  local model through Ollama or LM Studio, or any OpenAI-compatible server. Claude uses its
  native API; everything else shares one OpenAI-compatible engine. The on-device rules stay the
  default and the fallback. A subscription backend (the brief's business model) can later be
  added as one more provider.
- 2026-09-30: Markup proposals arrive as *pending* marks; the prompter shows only accepted marks,
  and the editor offers "Accept all" before prompting.
- 2026-09-30: Cue icons are drawn as icon-font glyphs in the text, not as `WidgetSpan`s, because
  of a Flutter right-to-left layout problem (see architecture.md, "Right-to-left gotcha").
- 2026-09-30: The UI is in English only for now. Script text can be in English, French or
  Arabic. Localizing the UI into French and Arabic is not scheduled yet.

## Open questions (from the brief)

- Should screen recording on Windows (build step 4 in the brief) move up, before the delivery
  review? It is now a core mode of the recorder.
- Which cloud model to use for markup, and how much the free tier includes.
- How reliably stress can be detected from volume and pitch (needs a prototype, step 2).
- App name.

## Known limitations

- The Windows camera (`camera_windows`) has no pause or resume, and no device orientation.
- In timed mode the scroll follows a planned pace, not the voice. Voice-following is build
  step 3.
- The on-device markup is heuristic. For example, French and Arabic stress rules are based on
  word lists, not prosody.

## Session log

- 2026-09-30, session 1:
  - Added the brief to `docs/` and scaffolded the Flutter app.
  - Built the model, the on-device and Claude markup engines, the delivery timeline and
    prompter, the editor, practice, recording, settings and library screens, and storage.
  - Found and worked around the right-to-left `WidgetSpan` problem.
  - Added `tool/screenshots_test.dart` for visual checks without a device.
  - 67 tests pass.
- 2026-09-30, session 1 (continued): Added provider choice for the AI markup (the table above),
  with a shared prompt and a forgiving parser for local models. 85 tests pass.
- 2026-09-30, session 1 (continued):
  - Built the design language: a brand book, prompter, recording and motion specs, tokens and
    14 components with live previews.
  - Published it as a design-system artifact and mirrored it in `docs/design/`, with
    `render-previews.mjs` for visual checks.
  - Studied OpenScreen's recording HUD, Notes teleprompter and content protection for the
    recording design.

# Status

Last updated: 2026-09-30

## Where we are

**Build step 1 of 7 (script markup and coached prompter): code complete, with design language
v2 applied. It has not yet run on a real device.** The build order is in
[product-brief.md](product-brief.md#build-order); it was revised on 2026-09-30.

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
| Design language v2 (four type voices, glass, springs, signature motions, kinetic prompter, cursor companion, Director's Cut; 20 components) | Done in `docs/design/` and the design-system artifact |
| Design v2 in the app: fonts and generated tokens, Studio theme, script page (marker swipes, margin notes, director's pass), kinetic prompter with Still, glass hold badge, record screen (glass panel, countdown, record button, timecode), privacy and licences in Settings | Done, tested (widget tests plus rendered screenshots). What's left is listed in the next steps |
| CI (`.github/workflows/build.yml`): analyze, test, then Windows and Android test builds as downloadable artifacts | Working: the first run (#1, 2026-09-30) passed and produced both builds. The builds are compiled but not yet opened on a real device |
| Compliance groundwork ([compliance.md](compliance.md)) | Rules and checklist written, licence page in the app, no secrets in the repo. Legal documents and filings are still to do |
| Screen and Screen + camera recording, cursor companion, telemetry | Designed (`docs/design/recording.md`). Not built. |
| Director's Cut (auto-edit, captions, auto-zoom, finish screen) | Designed (`docs/design/autoedit.md`). Not built; needs a native render core. |

109 tests pass (`cd app && flutter test`), and `flutter analyze` is clean.

## Next steps

1. ~~Get the owner's answer on the roadmap.~~ Done 2026-09-30: approved (see Decisions).
2. **Finish design v2 in the app.** Done so far: the fonts, tokens, theme, script page,
   kinetic prompter, hold badge and record screen. Still to do:
   - glyph signature motions in the Studio: arrive on the director's pass, play once when
     pressed;
   - the accept animation: the marker painting from 34% to 72%;
   - going on stage: a shared-element move from the editor to the prompter;
   - the countdown ring collapsing into the tally, and phone haptics;
   - the desktop record layout: prompter docked under the webcam and a self-view
     thumbnail;
   - the take-saved dialog becomes the Director's Cut finish screen at step 4.

   Re-render `app/tool/screenshots_test.dart` after UI changes, and compare with the
   artifact previews.

3. **Run it on real hardware** (can't be done in a Linux container). No Flutter install is
   needed: download the Windows zip or the Android APK from the latest green **Build** run
   (GitHub Actions, Artifacts; see the README).
   - Windows: `flutter run -d windows`. Check camera recording through
     `camera_windows`, the keyboard shortcuts, and where the takes are saved.
   - Android phone: check the camera and microphone permission prompts, the
     front camera preview with the prompter overlay, and the recording files.
   - iOS: the same checks as Android (needs a Mac).
4. **Try the AI engines for real.** Use Claude and at least one other cloud
   provider with real keys, and Ollama or LM Studio with a small local model
   (for example a 7B or 8B instruct model). Compare the markup on the three
   samples, and note which local models follow the JSON format reliably. Check
   the phone-to-computer case (LAN address) and the error messages (bad key,
   server off, context too small).
5. Polish found while testing: an in-app list of takes with playback (needs a
   video player that supports Windows), and an easier way to extend a pace or
   energy span beyond one sentence.
6. Then **build step 2, the Windows recorder**:
   - Camera, Screen, and Screen + camera.
   - The prompter window, HUD and cursor companion, all hidden from capture.
   - Cursor, click and key-burst telemetry.
   - Fragmented MP4.
   - A spike of the render core for the Director's Cut.

   See OpenScreen in the brief for reusable parts.

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
- 2026-09-30: Design language v2, at the owner's request ("premium, consistent, not boring",
  "interesting fonts", "animated text popups").
  - **Fonts:** four type voices (Anybody, Readex Pro, Martian Mono, Caveat and Aref Ruqaa).
    Anybody's width axis expresses pace.
  - **Studio:** stress is an amber marker swipe, and the AI director writes pencil notes in
    the margin.
  - **Motion:** glass over live video, springs for motion, and one signature motion per cue.
  - **Prompter:** kinetic text only near the reading line, and never reflowing. Big animation
    lives in the captions.
  - **Recording:** the prompter follows the mouse only in screen-only mode (cursor
    companion), never with the camera on. The Director's Cut edits the take automatically,
    from the script, the cues and screen telemetry. Proposed, not yet approved as the build
    order: [roadmap.md](roadmap.md).
- 2026-09-30, **owner's decisions on [roadmap.md](roadmap.md)**:
  - **Build order:** the Windows recorder comes next (step 2), then word timing, the
    Director's Cut v1, the delivery review and retakes, voice-follow, and mobile parity.
    The brief was updated to match.
  - **Core promise:** "Finished when you stop" (the Director's Cut) is the core promise.
  - **Cursor companion:** allowed with the camera on, but docked by default. Following
    on camera needs a one-time warning, and then shows an "Eyes to the lens" reminder.
- 2026-09-30, the owner: **SpawnAlpha is a commercial product**, so everything must follow
  licences and laws.
  - The rules and checklist are in [compliance.md](compliance.md).
  - Only permissive licences are allowed: no GPL or AGPL, and no non-commercial assets.
  - Data stays on the device unless the user sends it.
  - Platform video encoders are preferred for codec patents.
  - Open: the repository is public; the owner should make it private or add a proprietary
    notice.
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

- Which render core should the Director's Cut use (native encoders or an LGPL FFmpeg, GPU
  compositing, through FFI)? Spike it early.
- How good is word alignment for Moroccan Darija and Darija–French switching? The review and
  the Cut both depend on it.
- Which cloud model to use for markup, and how much the free tier includes.
- How reliably stress can be detected from volume and pitch (needs a prototype, step 2).
- App name (trademark search before launch).
- Repository visibility: the repo is public; make it private, or add a proprietary notice?

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
- 2026-09-30, session 1 (continued), design v2:
  - Added the four type voices, glass, springs and signature motions.
  - Added new components: the kinetic Prompter, CaptionStyles, AutoZoom, CursorCompanion,
    DirectorsCut, GlyphMotion and RecordScreen.
  - Reworked MarkedScript as a script page with a marker and pencil notes.
  - Added the `autoedit.md` spec and `docs/roadmap.md` with the pushback and the proposed
    build order.
  - Rendered every preview in both themes and in Arabic, and republished the artifact
    (version 4).
- 2026-09-30, session 1 (continued), design v2 in the app:
  - The owner approved the roadmap: the Windows recorder is next, the Director's Cut is the
    core promise, and the companion may follow on camera after a warning.
  - The owner stated the app is commercial, so everything must be lawful. Added
    `docs/compliance.md` and a Privacy and licences section in Settings.
  - Bundled the fonts, and generated the tokens from `tokens.json` with a staleness test.
  - Rebuilt the theme, the Studio screens, the script page, the kinetic prompter and the
    record screen. 109 tests pass.
- 2026-09-30, session 1 (continued), CI:
  - Added the Build workflow. Its first run passed analysis and all tests on GitHub.
  - It built the Windows app (13.5 MB zip) and the Android APK (27 MB) in about 8 minutes.
  - Flutter installs from the official archive with a checksum check, on Linux and Windows.
  - Next: the owner installs a test build and reports what breaks on real hardware.

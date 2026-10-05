# Status

Last updated: 2026-10-05

## Where we are

**Build step 1 of 7 (script markup and coached prompter): code complete and the main Windows
retest is owner-confirmed. Dot, One phrase, Center, Kinetic and Voice pace are the approved
starting choices. Build step 2 has a Windows display/window source picker, confirmed by
the owner and pushed, plus a live capture preview confirmed by the owner. An excluded
floating prompter trial is built, tested and pushed. The Windows GPU video saver passes
generated-frame and abrupt-exit checks; microphone/capture integration and actual screen
takes remain next.** The build order is in
[product-brief.md](product-brief.md#build-order); it was revised on 2026-09-30.

The owner's first test on Windows (build #1) found: no microphone permission prompt and no
sound in takes; a prompter that scrolled away from the word being read; effects that were too
weak and generic; a generic first screen; and no screen recording yet. Build #2 fixes the first
two (see the session log). The owner confirmed the sound works in build #2, and asked for the
guide choice in the app, which build #4 adds. After trying build #4 the owner asked for the
dot to grow and act out each cue in the cue's colour, and for the next features. The rest is
build step 2 (screen recording).

## Handover (2026-10-05): from here, Codex on the owner's Windows PC

- **PC setup is now complete (Codex, 2026-10-05):** E: is NTFS. The code is at
  `E:\Ai\ChatGPT\SpawnAlpha` on `claude/inspiring-euler-3v24zv`; Flutter **3.47.5**
  (Dart **3.13.4**) is at `E:\Ai\ChatGPT\flutter`. Its official archive SHA-256 was
  verified. Flutter's bin is in the user PATH, `PUB_CACHE` is
  `E:\Ai\ChatGPT\pub-cache`, analytics are disabled, and Developer Mode is enabled.
  Git for Windows was already available. Visual Studio **2022 Community 17.14.41**
  has the Desktop C++ workload, recommended components, and **C++ ATL** (required by
  `flutter_secure_storage_windows`). `flutter doctor -v` passes Windows, Visual Studio,
  desktop device and network checks. Android is intentionally not installed yet.
- **Local checks and launch:** `flutter pub get` succeeds; `flutter analyze` prints
  **No issues found!**; all **206 tests pass** (194 before floating prompter).
  All **72 screenshot cases pass**, including the source picker, unavailable-preview
  and default/minimum floating prompter in EN/FR/AR. The Windows debug build succeeds.
  Windows Git checkout converted generated
  tokens to CRLF, causing the exact-generation test to fail: `.gitattributes` now keeps
  `tokens.g.dart` in LF and the tokens were regenerated without changing design values.
  `flutter run -d windows` builds and opens the app. Existing scripts and takes appear.
  The app is wider than 1000px for the desktop retest. The owner confirmed Home's
  Record next hero, script cards, and Record/Practice buttons are visible and clear.
  The recording setup is open. The owner confirmed the meter for
  `Microphone (HS10-PRO Wireless headset)` moves when speaking. The owner also confirmed
  Check says **We hear you** (also visible in the running app). The owner found the dot's
  cues fine, but its move to a new line confusing. The owner tried the fade return and
  confirmed it is easier to follow; the dot check is complete.
  After inspecting the window with Windows UI Automation, the debug console repeatedly
  logged Flutter `accessibility_bridge.cc` AXTree update errors (nodes 42/44). Home still
  renders. Investigate Windows accessibility during the retest; no SDK workaround or
  accessibility suppression has been applied.
- **Windows build note for the next agent:** a pre-existing Build Tools installation
  lacks ATL, and CMake selected it even though Flutter doctor selects Community. The
  working build cache explicitly selects `C:/Program Files/Microsoft Visual Studio/2022/Community`.
  After deleting/cleaning the Windows build, configure it once from `app/` with:
  ```powershell
  & 'C:/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe' --fresh -S windows -B build/windows/x64 -G 'Visual Studio 17 2022' -A x64 '-DCMAKE_GENERATOR_INSTANCE=C:/Program Files/Microsoft Visual Studio/2022/Community' '-DFLUTTER_TARGET_PLATFORM=windows-x64'
  ```
  Then use `flutter run -d windows` normally. Environment-only instance selection did
  not work on this PC; the explicit CMake cache selection did.
- **Resume here:** Home clarity, the headset microphone meter, Check, the cue dot with
  its revised line return, and kinetic words are confirmed. The owner requested Left,
  Center and Right text alignment, and confirmed it works after trying it. Alignment is
  complete, tested, owner-confirmed and pushed in `b9cae4f`. The owner found One phrase
  starts lit and darkens behind the dot. The owner tried the brightness fix and confirmed
  the phrase stays clear. All five main desktop checks and alignment are now confirmed.
  The owner approved Dot, One phrase, Center, Kinetic and Voice. These are now the
  starting defaults and saved in the normal app. Explicit older saved choices are preserved
  in the general settings reader. Voice already starts when microphone support is available.
  The normal app is now running, not the memory-only cue launcher.
- **Owner data on E:** `SPAWNALPHA_DATA_DIR` is saved in the user environment and explicitly
  supplied in the current launch. App data is `E:\Ai\ChatGPT\SpawnAlpha\local-data`,
  git-ignored. Copied the existing scripts/settings/recordings from Documents without
  deleting originals, updated nine copied take paths, and saved the agreed prompter choices.
  Home shows all three scripts and nine takes. Secure keys stay in Windows secure storage.
- **Resume here (screen recorder slice 1):** the local Windows runner enumerates displays
  and visible, non-minimized app windows. The Stage picker is reached from **Choose screen**
  in the desktop setup rail; selection is checked again when confirmed and held in memory.
  Native smoke check found both monitors (including the portrait display), omitted SpawnAlpha,
  and returned Display 1 to the setup rail. Nothing is captured by this slice. Camera remains
  the only enabled recording mode. The owner chose a source, confirmed it, and reported that
  setup shows the chosen name. Source selection is complete and pushed in `d85687e`.
  Normal Flutter launch sessions `12765`, `51118` and `46560`, and cue-check session
  `6068`, were closed for native rebuilds. Relaunch from `app/` for the next trial.
  Do not record window titles, scripts or private capture content in logs. No new dependency.
  Flutter accessibility AXTree errors also occurred in the old cue launcher (node 279);
  screenshot-only inspection remains usable. No SDK changes or accessibility suppression.
- **Resume here (screen recorder slice 2, live preview):** locally implemented Windows
  Graphics Capture for the selected display or window, presented as a Flutter texture.
  Setup offers **Preview screen** after choosing a source. The preview says **Live preview
  only · nothing saved**; it writes no files and opens no audio stream. Returning stops
  capture and reopens the setup camera. Native smoke checks passed for a browser window,
  the full main display, repeated start/stop, and camera reopening. The Windows capture
  border remains on. Source names and frames stay in memory and are never logged.
  Tests cover resize/aspect ratio, closed or minimized sources, generic errors/retry,
  first-frame timeout, stale native replies, exit cleanup and double-tap prevention;
  real source resize/minimize/close still needs a hardware trial. All 194 tests and
  66 screenshot cases pass; EN/AR unavailable-preview PNGs were inspected.
  The owner scrolled the browser window and confirmed the preview updates. This slice is
  complete. The owner is going to sleep and explicitly asked Codex to keep building;
  further hardware trials can wait until they return. Continue tests/builds and small
  commits/pushes without waiting for an owner trial after each slice during this session.
  Live preview was committed and pushed in `18170a6`. Next comes recording integration
  and the pipeline (mic, fragmented MP4, Screen/Both); source thumbnails can follow.
  Preview uses 8-bit SDR pixels and caps CPU
  readback at 15 fps; recording should keep frames on the GPU and use platform encoders.
  A full-display preview can include the setup/preview app and show recursion until
  excluded-window handling is added. Design docs are updated; the Claude artifact needs
  republishing by a Claude session.
- **Resume here (screen recorder slice 3, floating prompter):** preview now offers
  **Show floating prompter**, opening a separate Flutter engine on the real script with
  the saved guide/motion/alignment/kinetic/mirror choices, in Timed trial pace. The native
  frameless/topmost tool window verifies Windows capture exclusion before showing any
  frame; unsupported or failed exclusion stays hidden. Native display smoke check opened
  it, confirmed the visible/excluded status, showed no prompter in captured display pixels,
  then closed it cleanly. The window has drag/resize/dock/snap, 60–100% opacity, controls,
  global play/speed/sentence shortcuts and click-through Lock with Ctrl+Shift+L unlock.
  Lock requires every shortcut to register, and hide/destroy releases them. It remains
  independent of the main window so minimizing the app should not hide the reader.
  Controller tests cover duplicate/late opens, exit cleanup, external close, generic
  errors/retry and exclusion failure. All 206 tests and 72 screenshots pass; EN minimum
  and AR default PNGs inspected. Real drag/resize/opacity/Lock/shortcut/minimize and the
  owner's trial are pending (owner explicitly deferred them until after sleeping).
  Recording synchronization, voice pacing in the child, separate HUD, Companion and
  actual screen/audio saving are still to build. No new package, input hooks or files.
- **Resume here (screen recorder slice 4, video saver core):** `GpuVideoWriter` uses
  D3D11 GPU color conversion and Windows Media Foundation H.264 in fragmented MP4.
  Output dimensions stay fixed while resized sources fit with black margins; surfaces
  handed to the encoder are never reused. Existing files cannot be overwritten.
  The non-shipping `gpu_video_writer_check` CMake target writes generated colors only:
  120 frames decode with ordered timestamps, correct color channels and resize margins.
  A forced process exit without finalization left 117 of 120 frames decodable on this PC.
  This is a saver core, not an enabled recording mode: chosen microphone audio, actual
  screen capture, common timestamps, stop/error recovery, HUD and take storage are next.
  Floating prompter slice 3 was committed and pushed in `f5a77c4`.
- **Resume here (screen recorder slice 5, sound saver core):** the video writer now
  optionally encodes PCM16 through Windows AAC in the same fragmented MP4. Generated
  mono 48 kHz and stereo 44.1 kHz tones decode with the correct level/duration and
  ordered audio/video timestamps. `MicrophoneCapture` opens the chosen endpoint (or
  pins Windows' default), requests mono PCM16 at 48 kHz through Windows' shared-mode
  converter and returns packet QPC timestamps. A missing chosen ID fails rather than
  recording another microphone. This core is not wired to capture/the UI yet. The
  next slice must align real screen and microphone clocks and safely finalize on stop,
  source closure/minimization or microphone loss. Video core was pushed in `490648d`.
- **Cue retest history (superseded by normal-app launch above):** `app/tool/cue_check.dart` is a development-only launch target.
  It uses the real Home/practice screens with memory-only scripts, settings and keys;
  optional recordings go under `app/build/cue-check/recordings`, on E: on this PC.
  `tool/fixtures/cue_check_scripts.dart` supplies all seven accepted cue kinds in English,
  French and Arabic. Tests verify cue coverage, round trips, valid anchors and the three holds.
  Launch from `app/` with `flutter run -d windows -t tool/cue_check.dart`. English practice
  is open with Dot, One phrase, Timed, Kinetic and Center, ready for the owner to press
  Play (about 23s).
  The dot now holds its outgoing anchor and briefly fades to the new line instead of
  sweeping diagonally across the text. Gap returns use the same approach; trails cannot
  join different lines. Cue timing, layout, same-line hops and reduced motion are preserved.
  Analysis is clean, all 158 tests pass, and all 42 original screenshot cases plus six
  EN/FR/AR line-return cases pass. English and Arabic arrival PNGs were inspected.
  The screenshot tool now uses the bundled reading font as its Windows fallback.
  The owner confirmed the revised line return is easier to follow. The app is rebuilt
  and open, restarted and paused at the beginning with Dot, Line step, Timed and Kinetic.
  The owner confirmed word effects are comfortable. Left/Center/Right alignment buttons
  are now in practice, the recording bar and the desktop recording rail. The normal app
  saves the choice per device; this memory-only launcher keeps it only for its run.
  Alignment preserves Arabic direction and remeasures cue anchors without resetting
  playback or changing line breaks. Old settings retain language and One phrase defaults.
  Analysis is clean, all 165 tests and 57 screenshot cases pass; EN Center and AR Left
  screenshots were inspected. The running app shows the new Align buttons.
  During the live Center click, the owner pressed Escape to stop Computer Use; no further
  app input was sent. The owner subsequently tried the alignment buttons and confirmed
  the text moves as expected. Resumed app control on the next turn and selected One phrase,
  keeping their Center choice, Dot, Timed and Kinetic; reset to the beginning for that check.
  The owner then reported that text starts fully lit and goes dark as the dot follows.
  One phrase now keeps the current phrase fully bright with Dot/Underline, hides all
  but current/next phrases, and hides the paragraph until measurement is ready so it
  cannot flash the full script. Spotlight retains its explicit word focus.
  All 168 tests and 60 screenshot cases pass; analysis is clean. Rendered pixel tests
  verify steady earlier-word brightness and hidden third phrases in EN/FR/AR. English
  and Arabic phrase screenshots were inspected. A hot reload while changing the scroll
  widget tree produced a transient multiple-scroll-controller assertion; a clean hot
  restart succeeded. The app is open at the start with Dot, One phrase, Timed, Kinetic
  and Center. The owner confirmed the brightness fix works. Defaults are the next question;
  screen recording follows once they are chosen. No recorder work is half done.
  Close practice to access the French and Arabic scripts on Home.
  This launcher has temporary test choices; ask about defaults in the normal app afterward.

- **The code:** all work is on `claude/inspiring-euler-3v24zv`; keep working on that branch.
  `main` holds only the initial commit.
- **The guide:** Codex reads [AGENTS.md](../AGENTS.md) on its own. Set up the PC from its "On a
  Windows PC" section (Visual Studio 2022 with C++, Developer Mode, Flutter 3.47.5), then run
  `flutter analyze` and `flutter test` from `app/`.
- **Testing changes on the PC:** `flutter run -d windows` replaces waiting for a CI build.
  The owner's camera and microphones are the real test for everything marked "needs the owner's
  retest" below. CI still builds the Windows zip and the Android APK on every push.
- **Where to start:** next step 2 (try the latest build and pick what to change), then build
  step 2, screen recording (next step 8).
- **The design artifact** (claude.ai) is private to the owner, and only Claude sessions can
  republish it. `docs/design/` holds the same files and is the source of truth; its
  `preview.html` files open in any browser.

| Area | State |
|---|---|
| Flutter app scaffold (`app/`: Android, iOS, Windows) | Done |
| Data model: tokens, marks, script document, marks remapped through edits | Done, tested |
| On-device markup engine (EN, FR, AR; three coaching styles) | Done, tested |
| AI markup engines: Claude (native API) plus one OpenAI-compatible engine for OpenAI, Gemini, Mistral, Ollama, LM Studio and custom servers | Done, tested against mock HTTP servers. **Not yet run against any live API or local server.** |
| Settings: provider picker, server address, per-provider keys, model list, connection test | Done, checked in screenshots |
| Delivery timeline, prompter controller, scroll maths | Done, tested |
| Prompter widget: cues, reading line, pause badge, pace bars, mirror, RTL | Done, tested (widget tests plus rendered screenshots) |
| Voice pacing (moves while you speak, level-based), line-step motion | Done, tested. Tried by the owner on Windows (build #2) |
| Guide choice (bouncing Dot, Underline, Spotlight, Off; G key) and motion choice (Line step, Smooth, One phrase), kept in settings | Done, tested. The owner tried the choice in build #4 |
| The explanatory dot: grows into each cue in its colour, with the cue's glyph inside (pause sign with a timer ring, breath inhaling, stress slam and strike, run announcements, echoes, streaks and sparks, a microphone while waiting) | Done, tested, owner-confirmed on Windows; line returns revised after feedback |
| Kinetic cues that act out the instruction: stress punches to 1.3× with a strike, energy hops, faster leans, slower floats, a pause makes the next words wait | Done, tested, owner-confirmed on Windows |
| One phrase motion: the phrase being said, large and centred, the next one dimmed | Done, tested in EN/FR/AR; steady brightness fix owner-confirmed on Windows |
| Home screen (director's desk): Record next hero, scripts as marked pages, recent takes, sidebar or tab bar; Takes screen | Done, tested; Home owner-confirmed on Windows |
| Windows record set-up rail: mode, camera, every microphone with its own meter, sound check, blocked-by-Windows panel with a button to the privacy settings, prompter choices, and a record button that refuses silence unless chosen | Done, tested, built locally. Headset meter and Check owner-confirmed; privacy-switch and explicit-silence paths still need hardware trials |
| Editor: write, style and language, markup, review marks and suggestions | Done, tested (widget test of the main flow) |
| Practice prompter screen with keyboard shortcuts | Done |
| Camera recording screen (countdown, prompter overlay, saves takes) | Works on Windows (owner, build #2), with sound. Android not yet tried |
| Microphones on Windows: vendored `camera_windows` records from the chosen or default microphone; list, level meter and picker; sound check after each take | Done. The owner confirmed takes have sound in build #2 |
| Storage: scripts as JSON files, settings, API key in secure storage | Done |
| Design language v2 (four type voices, glass, springs, signature motions, kinetic prompter, cursor companion, Director's Cut) | Done in `docs/design/` and the design-system artifact |
| Design v3 demos (22 components): Home, the prompter's guide (bouncing dot, underline, spotlight), motion and pace choices, stronger kinetic cues, the Windows record set-up | Designed and published (artifact version 9). Now built into the app (see above), except the floating prompter window (build step 2) |
| Design v2 in the app: fonts and generated tokens, Studio theme, script page (marker swipes, margin notes, director's pass), kinetic prompter with Still, glass hold badge, record screen (glass panel, countdown, record button, timecode), privacy and licences in Settings | Done, tested (widget tests plus rendered screenshots). What's left is listed in the next steps |
| CI (`.github/workflows/build.yml`): analyze, test, then Windows and Android test builds as downloadable artifacts | Working. Run #9 (2026-09-30, <https://github.com/HarDvolT/SpawnAlpha/actions/runs/36788754590>) is green with everything above, including the new native microphone code |
| Compliance groundwork ([compliance.md](compliance.md)) | Rules and checklist written, licence page in the app, no secrets in the repo. Legal documents and filings are still to do |
| Windows display/window selection and live preview | Built/tested locally and owner-confirmed; pushed in `d85687e` / `18170a6` |
| Excluded floating prompter trial | Built/tested locally, native exclusion smoke check passed; owner trial and recording integration pending |
| Screen and Screen + camera recording, cursor companion, telemetry | Designed (`docs/design/recording.md`). Source selection, preview and floating trial started; saving screen takes, recording HUD and integration remain to build. |
| Director's Cut (auto-edit, captions, auto-zoom, finish screen) | Designed (`docs/design/autoedit.md`). Not built; needs a native render core. |

206 tests pass (`cd app && flutter test`), 72 screenshot cases pass, and `flutter analyze` is clean.

## Next steps

1. ~~Get the owner's answer on the roadmap.~~ Done 2026-09-30: approved (see Decisions).
2. **Main Windows retest and defaults are complete** (2026-10-05; local Windows build):
   - Home: Record next, the script pages, Practice and Record from the hero.
   - The record set-up rail (window wider than 1000px): every microphone moves on its own
     meter; Check says "We hear you"; with Windows' microphone switches off it says so and
     opens the settings; Record refuses silence unless "record without sound" is chosen.
   - The dot acting out each cue, and the kinetic cues; One phrase motion.
   The owner confirmed Home, the headset meter and Check, the dot, kinetic words,
   alignment and the One phrase brightness fix, and approved the starting defaults.
   Privacy-switch and explicit-silence paths still need hardware trials. The owner also
   confirmed the browser-window live preview updates. Continue build step 2 while they
   sleep; they will try the later pieces together when they return.
3. **Remaining design v3 in the app:** the floating prompter window and cursor companion come
   with build step 2 (screen recording).
4. **Finish design v2 in the app.** Done so far: the fonts, tokens, theme, script page,
   kinetic prompter, hold badge and record screen. Still to do:
   - glyph signature motions in the Studio: arrive on the director's pass, play once when
     pressed;
   - the accept animation: the marker painting from 34% to 72%;
   - going on stage: a shared-element move from the editor to the prompter;
   - the countdown ring collapsing into the tally, and phone haptics;
   - the desktop record layout: prompter docked under the webcam and a self-view
     thumbnail (now part of the v3 record set-up, step 3);
   - the take-saved dialog becomes the Director's Cut finish screen at step 4.

   Re-render `app/tool/screenshots_test.dart` after UI changes, and compare with the
   artifact previews.

5. **Run it on real hardware** (can't be done in a Linux container). No Flutter install is
   needed: download the Windows zip or the Android APK from the latest green **Build** run
   (GitHub Actions, Artifacts; see the README).
   - Windows: `flutter run -d windows`. Check camera recording through
     `camera_windows`, the keyboard shortcuts, and where the takes are saved.
   - Android phone: check the camera and microphone permission prompts, the
     front camera preview with the prompter overlay, and the recording files.
   - iOS: the same checks as Android (needs a Mac).
6. **Try the AI engines for real.** Use Claude and at least one other cloud
   provider with real keys, and Ollama or LM Studio with a small local model
   (for example a 7B or 8B instruct model). Compare the markup on the three
   samples, and note which local models follow the JSON format reliably. Check
   the phone-to-computer case (LAN address) and the error messages (bad key,
   server off, context too small).
7. Polish found while testing: an in-app list of takes with playback (needs a
   video player that supports Windows), and an easier way to extend a pace or
   energy span beyond one sentence.
8. Then **build step 2, the Windows recorder**:
   - Camera, Screen, and Screen + camera.
   - The prompter window, HUD and cursor companion, all hidden from capture.
   - Cursor, click and key-burst telemetry.
   - Fragmented MP4.
   - A spike of the render core for the Director's Cut.

   See OpenScreen in the brief for reusable parts.

## Decisions

- 2026-10-05, the owner: after the Windows retest, approved starting settings **Dot,
  One phrase, Center, Kinetic, Voice** (Timed when voice pacing is unsupported).
  Saved on their PC; the design spec and product brief now match. The Claude artifact
  remains behind and needs republishing by a Claude session.

- 2026-10-05, the owner: offer Left, Center and Right prompter text alignment. Save an
  explicit choice for practice and recording; alignment must preserve reading direction.

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
- 2026-09-30, after the owner's first Windows test ("give the option to choose what type of
  animation or scroll style or per-word animation or a jumping dot"): the prompter offers
  **choices**, not one style. Guide: Dot, Underline, Spotlight, Off. Motion: Line step,
  Smooth, One phrase. Pace: Voice, Timed, Manual. Cues: Kinetic, Still. The defaults are
  proposed (Dot, Line step, Voice, Kinetic) until the owner has tried the demos.
- 2026-09-30, the owner, after build #4: **the Dot is the default guide**, and it must explain
  the cues: grow, take the cue's colour and act it out (see `docs/design/prompter.md`, "The
  bouncing dot"). Underline, Spotlight and Off stay as choices.
- 2026-09-30: **A take is never silently soundless.** The set-up shows every microphone with a
  meter and a sound check; with no working microphone the record button is off unless the
  user picks "record without sound"; every take's audio is checked when it is saved.
- 2026-09-30: `camera_windows` is vendored in `app/packages/camera_windows` (BSD-3, licence
  kept) so takes record from the chosen or the default microphone; upstream always used the
  first one listed. Drop the copy if upstream adds microphone choice.
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
- Voice pace follows the microphone level, not the words: it knows when you speak, not
  which word you are on. Voice-following (speech recognition) is build step 3.
- On Windows, the level meter opens its own shared-mode stream on the microphone next to the
  recording, and during the set-up one more per microphone. Screen capture preview works;
  saving screen recordings is not built yet.
- Live preview uses an 8-bit SDR, 15 fps CPU readback path. Full-display preview can show
  recursion because the setup/preview window is not excluded yet. Recording needs a GPU
  pipeline, platform encoders and integration with the excluded floating prompter.
- The on-device markup is heuristic. For example, French and Arabic stress rules are based on
  word lists, not prosody.

## Session log

- 2026-10-05, Windows recorder slice 5 (sound saver core):
  - Added optional platform AAC audio to the fragmented MP4 writer; generated-tone
    checks pass for mono 48 kHz and stereo 44.1 kHz, with near-zero start alignment,
    correct duration and level, ordered timestamps and rejected overlapping samples.
  - Added chosen-endpoint shared WASAPI PCM capture with Windows conversion, packet
    timestamps, explicit errors and balanced stop/release. No fallback from a missing
    chosen device. No new package, copied code, bundled codec or private logging.
  - Actual screen recording, common-clock integration and owner trials remain next.
    The native microphone check captured timestamped PCM packets in memory for 1.1 s,
    discarded them, verified a missing ID does not fall back, and closed cleanly.
    Analysis is clean, all 206 tests pass and the Windows debug build succeeds.

- 2026-10-05, Windows recorder slice 4 (video saver core):
  - Added GPU BGRA-to-NV12 conversion, fixed-size resize fitting, the platform H.264
    encoder and fragmented MP4 sink, with no new dependency or copied code.
  - Native generated-frame checks cover colors, resize margins, ordered timestamps,
    repeated finalization, rejected duplicate timestamps and file overwrite protection.
    The abrupt-exit check decodes 117/120 frames without finalizing the writer.
  - This core is not connected to capture or the UI yet; real screen/microphone takes
    and owner trials remain pending. Analysis is clean, all 206 tests pass and the
    Windows debug build succeeds. The owner authorized continued work while asleep.

- 2026-10-05, Windows recorder slice 3 (excluded floating prompter trial):
  - Added a second Flutter engine/window, verified capture exclusion before visibility,
    privacy-minimized in-process presentation transfer and native placement/opacity/Lock
    with global shortcuts. The preview owns its lifetime, including late replies and
    external close; navigation destroys the child and releases shortcuts.
  - Fixed the minimum-width control bar after tests caught an overflow; EN/FR/AR control,
    direction, timing and minimum-layout checks now pass. Analysis is clean, all 206 tests
    and 72 screenshots pass, and the Windows debug build succeeds. EN/AR PNGs inspected.
  - Native display preview showed no prompter while the native session reported visible
    and excluded; closing worked. Real placement/Lock/shortcut/minimize and owner trials
    remain pending. The owner asked to defer further trials and keep building while asleep.
    Screen/audio saving and recording integration are next; no actual screen takes yet.

- 2026-10-05, Windows recorder slice 2 (live preview):
  - Pushed owner-confirmed source selection as `d85687e`.
  - Added selected-source Windows Graphics Capture and a Flutter texture preview, with
    start/stop ownership, generation guards, safe resize, first-frame timeout and generic
    unavailable/retry states. Capture stops on Back; setup reopens the camera.
  - Prevented duplicate preview routes when the button is tapped twice. Added native-channel,
    controller, lifetime and EN/FR/AR widget tests, plus three screenshot cases. No new
    package, copied code, file/audio capture, network transfer or private logging.
  - Analysis is clean, all 194 tests and 66 screenshot cases pass, and the Windows debug
    build succeeds. Native browser-window and display smoke checks passed, including
    repeat capture and camera reopen. The owner confirmed the preview updates while they
    scroll the chosen window and asked Codex to keep building while they sleep.

- 2026-10-05, defaults and Windows recorder slice 1:
  - Saved the approved starting choices, with regression tests for old/saved settings.
    Added an optional app-data folder override and copied the owner's three scripts and
    nine takes to the git-ignored folder on E:, retaining originals as backup.
  - Built native display/window enumeration, the Stage source picker and its setup entry.
    Refresh and confirmation reject closed sources; private titles/errors stay out of logs.
    No capture starts, no source IDs are persisted, and no dependencies were added.
  - Analysis is clean, all 181 tests and 63 screenshot cases pass, and the Windows debug
    build succeeds. EN/AR picker PNGs inspected; the real two-monitor source list and
    selection return work. The owner confirmed the chosen name returns to setup; this slice
    is complete. Live preview is next.

- 2026-10-05, desktop retest:
  - One phrase feedback: the owner sees text initially lit, then darkening as the dot
    follows. Fixed the per-word dimming for Dot/Underline in phrase mode and prevented
    an unmeasured full-script flash. Hidden phrases now disappear completely. Added
    rendered brightness regressions in EN/FR/AR. All 168 tests and 60 screenshot cases
    pass; analysis is clean. Restarted the Windows test app for the owner's retry.
    The owner tried the fix and confirmed the phrase remains clear. Defaults and screen
    recording are next. All changes to the Claude design artifact still need republishing.
  - The owner confirmed kinetic word effects and requested Left/Center/Right alignment.
    Added the shared Stage choice, persistent setting, recording controls and anchor
    remeasurement. All 165 tests and 57 screenshot cases pass; analysis is clean.
    Hot-reloaded the app. The owner stopped Computer Use with Escape during a Center
    click, then tried the buttons and confirmed the layout works. One phrase is now selected
    for the next check. Defaults remain pending. Design specs changed; the Claude artifact
    still needs republishing.
  - The owner confirmed Home's hero, cards and Record/Practice buttons are clear;
    the HS10-PRO headset microphone meter moves; Check says "We hear you".
  - Added the memory-only development cue-check launcher and seven-cue scripts in EN/FR/AR.
    The owner likes the cue behavior but finds line changes hard to follow. Replaced the
    diagonal return with a short fade at the outgoing and incoming anchors, including
    gap returns, and stopped trails crossing lines. Updated the design specifications;
    the Claude-only design artifact has not been republished and should be refreshed there.
    Analysis is clean, all 158 tests pass, and 48 screenshot cases pass. Built and reopened
    the Windows cue check. The owner confirmed the line return is easier to follow.
    Kinetic is now on for the next check; One phrase and final defaults follow it.

- 2026-10-05, Codex Windows setup:
  - Installed and verified the exact SDK on E:, enabled Developer Mode, saved the user
    PATH and package-cache location, and disabled analytics.
  - Installed Visual Studio Community with Desktop C++ and ATL; fixed the native build's
    selection of an older installation by explicitly configuring CMake for Community.
  - Fixed the generated-token checkout line endings; analysis is clean and 149 tests pass.
  - Built and launched SpawnAlpha on Windows for the owner's retest. Home feedback is next;
    microphone and prompter retests and defaults are still pending. Screen recording is next
    after those checks. No UI or design behavior changed in this setup session.

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
- 2026-09-30, session 1 (continued), the owner's first Windows test:
  - Found: no microphone prompt and silent takes; a prompter that drifted from the word
    being read; weak, generic effects; a generic first screen; no screen recording.
  - Root cause of the silence: `camera_windows` always recorded from the first microphone
    Windows lists, often a virtual or unused one. Vendored the plugin and made it use the
    chosen or default microphone, with a Core Audio list, a WASAPI level meter, a
    microphone chip and picker, and a sound check after each take.
  - Added Voice pace, the current-word underline and line-step motion. 120 tests pass.
    CI run #2 is green with both builds.
- 2026-09-30, session 1 (continued), design v3 demos:
  - At the owner's request, the prompter now offers a choice of guide, motion and pace,
    including a bouncing dot that acts out each cue (it rests in a ring at a pause, swells
    at a breath, jumps into a stressed word).
  - Stronger kinetic cues that act out the instruction.
  - A new Home (director's desk) and the Windows record set-up (every microphone with a
    meter, a sound check, the blocked-by-Windows state).
  - New tokens `stage-ok` and `stage-warn`; `tokens.g.dart` regenerated.
  - Published as artifact version 9 and mirrored to `docs/design/`.
- 2026-09-30, session 1 (continued), the guide in the app:
  - The owner, testing build #2 on Windows: sound works; the underline shows, but there was
    no way to choose a dot or anything else (the choice only existed in the design demo).
  - Built the guide choice into the app: `BouncePath` (the dot's path, pure Dart) and
    `PrompterGuide` / `PrompterMotion` in `lib/src/prompter/guide.dart`; Dot, Underline,
    Spotlight and Off, plus Line step and Smooth, in the control bar (G cycles the guide),
    kept in settings. The text got its own layer so fading never darkens the glass, and
    the dot is painted above the read-zone fades.
  - 137 tests pass; screenshots checked in English and Arabic, phone and desktop.
- 2026-09-30, session 1 (continued), the dot explains, and the next v3 features:
  - The owner, on build #4: the dot is the default, but it should grow and act out the cues
    in their colours; then do the next features.
  - The dot now becomes each cue (`BouncePath` in `prompter/guide.dart`, painted by
    `_DotLayer`): pause sign with a draining timer ring, breath inhaling, stress slam with a
    shockwave and a strike, run announcements with the run's glyph, echoes (slower), streaks
    (faster), sparks and a pulse (energy), a microphone while voice pace waits.
  - Kinetic cues act out the instruction; the overlay now paints stressed, energy and
    pace-run words itself.
  - One phrase motion (`phraseStarts`).
  - The Home screen and a Takes screen; going on stage is shared in `stage_launch.dart`.
  - The Windows record set-up rail, with one meter per microphone and access-denied
    detection in the vendored plugin, a sound check, and the no-silent-take rule.
  - 149 tests pass. Design docs (prompter.md, motion.md) updated for the dot and One phrase.
- 2026-10-05, handover: the owner will finish the project with Codex on their Windows PC.
  Added Windows PC set-up to AGENTS.md, a note on the design artifact for agents that can't
  republish it, and the handover section above. Nothing is half done: the branch is clean,
  pushed, and green in CI (run #9).

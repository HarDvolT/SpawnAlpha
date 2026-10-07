# Status

Last updated: 2026-10-07

## Where we are

**Build step 1 of 7 (script markup and coached prompter): code complete and the main Windows
retest is owner-confirmed. Dot, One phrase, Center, Kinetic and Voice pace are the approved
starting choices. Build step 2 has a Windows display/window source picker, confirmed by
the owner and pushed, plus a live capture preview confirmed by the owner. An excluded
floating prompter, camera bubble and protected countdown/HUD are built and tested. Screen
and Both are enabled in normal Windows setup: chosen-source GPU video, chosen camera in
a separate fragmented file, chosen-microphone AAC, Voice
pace, pause/resume, reader hide/show/Lock and durable local saving/recovery are connected.
The full generated Screen, Both and computer-sound takes pass on this PC. Computer sound
is available with an explicit switch, initially off. The cursor companion is connected
and protected; optional local activity is connected and tested. Longer recording and
abrupt-exit recovery checks pass; the native render-core spike also passes. Build step 3
now has verified offline model setup, bounded local speech jobs, frozen Script/Notes
processing, durable actual words, script alignment and SRT/VTT export in take review.
Generated short and 70-second app checks pass. Reversible quiet cuts, local
take playback and first Windows video exports now work. Automatic local speech
and reversible cutting after Stop are connected. Optional local screen
activity zooms follow clicks, shortcuts and typing on the cut clock, with
an on/off export choice and frozen target history. Independent optional amber
click highlights follow retained visible clicks and leave the camera clear.
Independent optional glass shortcut badges show only allowlisted modifier
chords; ordinary typing stays hidden and badges stop at source cuts.
Optional rounded screen frames fit the picture on a local dark gradient with
soft shadows, keeping camera, captions and click targets independent.
Optional gentle camera emphasis follows reliable actually spoken accepted
Script stress cues, independently of captions. Short takes/cuts and short
partial camera tracks stay unchanged; reduced motion starts it off.
Optional sound-join fades
soften internal cut edges without shifting words. Optional Readable/Cue/Punch/Karaoke captions
follow saved actual words/corrections and the cut clock. Reversible filler
review offers safe optional removals, initially kept; remaining Director's Cut
tracks are next. Repeated Script sections now have a comparison with original
listening, partial coverage and wording flags. Safe reversible Keep attempt
choices now remove other attempts from video/captions, with Keep all and
Restore all. Owner hardware trials are
deferred until they return.** The build order is in
[product-brief.md](product-brief.md#build-order); it was revised on 2026-09-30.

**New request (2026-10-06):** private talking-point cards for unscripted videos.
**Notes mode is implemented on Windows.** Create a Script or Notes from Home,
or switch aids in the editor/setup. Cards save locally, can be edited/reordered/
removed, and have manual buttons and Ctrl+Shift arrow navigation. Camera,
Screen/Both and the protected companion render cards. New takes reset to card
one; the last card never stops capture, and paused browsing coalesces on resume.
Take metadata freezes the deck and saves card indices on the take clock.
The generated native Arabic Notes recording passes. Owner trials remain
deferred; frozen Script/Notes speech processing is built and Cut work continues.

The owner's first test on Windows (build #1) found: no microphone permission prompt and no
sound in takes; a prompter that scrolled away from the word being read; effects that were too
weak and generic; a generic first screen; and no screen recording yet. Build #2 fixes the first
two (see the session log). The owner confirmed the sound works in build #2, and asked for the
guide choice in the app, which build #4 adds. After trying build #4 the owner asked for the
dot to grow and act out each cue in the cue's colour, and for the next features. The rest is
build step 2 (screen recording).

## Handover (2026-10-05): from here, Codex on the owner's Windows PC

- **Latest checkpoint (2026-10-07, effects after recording):** 815 Flutter
  tests, 260 screenshots and clean analysis. The owner clarified that camera
  emphasis must be addable/removable after recording, including later from a
  saved take. This already uses export-time choices; the save panel now says
  that each save creates a new version and keeps the original and earlier
  videos. New EN/FR/AR disk-reload regressions switch it off/on/off, preserve
  every earlier video/subtitle/history file and original media/words, and use
  frozen cues even after the current library script changes. EN/AR phone
  layouts inspected; normal Windows Release rebuilt. No native behavior,
  dependency, data collection or upload changed. **Half done:** the remaining
  camera movement, blur/cursor, sound/coaching and editor/export work is still
  unfinished. Next keep the paired camera clear of activity/zoom targets,
  then continue the Cut tracks. Owner trials stay deferred; mobile and paid
  launch remain unfinished.

- **Latest checkpoint (2026-10-07, camera emphasis):** 812 Flutter tests,
  260 screenshots and clean analysis. Emphasize the camera starts on for
  aligned Script Camera/Both exports unless system reduced motion is set;
  an explicit switch overrides it. Accepted exact reliable/corrected spoken
  stress triggers a centred 1.12x camera crop on the existing camera spring.
  Original/output and original/retained paired-camera duration must reach
  20 seconds; entrances stay eight output seconds apart. Holds clamp at
  source/camera boundaries and continuous splits stay identical. Notes,
  unaligned/changed/uncertain/unsaid speech and unaccepted cues get no effect.
  Bounded text-free tracks/counts survive local history/recovery without
  rereading later words/camera metadata; hiding the paired camera removes
  its track. Subtitle clocks, screen/frame/targets and camera size/position
  remain independent. Native main/paired wide/portrait decoded crop/return,
  source-cut resets and malformed/short-track rejection pass, along with the
  full render suite. Actual app-channel six EN/FR/AR Camera/Both wide/feed/
  portrait on/off exports preserve exact subtitles/history/original bytes.
  Fixed a discovered native failure-cleanup hang: exception unwinding
  shuts down the owned sink instead of finalizing a broken queue. Generated
  zero/one-sample failures close promptly, and mono/stereo fragmented AAC
  recording checks pass. EN/AR phone and native main/paired PNGs inspected.
  No owner media/input, face guessing, score, dependency, asset or upload.
  Normal Windows Release app restored with the verified cleanup fix.
  **Half done:** camera movement away from targets, directional blur,
  smooth cursor, remaining sound/coaching and editor/export tools remain.
  Next keep the paired camera clear of activity/zoom targets, then continue
  the other Cut tracks. Existing WGC videos have a baked-in cursor: design
  explicit cursor-free capture provenance before drawing a replacement.
  Owner trials stay deferred; mobile and paid launch remain unfinished.

- **Latest checkpoint (2026-10-07, rounded screen frame):** 774 Flutter tests,
  254 screenshots and clean analysis. Frame the screen starts on for Screen/
  Both, including takes without activity; Camera remains unframed. Full
  source content fits inside a fixed 6% inset with radius-md corners, a local
  fixed dark gradient and the existing soft shadow tokens. Zoom crops retain
  their clock; click targets map through the same inset. The native GPU mask
  clears rounded corners/margins, protects the independently composed camera
  and leaves caption/shortcut placement intact. Choice/history/recovery are
  backward compatible (old videos unframed), with unchanged originals.
  Native decoded wide/portrait corners, full-picture bars, inset zooms/clicks
  and fixed camera placement pass; the full render suite passes. Actual
  app-channel 12 EN/FR/AR wide/feed/portrait frame on/off exports preserve
  exact subtitles, independent effects/history and source/activity bytes.
  EN/AR phone and native wide/portrait PNGs inspected. No owner media/input,
  package, wallpaper asset, copied code or upload. Normal Release restored.
  **Half done:** smooth cursor, directional blur, camera
  movement, further sound/coaching and editor/export tools remain. Continue
  these Cut tracks before real voice-follow/mobile. Owner trials stay deferred;
  mobile/paid-launch work remains and the product is unfinished.

- **Latest checkpoint (2026-10-07, shortcut badges):** 754 Flutter tests,
  254 screenshots and clean analysis. Show shortcuts starts on for existing
  local Screen/Both activity, independently of zooms/clicks. Only the existing
  14 Ctrl/Ctrl+Shift chords become fixed LTR glass badges; ordinary key timings
  never become text. Latest badge wins, with retained/reordered output times,
  continuous-split invariance and source-cut lifetime clamps. Immutable local
  tracks/count history and strict recovery survive activity removal without
  private paths. Native private OFL Martian Mono single-line labels pass
  decoded wide/portrait onset, safe bounds, spring rise/fade and rejected
  private labels. Actual Windows app-channel 12 EN/FR/AR wide/feed/portrait
  all/plain/click-only/shortcut-only exports pass exact subtitle clocks,
  tracks/history and unchanged source/activity bytes. EN/AR phone and native
  portrait PNGs inspected; no owner media/input or dependency. Normal Windows
  Release build restored. **Half done:** smooth cursor,
  frame/backdrop/blur and further sound/coaching remain; the full product is
  unfinished. Next finish the screen frame and remaining Cut tracks before
  voice-follow/mobile. Owner hardware trials remain deferred; the design
  artifact needs republishing from docs/design by Claude.

- **Latest checkpoint (2026-10-06, click highlights):** 735 Flutter tests,
  254 screenshots, clean analysis and normal Windows Release build. Highlight
  clicks starts on for local Screen/Both activity, independently of Auto-zoom.
  Fixed amber spring rings/soft halos follow retained visible clicks on the
  output clock; hidden clicks/plain keys/removed activity draw nothing.
  Lifetimes clamp at source cuts; continuous source splits stay identical.
  Resize/current zoom map the target; clips leave margins/camera clear and
  captions draw above it. Immutable pulse history/recovery excludes private
  paths and survives activity removal. Native decoded wide/portrait onset/
  fade passes; camera-covered pulses decode identically to the no-ring baseline.
  Actual Windows app-channel EN/FR/AR wide/feed/portrait independent on/off
  exports pass exact subtitle clocks, tracks/history and original bytes.
  EN/AR phone and native PNGs inspected. No owner media/input or dependency.
  **Half done:** smooth cursor, shortcut badges, frame/backdrop/blur and further
  sound/coaching remain. Continue those Cut tracks before voice-follow/mobile;
  owner hardware trials stay deferred.

- **Latest checkpoint (2026-10-06, spoken pointing zooms):** 726 Flutter tests,
  clean analysis and normal Windows Release build. A reliable actually spoken
  frozen Script phrase near a visible click can now trigger a zoom: English
  here/this button, French ici/ce bouton/cette option, Arabic هنا/هذا الزر/هذه
  الخانة, with normalized language forms. Multiword phrases require complete
  exact reliable/corrected speech in one attempt without added words, sentence
  breaks or long gaps. Notes, absent alignment and uncertain/unsaid words
  supply no bonus. The whole phrase and click must survive the same source
  range; losing the phrase retains ordinary cluster evidence. Actual Windows
  app-channel one-click EN/FR/AR wide/feed/portrait on/off exports pass caption
  clocks, immutable targets/history and unchanged source/activity bytes.
  No new UI surface; 254 screenshot cases remain from the activity zoom slice.
  No owner media/input or dependency. **Half done:** cursor/ripple/keycap/frame
  polish, further sound and full coaching. Continue those Cut tracks before
  voice-follow/mobile; owner trials stay deferred.

- **Latest checkpoint (2026-10-06, screen activity zooms):** 698 Flutter tests,
  254 screenshots, clean analysis and normal Windows Release build. Optional
  Auto-zoom follows bounded nearby clicks/shortcuts and three anonymous typing
  timings with a fresh cursor/focus target. Time/spatial clusters cannot chain
  across the screen; cut/reordered activity retains its source identity.
  Camera-token springs pan overlapping targets and reset at discontinuous
  cuts. Resize coordinates clamp to the visible recording; camera/captions
  keep their layout/clock. Missing/malformed activity retains the full image
  with a generic notice. Immutable target history/recovery excludes private
  paths and survives activity removal. Native geometry and decoded wide/
  portrait zoom/full-return pixels pass; actual Windows app-channel EN/FR/AR
  wide/feed/portrait on/off exports pass subtitles, history and unchanged
  source/activity bytes. EN/AR phone/native PNGs inspected. No owner media/
  input or new dependency. **Half done:** pointing-word zooms, cursor/ripple/
  keycap/frame polish and further sound/coaching remain. Continue these Cut
  tracks before voice-follow/mobile; owner trials remain deferred.

- **Latest checkpoint (2026-10-06, optional sound-join fades):** 669 Flutter
  tests, 254 screenshots, clean analysis and normal Windows Release build.
  Soften sound at cuts starts on for discontinuous internal joins and can be
  switched off. A 20ms total envelope uses 10ms of each retained side without
  overlapping words, amplification or a clock change. Continuous source spans
  and outer edges keep their sound; old history defaults off. Choice/history
  and source/caption clocks pass EN/FR/AR full review/export checks. Native
  mono/stereo, small ranges, packet splitting, decoded join attenuation and
  distant-tone levels pass; whole/contiguous decoded PCM is identical. Actual
  app-channel keep/select/restore exports preserve choices/history and original
  bytes. EN/AR phone PNGs inspected. No owner media/input or new dependency.
  **Half done:** room-tone crossfades, LUFS/noise/de-essing, screen polish,
  automatic best-performance ranking and full coaching remain. Continue the
  screen effects and sound tracks before voice-follow/mobile. Actual listening
  and language/hardware trials stay deferred; mobile/paid-launch work remains.

- **Latest checkpoint (2026-10-06, Cue/Punch delivery captions):** 663 Flutter
  tests, 254 screenshot cases, clean analysis and normal Windows Release build.
  All four styles follow actual
  saved words. Reliable exact frozen Script matches carry accepted stress,
  energy and pace; Notes and changed/added/uncertain words never borrow cues.
  Source-word cue identity survives discarded/reordered attempts. Cue rises at
  actual starts; Punch shows one to three words, with stress alone. Still
  removes transforms/sweeping and starts with system reduced motion. Explicit
  format/style/motion choices survive subsequent format changes and each
  immutable export. SRT/VTT keep complete wording without Arabic decoration.
  Native decoded EN/FR/AR reveal, spring/Still, safe-margin and stress-spacing
  checks pass. Real app-channel Cue/Punch/Karaoke retake exports pass source
  preservation, clock, captions/subtitles and history/reload. EN/AR controls
  and native Arabic portrait PNGs inspected. No owner media or new dependency.
  **Half done:** screen/sound polish, automatic best-performance ranking and
  full coaching remain. Continue those Cut tracks before voice-follow/mobile.
  Real speech/hardware trials and paid-launch work remain; owner testing stays
  deferred. The design artifact needs republishing from docs/design by Claude.

- **Latest checkpoint (2026-10-06, Karaoke video captions):** 636 Flutter
  tests, 230 screenshot cases, clean analysis and normal Windows Release build.
  Caption style now offers Readable/Karaoke. Exact saved word times/ranges
  drive stable dim-to-lit text and progressive amber underlines, reversing
  for RTL glyph runs. No timing is guessed and gaps have no underline. Cut
  decisions, corrections, subtitle phrases and original media stay intact.
  History/recovery remembers each video's style; old records remain Readable.
  Native decoded pixels pass word fill, LTR/RTL progression, safe margins,
  diacritics/mixed Arabic and rejected malformed ranges. Real app-channel
  EN/FR/AR retake selection/restore exports pass exact clocks, captions/SRT,
  style history/reload and original-byte checks. EN/AR phone and Arabic
  portrait video PNGs inspected. No owner media or new dependency used.
  **Half done:** Cue/Punch cue motion, automatic best-performance ranking,
  screen/sound polish and full coaching remain. Next build Cue/Punch before
  the other Cut tracks. Real language/hardware and mobile/paid-launch work
  remain; owner testing stays deferred. Design artifact needs republishing
  from docs/design by a Claude session.

- **Latest checkpoint (2026-10-06, reversible retake selection):** 618 Flutter
  tests, 218 screenshot cases, clean analysis and normal Windows Release build.
  Keep attempt selects a complete frozen Script section only when other
  attempts have confident words and measured quiet cut boundaries. Cues owned
  by retained words remain protected; partial/unsafe buttons stay disabled.
  All attempts start kept. Keep all/Restore all restores choices locally;
  wording changes rebuild with every attempt kept. Quiet/filler preferences
  survive old-plan enrichment and overlapping removals are unioned once.
  Stale saves, forged provenance and oversized plans are rejected. Native
  decoded tone/picture checks and real app-channel EN/FR/AR selection/restore,
  exact export clock, captions/subtitles, history/reload and unchanged original
  bytes pass. EN/AR chosen and unsafe phone PNGs inspected. No owner media used.
  **Half done:** automatic best-performance ranking is still pending. Next
  caption motion, screen/sound polish and full coaching. Mobile/paid-launch
  work and real language/hardware trials remain; owner testing stays deferred.

- **Latest checkpoint (2026-10-06, repeated-section comparison):** 574 Flutter
  tests, 200 screenshot cases, clean analysis and normal Windows Release build.
  Compare attempts derives anchored repeats from the frozen Script in a
  bounded isolate, with actual wording/source times, partial coverage,
  changed/added words and uncertainty. It pages sections/attempts and uses
  explicit original Hear actions. Ordinary scripted repetition, single echoes,
  Notes and absent alignment (including computer-only) remain unscored.
  Stale results cannot replace a wording update. EN/FR/AR fixtures/full review
  checks pass, including later library edits and unchanged cut choices.
  EN/AR partial and FR dark phone PNGs inspected; no owner media used.
  **Half done:** this comparison makes no best-performance choice and removes
  nothing. Next connect safe reversible retake selection, then caption motion,
  screen/sound polish and full coaching. Mobile/paid-launch work and actual
  language/hardware trials remain; owner testing stays deferred.

- **Latest checkpoint (2026-10-06, hear original filler phrases):** 537 Flutter
  tests, 188 screenshot cases and clean analysis. Each Possible filler now has
  **Hear this phrase**: it returns to/reveals the original player, includes
  600ms of context per side, turns preview sound on explicitly and pauses at
  the excerpt's end on the existing 250ms poll. This is a listening aid, not
  a sample-accurate rendered cut preview. Choices/files stay unchanged.
  Scrolling cannot replay old requests; late commands/status, backgrounding,
  replacing and leaving the player are generation guarded. Generated real
  Windows playback and EN/FR/AR screen checks pass; EN/AR phone PNGs inspected.
  No owner media used. Normal Windows Release build restored after native
  fixtures. **Half done:** full retake decisions, caption motion, screen/sound
  polish, coaching and mobile/paid launch remain. Owner trials stay deferred.

- **Latest checkpoint (2026-10-06, reversible filler review):** 525 Flutter
  tests, 188 screenshot cases, clean analysis and normal Windows Release build.
  Filler phrases use the EN/FR/AR lexicon and start kept. Script requires
  added speech absent from the frozen script; Notes stays unscored. Screen,
  accepted pauses/breaths, uncertain words and unsafe boundaries stay intact.
  Measured quiet on both sides is required; no timestamp-only silence guesses.
  Old quiet choices survive review, switch saves reject stale cut revisions,
  and Restore all changes restores gaps and fillers. Only chosen complete
  filler words leave cut captions/video; original transcripts and earlier
  exports remain available. Generated native tone/pixel checks and app-channel
  EN/FR/AR keep/remove/restore/export/history/reload pass; owner media was not
  used. EN/AR phone PNGs were inspected. **Half done:** full retake decisions,
  caption motion, screen/sound polish and delivery coaching remain; actual
  French/Arabic/Darija recognition quality and hardware trials stay deferred.
  Continue those tracks before mobile/paid launch; the app is not finished.

- **Latest checkpoint (2026-10-06, captions on video):** 485 Flutter tests,
  176 screenshot cases, clean analysis and normal Windows Release build.
  The default-enabled **Put captions on video** switch uses complete saved
  actual phrases, including corrections, with bundled display fonts and fixed
  caption tokens. Disabling it preserves SRT/VTT. History records the choice
  and old records remain compatible. Native EN/FR/AR pixel checks pass timing,
  safe margins, two lines, Arabic diacritics/mixed text and padded portrait rows;
  unreadable/control text fails without clipping or retaining an output.
  The real app-channel check passes all four sizes, local history/reload,
  saved playback and cancel cleanup. Phone export EN/AR and generated caption
  PNGs were inspected. No new dependency or owner speech used.
  **Half done:** this is the Readable style; Cue/Punch/Karaoke motion,
  filler/retake decisions, screen/sound polish and coaching remain.
  Owner trials stay deferred; continue those tracks before mobile/paid launch.

- **Latest checkpoint (2026-10-06, transcript wording corrections):** 478 Flutter
  tests, 176 screenshot cases, clean analysis and normal Windows Release build.
  Review wording has bounded pages, low/unknown-confidence flags, one-word editing
  and Restore. EN/FR/AR field direction, validation and restoration pass; Arabic
  wording aligns right and source times show tenths. Corrections preserve the first
  recognized spelling, native confidence and original time interval. New atomic
  word revisions recompute existing frozen Script alignment and rebuild quiet cuts;
  Notes/computer-sound-only stay unscored. Originals and earlier exports stay intact.
  Failed library writes now roll back their own optimistic attachment without
  replacing later edits. Generated Release speech/correction/restore/reload checks
  pass for Script/Notes. **Half done:** no word splitting/merging or time adjustment;
  filler/retake decisions, burned captions, screen/sound polish and coaching remain.
  Owner trials are still deferred; continue the remaining Director's Cut tracks.

- **Playback follow-up (2026-10-06):** background pause now waits for an active
  Play/Seek/Mute command rather than dropping the request. Session generations
  prevent late commands affecting a replacement player; disposal closes safely.
  All 459 Flutter tests, clean analysis and the Windows Release build pass. Automatic-review checkpoint below
  still applies; remaining Cut/coaching work is next and owner trials are deferred.

- **Latest checkpoint (2026-10-06, automatic review after Stop):** 456 Flutter
  tests, 167 screenshot cases, clean analysis and a normal Windows Release build.
  Camera/Screen/Both now open take review directly,
  retain sound/camera warnings and release live camera/preview/microphone meters
  until returning to setup. The default-enabled setting checks an installed
  model only, finds actual words and saves a reversible quiet cut; automatic
  processing never downloads. Missing setup offers the disclosed explicit action.
  Progress/cancel is above the player. Pre-start cancellation and single-job
  ownership pass. Generated Release app-channel checks pass Script/Notes,
  frozen aids, durable words/cuts, reuse and reload. The already verified public
  model is installed in the owner's ignored `local-data/models` on E: and was
  checked for exact size/SHA-256. No owner recording was processed in these checks.
  **Half done:** filler/retake decisions, corrections, captions/screen/sound polish
  and delivery coaching remain. Owner trials are deferred. Build those next;
  Android/iOS and paid-launch/legal work remain later. Do not call the app finished.

- **Latest checkpoint (2026-10-06, first Windows video export):** 443 Flutter
  tests, 161 screenshot cases and clean analysis. Debug/Release native render
  checks pass selected/reordered source, stereo 44.1 kHz resampling, silent
  input, visible aperture, camera inset/end, precise portrait clock, damaged
  input, cancel cleanup and original overwrite protection. The real app-channel
  generated check passes 1080p/4K landscape, portrait and 4:5, Unicode files,
  verified history/reload, paused saved-video playback and full export processor.
  Video is finalized MP4; recordings remain fragmented. Fixed fragment duration
  hints underreporting a 1080p export. Original sound follows the kept clock.
  Export adds local actual SRT/VTT and EDL metadata, reversible revision-bound
  history, progress/cancel and completed-job recovery (including failed caption
  or library saves). Native probes queue across startup/export owners.
  **Half done:** full-picture fitting is available; burned captions, crossfades,
  automatic-on-stop, filler/retake decisions, screen polish, sound cleanup and
  delivery coaching remain. Owner trials are deferred. Next build automatic
  processing after Stop and remaining Cut/coaching pieces. Android/iOS and
  paid-launch/legal work remain later; do not call the product complete.

- **Latest checkpoint (2026-10-06, local take playback):** 430 Flutter tests,
  149 screenshot cases and clean analysis. Windows Debug build and generated
  player check pass: Unicode names, paused first frame, mute, play/pause,
  paused seeking, end, repeated close/reopen and missing/remote rejection.
  Review now has an in-app player with bounded previews and accessible controls.
  MediaPlayer/StorageFile use the Windows platform; no new package or codec.
  URLs, network drives/shares, alternate streams and reparse points are rejected.
  Player ownership handles late opens/disposal, and errors never show/log paths.
  Owner trials remain deferred. **Next:** native streaming render and local
  video export, then automatic processing, the remaining Cut tracks and coaching.

- **Latest checkpoint (2026-10-06, reversible quiet cuts):** 422 Flutter tests
  and 145 screenshot cases pass, with clean analysis. Native generated speech
  now also measures quiet audio on the original clock and verifies a reversible
  cut over the 70-second fixture without losing any recognized word.
  Camera Script/Notes takes can create a durable quiet-gap plan in take review;
  each removal has an on/off switch and Restore all. Accepted marked gaps and
  breaths are fully protected, as are words and low-confidence neighbourhoods.
  Missing frozen Script alignment, no measured evidence, no speech and Screen
  context keep the original. Captions move onto the kept output clock.
  Take duration now preserves microseconds across disk, with old millisecond
  records still supported. New transcripts invalidate old cut references;
  saving cuts preserves later script edits and rejects changed word revisions.
  **Half done:** this is a plan and subtitle timing, not video export. Native
  streaming render, preview, automatic-on-stop, fillers/retakes, screen polish
  and delivery review remain. Build those next; owner trials remain deferred.

- **Latest checkpoint (2026-10-06, offline speech runtime):** 396 Flutter tests
  and 139 screenshot cases pass; analysis prints No issues found. Normal Windows
  Release speech-channel check passes verified model/pre-start cancel, frozen
  Script versus Notes, durable results/captions and three bounded windows over a
  generated 70-second WAV with long gaps. Windows Debug/Release builds pass.
  DTW audio-attention boundaries replaced unstable regular token estimates;
  no equally-spaced words or script text was invented. Native model/context and
  bounded PCM stay off the UI thread, Dart assembly/alignment runs in an isolate.
  Runtime/model MIT notices are bundled/registered, first use explains the
  148 MB public download, takes up to 24 hours and keeping originals locally.
  Original media stays untouched; rejected timings require retry/review.
  Actual French/Arabic/Darija quality and long real takes are still unverified.
  **Half done:** processing is an explicit take-review action; automatic-on-stop,
  correction/confidence decisions, full Cut/render/export and coaching are next.
  Owner trials remain deferred. The private design artifact is behind source docs.

- **Latest checkpoint (2026-10-06, Notes implementation):** 371 Flutter tests and
  130 screenshot cases pass; Windows Debug and Release builds pass. Generated
  native Notes recording verifies the protected Arabic reader/companion,
  native shortcut dispatch, pause coalescing, frozen deck/card clock, last-card
  behavior and cleanup. The owner can try Notes later as requested. No new
  dependency. Speech setup/processing, Director's Cut, captions/export and
  coaching remain unfinished; do not describe the product as complete.
  Notes choices do not change the approved Script defaults. Added camera-only
  aid snapshots; camera plugin crash recovery is still more limited than Screen.
  Library writes are serialized, and unreadable documents never log private text.

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
  **No issues found!**; all **347 tests pass** (226 before Screen integration).
  All **112 screenshot cases pass**, including the source picker, unavailable-preview
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
- **Resume here (screen recorder slice 6, capture/save pipeline):** the dedicated MTA
  worker now captures the selected window/display on the GPU and writes H.264 + optional
  chosen-microphone AAC against a common QPC clock. Output fits the initial aspect ratio
  within a 1920 px long edge at 30 fps; source resizing is letterboxed and a static source
  keeps its latest frame. Startup waits for a real frame before creating a file; stop
  finalizes outside the UI thread. Closed/minimized sources stop with a recoverable result.
  Microphone access/loss, missing timestamps or sample loss produce explicit reasons.
  `spawnalpha/screen_recording` and the tested Dart `ScreenRecordings` backend expose
  start/status/stop with session guards. This pipeline is not enabled in the setup UI yet.
  Native checks record only a generated-color fixture window, including resize, normal
  stop, real default-microphone PCM/AAC and source closure/minimization; saved outputs
  decode with ordered times and close audio/video endpoints. Output stays in ignored
  `app/build/encoder-fixtures`; no private window titles or samples are logged.
  Durable take metadata/recovery, capture-excluded HUD/countdown, synchronized floating
  reader and Screen/Both setup integration are next. Sound core was pushed in `9652e11`.
- **Resume here (screen recorder slice 7, durable takes/recovery):** `ScreenTakeStore`
  flushes a local pending manifest before capture, including the script/presentation
  version, source name/kind/size and explicit audio choice; it excludes native source IDs,
  old takes, suggestions and keys. Finish verifies a decoded frame and file details on
  a native worker before saving the library and marking the manifest complete. Startup
  recovers readable pending videos without duplicating takes, resurrecting deleted scripts
  or replacing later script edits. Unreadable files remain local for retry. Recovery is
  serialized with new reservations/finishes and never follows arbitrary manifest paths
  or video symlinks. Take now records mode, metadata path, optional camera path and a
  recovered flag; legacy camera takes still load. EN/FR/AR snapshot, crash/retry, failed
  library write and path/deletion tests pass. Native probing reads an unfinished generated
  fragmented MP4 correctly, including its visible aperture rather than decoder padding.
  Startup recovery is wired; no screen mode is enabled yet. Excluded HUD/countdown,
  recording-time floating reader and Screen/Both setup integration remain next.
  Capture/save pipeline was pushed in `f16d256`.
- **Resume here (screen recorder slice 8, real pause/resume):** the recording clock now
  removes paused intervals from both video cadence and microphone timestamps, trimming
  audio packets that cross pause/resume boundaries. Recording continues to monitor source
  and microphone availability while paused; picture writes and saved duration stop, while
  the live meter can still move. Native generated-window checks with and without real
  default-microphone AAC verify an unchanged paused timer/frame count, removed pause gap
  and aligned decoded audio/video endpoints after resume. Pure C++ clock checks cover
  pre-start trim, crossed boundaries and repeated pauses. The guarded Dart/native pause
  API is ready; controls/setup integration remain next. Durable recovery was pushed in
  `fc8f608`.
- **Resume here (screen recorder slice 9, excluded HUD/countdown):** a separate retained
  `recordingHudMain` Flutter engine renders the countdown and recording HUD. The native
  host verifies HUD and main/setup window capture exclusion before visibility; close
  restores the owner's previous affinity. Countdown centres on the source and the HUD
  docks at the source display's bottom. It shows tally/time, selected microphone/meter,
  Pause/Resume, Stop and reader visibility/Lock controls. Only controls and the drag grip
  take mouse input; other HUD areas use native click-through, with transient cursor
  checks and no hooks/logging. Rounded bounds and input/layout timing use design tokens.
  EN/FR/AR microphone layout/control tests pass, and countdown-to-HUD resizing keeps the
  old state usable for its transition frame. `tool/native_hud_check.dart` is a memory-only
  smoke launcher: no script, file, microphone or capture access. It checks visibility,
  exclusion, phase/docking updates, close/reopen and main-window affinity restoration.
  Reader synchronization, recording controls integration and Screen/Both setup enablement
  remain next; the HUD is not accessible from normal setup yet. Pause was pushed in
  `4890fc8`. Real HUD click-through/placement and owner trials remain pending.
- **Resume here (screen recorder slice 10, normal Screen mode):** Screen is enabled in
  Home and record setup and remembered per device. Setup has a chosen-source live preview
  and the existing mic/check/guide/motion/alignment/pace choices; no camera is required.
  `ScreenTakeController` owns preparation, verified exclusion of main/HUD/reader,
  countdown, flushed manifest, native capture, pause/resume, stopping, file verification
  and save. The native release acknowledgement joins the worker before unprotecting the
  main window. Cancellation/disposal keeps late windows/capture replies under that owner;
  a failed release retains protection and blocks another take. Voice uses the recording
  microphone's own levels; the reader holds during Pause, resumes at the same word and
  does not stop a screen take at the end of the script. Reader visibility and Lock work
  from the HUD. A missing microphone requires an explicit Record without sound choice,
  which uses Timed pace; partial source/microphone stops save readable video with a warning.
  Takes show their mode and recovered state. Preview route handoff/reopen is tested.
  `tool/native_screen_take_check.dart` captures only a separate generated blue fixture
  window, silently, into ignored `app/build/screen-ui-fixtures`: real protected windows,
  countdown, pause gap removal, reader hide/show, durable save and cleanup all pass.
  No owner data or private desktop/camera/mic is used by that launcher. Analysis is clean,
  all 239 tests and 84 screenshots pass; EN/AR setup PNGs were inspected and button
  contrast/Arabic metadata typography corrected. HUD slice was pushed in `cbfdad5`.
  **Next:** Screen + camera with separate crash-safe files and a shared pause clock;
  then system audio, companion and privacy-limited telemetry. Both remains disabled.
- **Resume here (screen recorder slice 11, paired video core):** the native recorder
  opens the exact chosen camera through Media Foundation and writes a separate silent
  fragmented camera MP4. Screen and camera share every frame timestamp and pause gap;
  microphone sound remains in the screen file. No fallback from a missing camera.
  Asynchronous frames own their pixels, handle first-frame format/stride changes, and
  drain before device release. Native generated-video checks pass normal pair capture,
  stop while paused, camera loss, repeated camera open/close and plain Screen regression.
  Dart validates paired arguments, camera counts and camera-loss status. No owner camera,
  private desktop or microphone was used for these paired checks; fixtures stay ignored.
  Analysis is clean, 242 tests pass and the normal Windows debug build succeeds.
  **Half done:** the paired capture core is ready, but Both stays disabled until paired
  manifests/recovery, excluded live camera bubble and normal setup/control wiring work.
  Continue those next; the owner authorized continued work and will try everything later.
- **Resume here (screen recorder slice 12, paired storage/recovery):** `ScreenTakeStore`
  reserves both new local paths and flushes the chosen camera's display name and exact
  presentation before capture. It verifies the files separately and saves Both with
  both paths and independent dimensions/durations. Camera audio is not duplicated.
  Missing/unreadable camera output keeps the useful Screen take, marks cameraReadable
  false in the local Both manifest, and preserves camera bytes. Recovery rejects external
  camera paths/links, preserves later edits, and retries failed library saves without
  duplicate pairs. EN/FR/AR and partial/retry tests pass; analysis is clean, 249 tests pass.
  Native core slice 11 was pushed in `149e27c`. **Next:** excluded live camera bubble,
  paired controller/setup and a clear partial-camera warning; Both is still disabled.
- **Resume here (screen recorder slice 13, excluded camera bubble):** a separate
  circular Flutter/native self-view verifies exclusion before its first visible frame.
  It reads owned camera snapshots from the recording core, converts only preview pixels
  to a leased Flutter texture, and opens no second device. It starts beside the reader,
  supports dragging and preview-only Hide, and receives only display name/geometry.
  Both saved videos pause while its live framing feed continues; native generated-frame
  checks verify this and retained snapshots after stop. The native window smoke check
  passes exclusion-before-visibility, stale close and repeated open/close without opening
  the owner's camera. EN/FR/AR layout/control tests and six screenshots pass; the small
  privacy label was simplified after PNG inspection. Analysis is clean, 256 tests and
  90 screenshot cases pass; Windows builds. Slice 12 was pushed in `fdeef2b`.
  **Next:** connect bubble ownership/partial warnings and selected-camera handoff to
  normal Both setup, then owner camera/microphone trials. Both remains disabled so far.
- **Resume here (screen recorder slice 14, normal Both mode):** Both is enabled in
  Home/setup and remembered. Setup shows the chosen friendly camera name, a circular
  framing preview, source preview and the existing microphone/reader choices. It uses
  preview-only camera access, then disposes that device before protected countdown/native
  capture so the exact chosen link can be reopened once by the recorder. Late preview
  opens are generation-guarded. Missing camera/source prevents Record; a missing mic
  still requires an explicit silent choice. Stop/Cancel stays available after releasing
  setup camera. HUD/reader/bubble exclusion is required before capture and checked while
  recording. Native release joins finalization before closing overlays/unprotecting setup.
  Paired output is saved durably; unreadable camera output keeps Screen and warns plainly.
  EN/FR/AR choice/snapshot/layout/cleanup tests and screenshots pass. Fixed natural Arabic
  title height after PNG inspection so it no longer covers the Stage label.
  `tool/native_paired_take_check.dart` plus the explicit **non-shipping** CMake target
  `paired_ui_fixture` uses only a generated camera MP4 and synthetic source window,
  memory script/library and ignored files. The full protected countdown, live bubble,
  pause/resume, reader visibility/Lock, two verified files on one clock, durable pair
  and restored main affinity all pass. This caught and fixed a live-frame startup bug:
  Win32Window::Create first calls OnDestroy, so the bubble recreates its pixel holder
  in OnCreate. Preview begins only once the recorder is ready. Temporary native tracing
  was removed; no owner camera/mic/private desktop was captured. Analysis is clean,
  270 tests and 93 screenshots pass; native full-pair check passes twice after the fix.
  Normal Windows debug and release builds succeed; the fixture binary is excluded from
  normal builds. Restore a normal launch from `app/` after using the explicit test target.
  **Half done:** owner hardware/placement/exclusion/partial trials are still deferred;
  system audio, cursor companion, privacy-limited telemetry and render-core spike remain.
  Slice 13 was pushed in `a77fcff`. Next: try Both with the owner's real chosen camera
  and microphone when they return; continue the remaining step-2 features in small pieces.
- **Resume here (screen recorder slice 15, computer-sound core):** WASAPI loopback
  pins Windows' default playback endpoint and supplies stereo PCM16 at 48 kHz. The
  bounded shared-clock mixer combines optional chosen-microphone voice with playback,
  preserves stereo/idle silence, removes common pauses and saturates coincident peaks.
  Microphone meter/Voice activity stay microphone-only. Startup/device/timestamp errors
  are explicit; safe stop flushes mixed audio to the saved video end. Seven generated
  full-pipeline checks pass playback-only, mixed, both pause cases, idle, missing and
  lost playback, with decoded tone/channel/duration checks and no real audio saved.
  Pure mixer checks pass; real loopback format/lifetime check discards all samples in
  memory. Analysis is clean, 272 tests pass and the normal Windows debug build succeeds.
  Slice 14 was pushed in `fdc200f`. **Half done:** native/Dart sound core is ready;
  normal setup stays off until the explicit off-by-default Computer sound switch,
  frozen controller choice and durable audio metadata/warnings are connected. Continue
  that next; owner testing is deferred again by request (2026-10-06).
- **Resume here (screen recorder slice 16, normal computer sound):** Screen/Both
  setup offers Computer sound, off on each visit and frozen for the take. Its caption
  explains the default Windows playback mix, including other apps, and local storage.
  Camera mode never uses it; wide and narrower Windows layouts both expose the choice.
  Playback alone still requires Record without microphone and uses Timed pace. HUD
  says Computer sound only instead of Without sound, keeps the mic meter empty and
  shows a sound-on icon. Microphone levels alone drive Voice. Pending/saved/recovered
  manifests preserve the separate audio choices, scope, frames/strongest level, without
  playback IDs. Quiet sound/start failure/device loss warn plainly and keep local
  recovery. Saved Screen/Both warnings use a general warning title/icon so camera or
  playback failure is not labelled as microphone failure. Changing the default playback
  endpoint stops the pinned stream safely.
  EN/FR/AR choice/snapshot/recovery/control tests pass; narrower setup is checked too.
  All 281 tests and 97 screenshots pass; analysis prints No issues found! Normal Windows
  debug and release builds succeed. Inspected
  EN/AR setup and computer-only HUD PNGs; waited for the switch animation for on-state
  screenshots. The explicit non-shipping audio_ui_fixture links generated endpoints
  and requires a native handshake before capture. Full protected countdown/reader/HUD,
  computer sound without microphone/Voice activity, common pause, durable take and
  cleanup pass; no real playback/microphone content is saved in fixture files.
  Slice 15 was pushed in `bc420fe`. **Half done:** owner actual camera/mic/playback,
  default-output change, placement and exclusion trials remain deferred by request.
  **Next:** cursor companion, privacy-limited telemetry, then the render-core spike.
  Restore the normal main.dart launch after the explicit audio test target.
- **Cursor companion (seventeenth slice, 2026-10-06):** Companion in the recording HUD
  changes the existing reader to a compact card without changing its word, pause state,
  guide, alignment or mirror. Native spring-follow movement trails away from direction,
  flips/clamps at work-area edges (including negative-coordinate monitors), ignores hand
  jitter and docks after two seconds of rest. The following card is click-through;
  hiding it, switching off, reduced motion or teardown releases pointer sampling.
  Camera use asks Keep docked / Follow anyway in the capture-excluded HUD, remembers the
  answer locally and shows Eyes to the lens when following. The docked card's Follow
  anyway and HUD's camera-choice control reopen that protected panel; Pause/Stop remain
  available. No cursor history, typed input, device IDs, recording paths or keys reach
  the child. No new dependency, copied code or network use.
  Pure native checks cover direction, four edges, jitter/rest, monitor changes, small
  work areas and delayed frames. All 301 tests and 109 layouts pass; analysis is clean.
  Long phrases step within the compact viewport so the current word stays visible;
  full readers keep their existing One phrase behaviour. A stale visibility poll cannot
  undo a Hide click. The native glass restores click-through after showing again.
  The generated protected paired take verifies camera docking/following, click-through,
  reduced-motion docking, hide/show sampling cleanup, one durable pair and release.
  EN/FR/AR compact and docked layouts plus the camera warning were inspected.
  **Half done:** owner comfort, real capture-exclusion/placement, multiple-monitor DPI,
  camera/microphone/playback trials remain deferred at their request. Pointer telemetry
  is not built. **Next:** privacy-limited cursor/click/key timing, longer/crash recording
  checks, then the render-core spike. Leave the normal app open for later trials.
  Design tokens, recording spec and component notes are current. The private Claude
  artifact needs republishing; its illustrative browser preview remains scaled.
  The optional browser-preview renderer could not run because Playwright is absent;
  actual Flutter screenshots provide the verified layouts.
- **Optional activity and recorder hardening (eighteenth slice, 2026-10-06):**
  Screen/Both setup offers Activity for automatic edits, initially off, with an explicit
  local-only caption. A source-scoped raw-input receiver saves anonymous key timing,
  whitelisted Ctrl badges, clicks, focus rectangles and 60 Hz cursor positions/shapes;
  it never saves typed characters, scan codes, device IDs, handles or window titles.
  Own-process controls/readers are excluded. The bounded sanitized queue shares the video
  pause clock; its JSONL sidecar is reserved in the pending manifest and flushed each second.
  Failure stops safely; old/off takes work without activity. Streaming inspection and
  recovery reject substituted paths/links/private payloads, preserve malformed bytes and
  still save readable video. A crash exposed activity extending past the last surviving
  video fragment: usable activity now clips to the decoded duration without rewriting bytes.
  All 321 tests and 112 screenshots pass; analysis prints No issues found!; normal Windows
  debug/release builds pass. EN/AR activity setup images were inspected. Pure privacy/clock
  checks and a real receiver lifecycle test pass; the latter excludes all own-window input
  and discards samples in memory. The full non-shipping activity fixture substitutes generated
  records only and verifies pause removal, durable counts and protected-window cleanup.
  A deliberate full-process exit leaves actual fragmented video and flushed activity; reopening
  recovers the pair once. A 30-second generated-window take with resize and three pauses decodes
  correctly and shows 0 MiB additional private-memory growth after warm-up. This is a short soak,
  not proof of hour-long performance. No owner desktop/typing/camera/sound was saved in checks.
  Native core is pushed in d0571fd; UI/storage/recovery integration is pushed in 5d6d382.
  **Half done:** owner hardware, multi-monitor DPI, capture-exclusion and longer real-session
  trials remain deferred by request. Native cursor is still baked into raw WGC video;
  replacement/smoothing must be designed alongside the Cut's clean-source preview.
  **Next:** the approved native render-core spike, then on-device word alignment (build step 3).
- **Render-core risk spike (nineteenth slice, 2026-10-06):** the explicit, non-shipping
  render_core_check target generates its own four-second H.264/AAC source, reads two
  GPU-backed tracks, crops/zooms/composites and joins [1s,2s) with [3s,4s). The saved result
  decodes to 60 ordered frames with verified pixels and the correct 440/880 Hz sound;
  skipped 220/660 Hz sound is absent. Debug and Release pass; Release renders this
  two-second 640 x 360 cut in about 0.44 seconds. No new dependency, copied code, bundled
  codec or owner capture. Decoder frame-interval selection and releasing all COM/GPU
  objects before shutdown fixed issues found by the spike. Read render-core-spike.md
  for scope, limitations and reproduction; this is not a shipping Cut/preview/export UI.
  A pure immutable portable cut plan now validates EN/FR/AR, source intervals, joins,
  retake reordering and JSON round trips without file paths or platform fields.
  Final activity hardening (pushed in 3ad86d5) excludes reserved reader shortcuts, tracks modifiers in
  event order, skips typing from windows spanning outside the selected display, and
  tolerates sub-millisecond container rounding without hiding truncated activity.
  An unavailable receiver gives a plain Switch Activity off retry message.
  All 328 tests and 112 layout cases pass; analysis is clean; normal release builds pass.
  **Half done:** owner hardware/comfort/exclusion/multi-monitor and hour-long trials
  are still deferred. Styled Cut captions/masks/blur, clean cursor sources, bounded PCM
  export/preview/cancellation and mobile render implementations are not built.
  **Next build step:** on-device word transcription/alignment (step 3), followed by
  Director's Cut (step 4). Keep all new tool/runtime/model files on E: and licence-check
  any speech model/dependency before adding it. The normal main.dart app is open at
  1280 x 720 for the owner's later trial; do not leave a fixture launch target active.
- **Word timing foundation (twentieth slice, 2026-10-06):** immutable timed words,
  fragmented UTF-8 assembly and bounded EN/FR/AR alignment preserve changed, added,
  missed and repeated speech. Three-word anchors on both attempts prevent a lone
  common word/stutter or initial script deletion from becoming an invented retake.
  The explicit, non-shipping native speech project uses pinned MIT runtime/model
  inputs, SHA-256 verified on E:, and notices retained. Generated local WAV and
  stereo AAC/MP4 recognition, preserved clock gaps, active/pre-start cancellation,
  and actual native-fragment-to-Dart-script matching pass without private logs,
  owner audio, devices, remote media, FFmpeg or Python. No normal app model download
  or processing channel has been added. See word-timing.md for exact scope/reproduction.
  Analysis is clean and all 347 tests pass; no UI changed since the 112 layout checks.
  The normal main.dart app remains running for the deferred owner recording trial.
  **Half done:** native PCM is capped at 15 minutes for this prototype; word timings
  are estimates. Model setup, chunked background jobs, durable results/progress/retry,
  confidence flags and real French/Arabic/Darija quality checks remain to build/test.
  **Next:** complete that step-3 app integration against each take's immutable snapshot;
  then step 4's Director's Cut. Keep all runtimes/models/files on E: on this PC.
- **Private speaker notes request (2026-10-06):** the owner wants a presentation-like
  aid with reminders instead of a full script, visible only to the speaker, with
  a button/shortcut to advance. Recorded the planned **Notes** mode alongside
  **Script**, independently of Camera/Screen/Both. One title/bullet card at a time,
  Previous/Next and the existing Ctrl+Shift arrow chords; the last card never
  ends a take. Reuse the protected reader, EN/FR/AR directionality and existing
  tokens. Notes captions follow actual speech; no verbatim-script mismatch scoring.
  Product brief, recording/auto-edit design and privacy notes are updated.
  **Done:** design/specification only; code, tests and screenshots are unchanged
  from the 347-test/112-layout checkpoint. The private design artifact is behind.
  **Not built:** deck storage/editor, manual navigation, protected notes UI,
  record-time snapshots/card events and aid-aware speech processing.
  **Next:** implement the immutable text deck and pure card controller with
  EN/FR/AR tests, then the editor/Stage window and shortcut/capture-exclusion trial;
  continue step-3 model/background processing after that. No new dependency.
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
| Excluded floating prompter | Built/tested and connected to Screen/Both recording, native exclusion and protected take checks pass; owner placement/shortcut trials deferred |
| Screen and Screen + camera recording, cursor companion, telemetry | Screen and Both enabled; complete generated protected takes pass, chosen mic/camera, optional computer sound, shared pause, separate files and save/recovery built/tested. Protected companion connected with camera choice and reduced motion. Optional scoped activity and partial recovery are connected/tested; owner hardware trials deferred. |
| Director's Cut (auto-edit, captions, auto-zoom, finish screen) | Designed (`docs/design/autoedit.md`). Native decode/compose/cut/AAC spike and portable EDL foundation pass; full alignment, exporter and finish UI remain to build. |

347 tests pass (`cd app && flutter test`), 112 screenshot cases pass, and `flutter analyze` is clean.

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
3. **Design v3 recording surfaces are built:** the floating prompter, HUD, camera bubble
   and cursor companion are connected in build step 2; owner trials are deferred.
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
7. In-app Windows take playback and first local video export are built. Remaining
   polish includes an easier way to extend pace/energy spans beyond one sentence.
8. **The original build step 2 is implemented and checked locally; owner hardware trials remain deferred:**
   - Camera, Screen, and Screen + camera.
   - The prompter window, HUD and cursor companion, all hidden from capture.
   - Cursor, click and key-burst telemetry.
   - Fragmented MP4.
   - Native render-core spike: done; see `render-core-spike.md`. Full Cut remains step 4.

   **New recorder extension:** Notes mode is built, with deck/editor/practice,
   protected Stage, buttons/shortcuts, take snapshots and card clocks.
   Owner trials of cards and actual capture exclusion remain deferred;
   see `design/speaker-notes.md`.

   **Build step 3 is available on Windows:** verified model setup, bounded
   cancellable background recognition and durable frozen-aid word results pass;
   take review exports SRT/VTT. See `word-timing.md` for estimated timings and
   remaining real-language quality trials. Step 4 now has reversible quiet cuts
   and local video export with Readable/Cue/Punch/Karaoke captions, reversible filler review and
   automatic processing after Stop. Repeated sections now offer a paged
   comparison, original listening and safe reversible Keep attempt choices.
   Automatic best-performance ranking is still pending. Next
   remaining camera/cursor/blur effects and sound polish/delivery
   coaching; optional activity zooms, click rings, shortcut badges and short
   sound-join fades, rounded local screen frames and gentle camera emphasis
   are connected.
   Keep originals intact.
   See OpenScreen in the brief for reusable parts.

## Decisions

- 2026-10-07, effects after recording: the owner requires camera emphasis to
  be addable/removable after Stop and later from a reopened saved take. Effects
  are chosen for each new export; originals and earlier saved videos stay
  intact. Make this explicit in the save panel. Re-recording is unnecessary,
  and changing the current script does not replace the take's frozen cues.

- 2026-10-07, camera emphasis: offer a separate Emphasize the camera choice
  for aligned Script Camera/Both exports, initially on unless system reduced
  motion is requested. Use accepted actually spoken exact reliable/corrected
  stress, a centred 1.12x existing camera spring, minimum original/output
  duration of 20 seconds and eight seconds between entrances. Partial paired
  camera original/retained duration must also reach 20 seconds. Clamp returns
  to source/camera boundaries; keep rectangle, screen and captions independent.
  Save bounded immutable time/zoom pairs/count without words or face targets;
  old exports have zero camera accents. Notes remain unscored.

- 2026-10-07, screen frame: offer a separate default-on Frame the screen export
  choice for Screen/Both, with or without activity. Fit the full picture in a
  token 6% inset, radius-md and existing soft shadows over a generated fixed
  dark gradient. Keep camera size/position and caption clocks independent;
  map clicks through the same inset. Save the boolean per immutable video;
  old exports remain unframed. No wallpaper assets or downloads.

- 2026-10-07, shortcut badges: offer an independent default-on Show shortcuts
  export choice for existing Screen/Both activity. Use only the disclosed
  allowlisted modifier labels, fixed LTR Martian Mono top-left glass and
  existing safe zones/spring tokens. Latest chord replaces the previous badge;
  source cuts clamp it. Save bounded immutable times/labels/count without
  private paths. Ordinary typing never becomes text. Screen frames follow.

- 2026-10-06, click highlights: offer a separate default-on export choice for
  retained visible Screen/Both clicks. Use fixed amber/spring design tokens,
  source-aware timing/crop geometry and camera/caption protection. Store the
  normalized pulse track/count per immutable video; no text/key identities or
  private paths. Switching off restores the plain video for this export.

- 2026-10-06, pointing-word zooms: use the normalized EN/FR/AR lexicon and
  reliable/corrected actually spoken frozen Script phrases near a visible
  click. Require whole retained source evidence, never Notes/unsaid text.
  The ordinary Auto-zoom choice controls this too; no transcript text enters
  portable target metadata. Unusable alignment leaves activity clusters intact.

- 2026-10-06, Windows activity zooms: offer optional Auto-zoom for Screen/Both
  with existing local activity, initially on. Use bounded measured nearby
  clicks/shortcuts/typing and existing camera springs; never invent targets
  or read typed characters. Keep the full picture when disabled or activity
  is unavailable. Store exact targets/count per immutable video, so recovery
  and captions preserve the same output clock. Cursor/frame work follows.

- 2026-10-06, first sound polish: optional de-click fades at discontinuous
  internal joins, enabled for new cut exports and saved per video. Keep the
  source/word/caption clock exact and continuous/outer edges intact. This is
  a join envelope, not the future room-tone crossfade or noise/LUFS processor.

- 2026-10-06, delivery captions: offer all four Windows styles. Cue starts for
  wide/feed and Punch for portrait until a person chooses a style; preserve
  explicit choices thereafter. Still starts with system reduced motion and
  stays optional. Only reliable exact/corrected frozen Script matches carry
  accepted cues, mapped from original source identity through every cut. Notes
  and changed/added/uncertain speech keep wording without borrowed cues. Arabic
  decoration belongs only to video display, never saved words or subtitles.

- 2026-10-06, Karaoke export: offer a separate style using exact saved spoken
  word intervals on the kept clock, with stable shaping and a directional
  underline. Keep Readable as the initial style until Cue/Punch are complete.
  Store choices with immutable exports; no timing or text is manufactured.

- 2026-10-06, first retake selection: start with all attempts kept. Explicit
  Keep attempt requires a complete kept section and safely removable others;
  measured quiet and recognized confidence gate removals. Preserve cues owned
  by retained words; discarded attempts may leave with their own cue gaps.
  Notes, Screen and computer-only remain protected. Restore choices without
  touching original media, full recognition or earlier exports. No automatic
  delivery-quality claim is inferred from script matching alone.

- 2026-10-06, first retake comparison: show factual frozen Script coverage,
  actual wording, uncertainty and source-clock listening. Keep all attempts
  until reversible selection exists; do not label word-match counts a delivery
  grade or best attempt. Notes and computer-only remain unscored. This is an
  implementation stage, not a change to the approved full retake goal.

- 2026-10-06, first filler implementation: vocabulary alone does not establish
  an unwanted hesitation, particularly "like", "du coup" or "يعني". Proposals
  are kept until individually chosen. Require confidence and measured quiet
  boundaries; preserve Script words/accepted cues and Screen context. Notes
  stays free speech. This conservative first policy awaits real-language trials.

- 2026-10-06, implementation of the approved after-Stop workflow: **Make a cut
  after recording** starts enabled and can be switched off. It verifies existing
  offline weights without a download, then saves actual speech and reversible
  cuts locally. Missing setup requires the explicit disclosed model action.
  Reopening a take preserves existing words/cut choices; originals stay intact.

- 2026-10-06, initial Cut guardrails: automatic cleaning requires measured quiet
  frames (20ms, RMS/peak at most -60 dBFS), never just an estimated word gap.
  Keep marked pauses/breaths and uncertain word neighbourhoods. Screen context
  stays intact until activity review is connected. Every removal is reversible;
  the original media is never changed. No retake/emphasis/loudness claim is made
  by the first quiet-gap pass.

- 2026-10-06, speech implementation: use pinned multilingual base weights as
  the Windows offline starting model, pending real French/Arabic/Darija trials.
  Use CPU audio-attention alignment with bounded windows and exact take offsets;
  never repair conflicts by shifting/dropping/inventing words. Keep recognition
  offline; only public model weights download explicitly at first use. Originals,
  frozen aids and words stay local. Explicit no-microphone Screen takes can have
  computer-sound captions, but never speaker delivery/script-adherence scores.

- 2026-10-06, implementation: Notes share a library document with an explicit
  recording-aid enum and an immutable deck; switching back preserves the script.
  Legacy documents default to Script. Notes never enter verbatim script scoring.
  Card indices use the existing take clock (Screen sampled at recording-poll
  precision), separate from optional Activity. Camera snapshots are local too.

- 2026-10-06, the owner: add private presentation-like talking-point cards for
  unscripted videos, with button or shortcut advancement. Implement as an
  additional Notes aid beside Script; recording mode remains Camera/Screen/Both.
  Notes are reminders, not a verbatim script: speech-based captions and review
  must preserve that distinction. The first slice is local text cards.

- 2026-10-06, step-3 technical prototype: pinned MIT upstream speech runtime and
  converted multilingual base weights for generated checks only. No final model
  quality/default decision or fine-tuned Darija licence approval. Keep processing
  on the device; register runtime/model notices before normal app integration.

- 2026-10-06, implementation direction: Windows rendering starts with the existing
  C++ Media Foundation/D3D11 stack; the generated GPU cut/zoom/inset/AAC spike passes
  without introducing FFmpeg or another runtime. Keep the EDL renderer-independent.
  The final cross-platform native/FFI boundary is still open. Activity is initially
  off per setup visit; its defaults still need the owner's deferred trial.

- 2026-10-06, Windows implementation of the approved companion design: reuse the
  existing reader/timeline, keep the camera card docked until an explicit follow choice,
  and store only that choice. Compact phrases step within their viewport when needed;
  regular readers retain their original phrase layout. Reduced motion keeps it docked.

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

- The Windows native render candidate passes; settle the mobile GPU/codec backends and
  final native/FFI boundary when the full Cut exporter is built.
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
  the native screen/audio save pipeline passes tests. Screen and Both are enabled with
  separate camera capture and common pause timing; actual chosen-camera hardware trials
  are deferred. Computer sound is enabled by explicit per-visit choice and captures
  the default Windows playback mix, not app-specific or other-device audio. Default
  playback changes stop safely; the owner's routing/disconnection trial is pending.
- Live preview uses an 8-bit SDR, 15 fps CPU readback path. Full-display preview can show
  recursion because the setup/preview window is not excluded yet. The recording GPU/
  platform-encoder pipeline and protected main/HUD/reader pass native tests and are
  connected to Screen mode. Live picker thumbnails and HDR capture remain pending.
- Companion's movement/edge logic and protected native placement pass automated checks.
  Owner comfort and real multiple-monitor/DPI placement remain to try; trials are deferred.
- The on-device markup is heuristic. For example, French and Arabic stress rules are based on
  word lists, not prosody.

## Session log

- 2026-10-07, saved-take effect choices:
  - Clarified the existing post-recording effect choices in the design, brief
    and save panel. Each save makes a new version without replacing earlier
    videos or original recordings.
  - Added EN/FR/AR saved-take disk-reload off/on/off regression checks,
    including later library script edits, unchanged subtitle clocks, complete
    history and byte preservation. All 815 Flutter tests and 260 screenshots
    pass; analysis is clean. EN/AR phone PNGs inspected and normal Windows
    Release rebuilt. Native effect behavior is unchanged from the verified
    camera-emphasis checkpoint. Owner trials remain deferred; remaining Cut,
    mobile and launch work continues from the handover above.

- 2026-10-07, camera emphasis and failed-export cleanup:
  - Added trusted frozen Script stress planning, cut/reorder/continuous clocks,
    short/partial-camera gates, independent export choice and reduced motion.
    No Notes/uncertain/changed/unaligned speech borrows emphasis. Bounded local
    tracks/count history/recovery preserve originals and exact subtitles.
  - Native separate centred camera crops reuse camera springs, leaving the
    main screen frame/targets and fitted camera rectangle fixed. Source cuts
    reset the crop; missing camera frames stay missing. A concurrent generated
    regression exposed a failed-encoder cleanup hang; exception unwinding now
    shuts down the owned sink without blocking finalization. Successful Stop
    and export completion retain explicit finalization.
  - Clean analysis, all 812 tests and 260 screenshots pass. Full native render
    regression and generated main/paired wide/portrait crops/cut resets pass;
    injected zero/one-sample failures and mono/stereo fragmented AAC checks
    pass. Actual app-channel six EN/FR/AR Camera/Both wide/feed/portrait on/off
    exports preserve captions/history and original bytes. EN/AR UI and native
    main/paired PNGs inspected. No owner input/media, guessed face, score,
    dependency, copied code or upload. Normal Windows Release restored.
    Camera movement, blur/cursor, sound,
    coaching/editor and mobile/launch remain; owner trials stay deferred.

- 2026-10-07, rounded screen frame:
  - Added the independent Screen/Both export switch and backward-compatible
    immutable choice/history/recovery. Frame fitting uses design tokens;
    original media, cut/caption clocks and camera geometry remain independent.
  - Native Direct2D masks the area outside the rounded picture/camera, drawing
    a local fixed dark gradient and cached Gaussian shadows. Clicks map through
    the inset and corner masks; captions/shortcuts draw above. Uses installed
    SDK dxguid identifiers; no new package, asset or copied code.
  - Clean analysis, all 774 tests and 254 screenshots pass. Native decoded
    wide/portrait full-picture/corner/inset zoom/click and fixed-camera checks,
    plus the full render regression, pass. Actual app-channel 12 EN/FR/AR
    frame on/off exports preserve exact subtitles, independent effects/history
    and original source/activity bytes. EN/AR UI and native PNGs inspected;
    normal Release restored. Smooth cursor/blur, camera
    movement, further sound/coaching/editor and mobile/launch work remain.

- 2026-10-07, shortcut badges:
  - Added the bounded allowlisted shortcut collector, cut/reorder retiming,
    latest-wins overlap handling, continuous-split invariance and strict
    JSON/native clock/label guards. Shared sidecar worker supplies each screen
    effect independently. Added Show shortcuts controls, count history,
    portable tracks and exact frozen completion recovery.
  - A separate native CaptionOverlay uses already bundled private OFL
    Martian Mono, fixed signal type and top-left safe-edge glass. Whole-plate
    spring rise/fade keeps glyph geometry stable; caption rendering remains
    separate. No new font installation, dependency, model or collection.
  - Clean analysis, 754 tests and 254 screenshots pass. Native wide/portrait
    decoded safe bounds, onset/rise/fade and private-label rejection pass.
    Actual app-channel 12 EN/FR/AR all/plain/click-only/shortcut-only exports
    preserve subtitle clocks, track/history reload and original source/activity
    bytes. EN/AR UI and native PNGs inspected; normal Release restored.
    Frame/backdrop, smooth cursor/blur and further sound/coaching
    follow. Owner hardware/mobile/launch trials remain deferred.

- 2026-10-06, click highlights:
  - Added the bounded visible-click collector and source-range pulse retiming,
    with clipped lifetime, contiguous-split invariance and strict immutable
    JSON/native request guards. The existing sidecar worker supplies zoom and
    click tracks independently. Added Highlight clicks controls/count history,
    portable pulse metadata and exact frozen completion recovery.
  - Native Direct2D draws amber spring rings and radial halos onto the owned
    GPU frame, mapping source resize/current crop and clipping outside the
    camera and visible picture. Captions stay above it; active pulses are bounded.
  - Clean analysis, 735 tests, 254 screenshots and normal Release pass.
    Native generated wide/portrait decoded onset/fade passes; a camera-covered
    pulse decodes identically to the no-ring baseline. Actual app-channel
    EN/FR/AR wide/feed/portrait zoom+ring/plain/ring-only exports preserve exact
    clocks, track/history reload and original source/activity bytes. EN/AR UI
    and native PNGs inspected; no owner media/input, dependency, model or upload.
    Smooth cursor, shortcut badges, frame/blur and further sound/coaching follow;
    mobile/launch work and owner trials remain.

- 2026-10-06, spoken pointing zooms:
  - Added natural EN/FR/AR lexicon phrases, bounded frozen-source alignment
    and a token proximity window. Complete exact reliable/corrected phrase
    timing can boost one visible click; uncertain/changed/added/unsaid words,
    Notes, sentence boundaries and long phrase gaps cannot. Cut/reorder
    provenance requires the entire phrase in the same retained source range;
    ordinary cluster evidence survives when the phrase does not.
  - Clean analysis and all 726 tests pass. Existing Screen/Both controls and
    native crop code are reused. Actual Windows app-channel one-click
    EN/FR/AR wide/feed/portrait on/off exports pass exact caption/subtitle
    clocks, frozen target/history reload and original source/activity bytes.
    Normal Release restored; no new dependency/model/upload or owner input.
    Cursor/ripple/keycap/frame polish and further sound/coaching are next;
    mobile/launch work and owner hardware trials remain.

- 2026-10-06, screen activity zooms:
  - Added the streaming bounded pure planner, strict local sidecar worker,
    source-dimension targets and range-aware immutable output track. Lead/hold,
    typing/cluster thresholds come from design tokens. No removed activity is
    borrowed; contiguous source splits preserve decisions. Bad/missing files
    retain the full picture without private diagnostics.
  - Native source crops evaluate under/critical/overdamped springs, preserve
    pan velocity, reset across cuts and clamp even NV12 apertures. Studio
    on/off controls, count history, portable metadata and completion recovery
    retain the exact track. Recovery rejects malformed tracks; removing the
    activity file after completion cannot change the saved video.
  - Clean analysis, 698 tests, 254 screenshot cases and normal Release pass.
    Generated native geometry/resize/pan/reset and wide/portrait decoded zoom/
    full-return pixels pass. Actual Windows app-channel EN/FR/AR wide/feed/
    portrait on/off exports retain caption/subtitle clocks, immutable history
    and unchanged source/activity bytes. EN/AR UI/native PNGs inspected.
    No owner media/input, new dependency, copied code, model or upload.
    Pointing-word zooms, cursor/frame effects, further sound/coaching and mobile/
    launch work remain; owner trials stay deferred.

- 2026-10-06, optional sound-join fades:
  - Added a bounded packet-independent PCM envelope at internal discontinuous
    joins, plus actual-join detection, a default-on reversible export switch
    and additive immutable history/portable metadata. Gains never exceed one;
    contiguous source spans and outer edges remain untouched. No overlap or
    change to original bytes, ASR, cut/caption/word clocks or earlier exports.
  - Clean analysis, 669 tests and 254 screenshots pass. Native mono/stereo,
    tiny ranges, packet splitting and disabled/continuous samples pass;
    decoded AAC attenuates the join while distant tone levels stay intact.
    Whole/contiguous exports decode to identical PCM. Actual Windows app-channel
    EN/FR/AR retake keep/select/restore exports retain the sound choice, Still,
    exact clocks, subtitle/history/reload and original bytes. Normal Release
    restored; EN/AR phone PNGs inspected. No owner media/input, new dependency,
    copied code or upload. Screen effects, remaining sound and coaching follow;
    owner trials stay deferred.

- 2026-10-06, Cue/Punch delivery captions:
  - Added source-identity cue mapping on a bounded worker, actual gap-phrase
    breaks, separate Punch chunks and display-only Arabic elongation. Kept
    reliable accepted cues through removal/reordering; no unsaid words or
    invented performance grade. Saved style/Still controls/history are additive.
  - Native shaping fits static axes and the full spring envelope before
    drawing. Adjacent spaces reserve stress-pop room without reflow or broken
    Arabic joining. Still retains clock/color and omits transforms/sweeping.
    Cue/Punch use existing privately loaded OFL fonts and installed Windows APIs.
  - Clean analysis, 663 tests and 254 screenshots pass, including frozen cues,
    changed/uncertain/corrected speech, retake identity, Arabic diacritics,
    malformed timing, format defaults and reduced-motion/explicit overrides.
    Native generated decoded pixels pass reveal, emphasis, springs/Still,
    spacing and safe margins. Actual app-channel exports in all three languages
    pass Cue/Punch/Karaoke caption clocks, retake selection/restore, history and
    unchanged source bytes and saved Still. Normal Release restored. No owner
    media/input, new dependency or upload.
    Screen/sound polish and full coaching are next; owner trials stay deferred.

- 2026-10-06, Karaoke captions on video:
  - Added bounded exact-word UTF-16 metadata, immutable renderer copies and
    validation on Dart/native sides. The native cached phrase changes brushes
    without reflow, with a shaped progressive underline in each run's direction.
    Fixed Cut tokens control type, dim ink, safe plate and underline geometry.
  - Added the Studio style choice and backward-compatible immutable history.
    Subtitle phrases and all original/cut revisions remain intact. No new
    dependency, model, owner media/input, upload or private diagnostic.
  - Analysis is clean, all 636 Flutter tests and 230 screenshots pass. Native
    decoded video checks and generated real app-channel EN/FR/AR retake
    selection/restore exports pass word fill/sweep/gaps/safe bounds, clocks,
    style history, captions and original bytes. Normal Release restored;
    EN/AR UI and mixed Arabic portrait PNGs inspected. Cue/Punch, screen/sound
    polish and full coaching are next. Owner trials stay deferred.

- 2026-10-06, safe reversible retake choices:
  - Added immutable optional selections, shared measured quiet boundaries,
    retained-cue ownership, unioned overlaps and strict actual-word provenance.
    Old plan enrichment retains silence/filler preferences; public writes
    reject rewritten proposals, stale revisions and oversized JSON.
  - Connected Keep attempt/Keep all, disabled unsafe/partial choices and
    Restore all. Filler choices inside removed attempts remain recoverable;
    wording edits reset proposals. Added EN/FR/AR controls and 18 screenshots.
  - Analysis is clean, all 618 Flutter tests and 218 screenshots pass. Native
    audio/picture checks and generated app-channel EN/FR/AR exports pass
    selection/restore, exact clocks, captions/subtitles, reload/history and
    unchanged original bytes. Normal Release build restored; EN/AR/unsafe PNGs
    inspected. No owner media, network or new dependency. Automatic ranking,
    caption/screen/sound polish and full coaching remain next; trials deferred.

- 2026-10-06, repeated-section comparison:
  - Added pure anchored section/attempt grouping and bounded isolate derivation
    from frozen Script/words. Partial coverage, changed/added speech, uncertainty
    and original times stay factual. Ordinary repetition and free speech do
    not become retake scores. The paged panel listens through the original
    player without altering cuts, words or media; stale results are guarded.
  - All 574 Flutter tests, 200 screenshot cases, clean analysis and normal
    Windows Release build pass. EN/FR/AR full review checks use a deliberately
    edited library script to verify frozen context and explicit playback.
    Inspected EN/AR partial and FR dark phone layouts. No owner media/input,
    dependency or network. Reversible selection and performance scoring remain
    unfinished; continue retakes and remaining Cut polish. Trials deferred.

- 2026-10-06, original phrase listening:
  - Added explicit bounded playback with original-source context, automatic
    pause, manual/background cancellation and generation ownership across
    late commands/status. The player survives scrolling and old requests
    cannot replay. Hearing a filler does not choose removal or edit files.
  - All 537 Flutter tests, 188 screenshot cases and clean analysis pass.
    Generated Windows player checks cover bounded playback and stable pause;
    EN/FR/AR integration checks cover original playback and unchanged cuts.
    Inspected EN/AR phone controls. Normal Release build restored. No owner
    media, network or new dependency. Retakes and remaining polish are next.

- 2026-10-06, reversible filler review:
  - Added shared normalized vocabulary, evidence-gated optional proposals,
    immutable indices/phrase provenance and strict caption retiming for chosen
    complete words. Existing quiet choices survive enrichment; stale cut saves
    fail without replacing newer decisions. Originals/full words/older exports
    remain available. Notes has no adherence; Screen and cue gaps remain intact.
  - All 525 tests and 188 screenshot cases pass; analysis is clean and the normal
    Windows Release build succeeds. Inspected EN/AR phone kept/removed layouts.
    Generated native tone/pixel checks verify the middle island disappears with
    surrounding picture/audio clocks preserved. Generated app-channel EN/FR/AR
    keep/remove/restore/video-caption/history/reload and original-byte checks pass.
    No owner speech, network or new dependency. Trials remain deferred.
    Full retake choices, caption motion, screen/sound polish and coaching are next.

- 2026-10-06, Readable captions on video:
  - Added bounded worker-owned DirectWrite/Direct2D caption compositing with
    private bundled display fonts, shaped Arabic and token-driven safe margins.
    Fit includes glyph overhang, preserves complete phrases and refuses unreadable
    text. Caption choices are revision-bound in immutable local export history;
    optional burning preserves subtitle files and existing exports.
  - All 485 Flutter tests, 176 screenshot cases, clean analysis and normal Windows
    Release build pass. Generated native timing/pixels/two-line/diacritics and
    all-format app-channel/history/player/cancel checks pass. Corrected the
    test decoder to respect negotiated RGB stride and visible aperture.
    Inspected EN/AR phone controls and generated French/Arabic video frames.
    No owner speech, network service or new dependency. Trials deferred;
    filler/retake review, motion, screen/sound polish and coaching remain next.

- 2026-10-06, transcript wording corrections:
  - Added immutable original spelling, one-word changes/restoration, revision-checked
    saving and frozen alignment recomputation. Existing ASR confidence/times and
    measured quiet evidence are preserved. Notes/computer-only policy survives.
    Cuts rebuild and older exports remain available. Failed library attachment
    rolls back unless a later edit already replaced it; retry stays usable.
  - Added paged Studio review, estimated wording flags and a validated RTL field.
    Inspected EN/AR and Arabic dialog screenshots; improved short-word times to
    tenths and right alignment. Analysis is clean, all 478 tests and 176 screenshots
    pass, normal Windows Release builds, and generated native Script/Notes correction,
    restore, recut and reload pass. No owner speech or new dependency; trials deferred.

- 2026-10-06, playback background-pause fix:
  - Kept a lifecycle pause while a platform command is pending, bound it to the
    original session, and guarded late command completion with its generation.
    Tests cover delayed Play, replacement handles and disposal. All 459 tests
    pass, analysis is clean and the Windows Release build succeeds.
    No new UI, dependency or data access.

- 2026-10-06, automatic review after Stop:
  - Connected Camera/Screen/Both to review with persistent capture warnings and
    released live inputs; Record another resets the aid and restores setup.
    Added the default-enabled local processing setting and installed-only check.
    Model/speech/cut cancellation preserves originals and saved words; automatic
    reuse preserves existing choices. Slow initial reads cannot replace new cuts.
  - EN/FR/AR Script/Notes processing, no-network missing/pre-start setup,
    single-owner cancellation, review progress and recorder-input lifetime tests
    pass. Analysis is clean, all 456 tests and 167 screenshots pass, and the normal
    Windows Release build succeeds. EN setup/AR progress PNGs inspected.
    The generated Release channel
    check verifies actual speech, frozen aids and durable/reused words/cuts.
    Copied the verified public model to the owner's local-data on E: after checking
    size/SHA-256 again. No new dependency or owner speech used; trials deferred.

- 2026-10-06, first Windows video export:
  - Built the bounded native GPU/PCM renderer, finalized MP4 output, all four
    formats, optional paired-camera corner, actual cut captions/portable metadata
    and local saved-video history. Every render uses fresh files; original stays.
  - Added revision checks, cancelled-job cleanup, decoded verification, queued
    probe ownership and durable completed-job recovery through caption/library
    save failures. Fixed a fragmented-file duration hint before enabling export.
  - Analysis is clean; 443 tests and 161 screenshot cases pass. Native generated
    checks pass in Debug/Release; the real Windows app-channel check passes all
    formats, Unicode paths, history reload, saved playback and cancellation.
    Normal Windows Debug/Release builds pass. EN/AR export PNGs inspected.
    Owner trials remain deferred; automatic-on-stop and remaining Cut/coaching
    features are next. No new dependency, bundled codec or copied external code.

- 2026-10-06, private speaker notes feature request:
  - Recorded the requested free-speech aid as Notes mode and added its design
    specification: manual cards/buttons/shortcuts, exclusion, last-card behavior,
    EN/FR/AR, local snapshots and accurate speech-based captions.
  - Updated the brief, design index, recording/auto-edit rules, roadmap and privacy
    table. No app implementation, dependency or default change in this session.
  - Next build the pure deck/controller, then editor/Stage/recording integration;
    word-processing integration remains pending. Existing validation is 347 tests
    and 112 layout cases; documentation links/diff were checked for this change.

- 2026-10-06, word timing slice 20:
  - Added immutable timed-word data, correct UTF-8 fragment assembly and bounded
    script alignment in EN/FR/AR, including changes/additions/misses and anchored
    repeated attempts. Invalid timing is rejected instead of fabricated.
  - Licence-checked/pinned source and model, kept notices, built a separate CPU
    prototype, and passed generated local WAV plus stereo AAC/video recognition,
    clock-gap preservation, cancellation and Dart end-to-end matching. All test
    downloads/fixtures stay under ignored app/build/asr on E:, never owner media.
  - Clean analysis and all 347 tests. The 112 earlier layout checks and normal
    app remain current. Actual step-3 app channel/model setup/durable jobs and
    language accuracy trials are still pending; see word-timing.md.

- 2026-10-06, Windows recorder slices 18/19:
  - Connected optional anonymous activity, exact pause timing, flushed sidecars and
    durable partial recovery. Generated full-process crash/reopen and 30-second
    resize/three-pause checks pass; no owner data was recorded. Fixed clipping to the
    surviving video and retained privacy under source/shortcut/modifier changes.
  - Completed the GPU render-risk spike and portable EN/FR/AR cut plan. Two kept ranges
    re-encode to verified video/audio in about 0.44 seconds for this small Release fixture.
    Readers/COM/GPU teardown is safe. The real Cut UI/exporter and ASR remain future steps.
  - All 328 tests, 112 screenshots, clean analysis and normal Windows release builds.
    Native activity privacy/lifecycle, full protected generated take, abrupt-exit
    recovery and Debug/Release rendering checks pass. Owner trials remain deferred.

- 2026-10-06, Windows recorder slice 17 (cursor companion):
  - Added the protected compact reader, follow spring, edge flipping, stillness docking,
    glass/rounded bounds, camera choice/reminder and reduced-motion docking. It reuses
    playback and never saves cursor samples. A late poll cannot undo Hide; showing again
    restores click-through. Native style changes preserve the live window's visibility.
  - All 301 tests and 109 layout cases pass, including EN/FR/AR compact long phrases.
    Analysis is clean. The full generated protected paired take passes camera docking,
    following, click-through, reduced motion, hide/show cleanup and durable saving.
    Owner trial remains deferred. Telemetry, longer/crash checks and render core are next.

- 2026-10-06, Windows recorder slice 16 (normal computer sound):
  - Connected the explicit off-by-default setup switch, frozen owner choice, separate
    manifest audio consent/scope, honest playback-only HUD and quiet/device warnings.
    Default routing changes stop rather than leave the old endpoint recording silence.
    Voice/meter remain microphone-only; Camera never records playback.
  - EN/FR/AR snapshots, recovery, setup and controls pass, including narrower Windows
    setup. All 281 tests and 97 layout cases pass; analysis is clean. Full generated
    native UI take verifies protected controls/common pause/durable sound choice/cleanup.
    The helper refuses capture without the explicit fixture binary; no owner sound or
    microphone is saved. Owner trial remains deferred; companion/telemetry are next.

- 2026-10-06, Windows recorder slice 15 (computer-sound core):
  - Added pinned Windows stereo loopback, bounded shared-clock microphone/playback
    mixer and separate sound status/reason. No private logs, new dependency or copied code.
  - Seven generated native recordings verify stereo tones/mixed voice, pause removal,
    idle silence, access failure, device loss and aligned endpoints. Pure ring/duplicate/
    clipping/clock checks pass; actual loopback samples are discarded by the lifetime
    check. Analysis is clean, 272 tests pass and Windows debug builds. Setup integration
    remains next; owner will test the app later.

- 2026-10-06, Windows recorder slice 14 (normal Both recording):
  - Connected exact chosen-camera identity, setup device handoff, protected live bubble,
    paired capture/store and partial-camera warnings. Both is enabled and remembered.
    Capture protects every required window, stops safely on lost protection and releases
    native finalization before destroying overlays/restoring setup. No extra audio stream.
  - Added EN/FR/AR setup/identity/snapshot/ownership/late-close/error tests and Both PNGs.
    Natural Arabic title height prevents label overlap. Full generated native take passes
    pause/resume, live bubble, reader hide/show/Lock, separate files with matching duration,
    one durable pair and cleanup. It caught the bubble's initial OnDestroy/pixel-holder bug;
    fixed and repeated the complete take successfully. No owner's camera/mic was used.
  - Analysis is clean, 270 tests and 93 screenshot cases pass; Windows release builds.
    Owner real camera/microphone
    trials deferred by request; system audio, companion and telemetry remain next.

- 2026-10-06, Windows recorder slice 13 (excluded camera bubble):
  - Added the design-sized circular self-view, exclusion before visibility, recorder-owned
    frames/leased texture, native drag and preview-only hide. No second camera stream,
    file/device IDs in child, private logs, new dependency or input hooks.
  - Native window lifetime/exclusion smoke and paired live-preview-during-pause check
    pass. EN/FR/AR controls/layout and waiting/live screenshot cases pass; inspected EN/AR
    PNGs and reduced wrapping in the privacy label. Analysis is clean, 256 tests and
    90 screenshots pass; Windows builds. Both setup/controller integration remains next.

- 2026-10-06, Windows recorder slice 12 (paired storage/recovery):
  - Flushed both file reservations and chosen-camera display metadata before capture,
    verified paired output separately, and retained useful screen output if camera
    decoding fails. Recovery restricts both paths and preserves local camera bytes.
  - EN/FR/AR snapshot/edit/recovery tests, normal paired save, partial camera, external
    path rejection and failed-save retry pass. Analysis is clean, 249 tests pass.
    No dependency or UI change; protected bubble and Both setup integration remain next.

- 2026-10-06, Windows recorder slice 11 (paired video core):
  - Added exact-device asynchronous camera snapshots and a separate fragmented file
    on the screen recording/pause clock. Camera loss saves the partial pair explicitly.
    Microphone audio is recorded once in the screen file; no new dependency or copied code.
  - Generated native pair checks pass normal capture, stop while paused and camera loss;
    repeated camera lifecycle and plain Screen pause regression pass. Fixed the first
    Media Foundation format-change callback before decoding the owned camera pixels.
    Dart argument/count/error tests pass; analysis is clean, 242 tests pass and Windows
    builds. Owner trials remain deferred; paired recovery/bubble/setup follow next.

- 2026-10-05, Windows recorder slice 10 (normal Screen recording):
  - Connected protected countdown/HUD/reader, chosen capture/audio, Voice, pause,
    safe native release and durable saving to normal setup; persisted mode and showed
    screen/recovered takes. Screen requires no camera. Both is still disabled.
  - EN/FR/AR setup, ownership/cancel/dispose/save order, source loss and Voice/end-of-script
    tests pass. Fixed a null live-preview handle during route handoff and low-contrast
    Stage controls/Arabic metadata. Full silent generated-window native take passes.
    Analysis is clean, 239 tests and 84 screenshot cases pass. Owner trials deferred
    by request; Screen + camera is next.

- 2026-10-05, Windows recorder slice 9 (excluded HUD/countdown):
  - Added a separate protected HUD engine/window and protected setup-window ownership,
    source-centred countdown, docked timer/meter/controls, rounded bounds and click-through
    outside controls/grip. No script, private files, capture or microphone in HUD transfer.
  - Added EN/FR/AR layout/control/state/exclusion tests and nine screenshot cases.
    Fixed low-contrast controls and the single-frame countdown/docking overflow.
    Native smoke checks cover verified visibility/exclusion, close/reopen and restored
    main-window affinity; owner click-through/placement trials remain pending.
  - Normal setup still has Screen/Both disabled until reader/control integration.
    Analysis is clean, all 226 tests and 81 screenshots pass; EN recording and AR
    countdown PNGs were inspected. The Windows native check passes without layout
    overflow and restores the main window after two protected HUD sessions.

- 2026-10-05, Windows recorder slice 8 (pause/resume):
  - Added a shared QPC clock with paused intervals removed, including exact PCM packet
    trimming at pause/resume boundaries. Paused capture keeps the source snapshot/meter
    current but writes no picture/sound and holds saved duration.
  - Native silent/audio fixture checks verify a stable paused timer/frame count, removed
    gap, correct resized pixels and aligned decoded endpoints; pure clock checks pass.
    Pause API has the same session guards as Stop. Recording controls/UI are next.
    Analysis is clean, all 220 tests pass and the Windows debug build succeeds;
    normal microphone recording also passes after the clock change.

- 2026-10-05, Windows recorder slice 7 (durable takes/recovery):
  - Added flushed local pending manifests and script/presentation snapshots, file
    verification on a native worker, mode/path metadata and idempotent crash recovery.
    Recovery preserves later edits, deleted scripts and unreadable local files, and
    rejects external paths/symlinks. A library save failure leaves recovery information.
  - Native verification decodes one frame, checks visible dimensions/audio and reads
    completed-fragment duration after a crash. Fixed padded decoder-height reporting.
    EN/FR/AR snapshots and recovery/retry/compatibility tests pass. Startup recovery is
    serialized with reservations/finishes. No screen recording UI is enabled yet.
    Analysis is clean, all 220 tests pass and the Windows debug build succeeds;
    native probing passes unfinished video-only and finalized AAC fixtures.

- 2026-10-05, Windows recorder slice 6 (capture/save pipeline):
  - Joined free-threaded WGC GPU snapshots and selected-endpoint PCM/AAC on a dedicated
    worker, fixed output bounds and common QPC timestamps. Static sources repeat their
    latest GPU snapshot; slow encoding drops cadence slots without unbounded queues.
  - Startup requires a frame and a working chosen microphone; stop and source loss
    finalize partial output. Native fixture-window recording/decode checks pass for resize,
    chosen/default audio, normal stop and closed/minimized source recovery.
  - Added guarded native start/status/stop and Dart channel tests. No setup mode is
    enabled yet; durable metadata/recovery, hidden HUD/countdown and floating-reader
    synchronization remain next before owner trials of actual screen takes.
    Analysis is clean, all 210 tests pass and the Windows debug build succeeds.
    Decoded WGC fixture pixels match the generated colors and resize margins;
    early cancellation and missing chosen microphone leave no output file.

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

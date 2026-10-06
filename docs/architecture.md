# Architecture

This covers how the app is built and the rules the code relies on. For what the product is, see
[product-brief.md](product-brief.md); for progress, see [status.md](status.md).

## Layers

```
ui/        screens and widgets       (Flutter)
prompter/  timeline + controller + kinetic maths (pure Dart)  +  prompter widget (Flutter)
theme/     design tokens (generated) and the Material theme built from them
markup/    markup engines            (pure Dart, plus package:http)
storage/   files and secure storage  (Flutter plugins)
model/     tokens, marks, scripts    (pure Dart)
```

Dependencies point downward only: `model/` imports nothing from the app, and `markup/` imports
only `model/`.

## Scripts, tokens and marks (`lib/src/model/`)

- **`ScriptDocument`** is immutable. It holds the text, language (`en`, `fr`, `ar`), coaching
  style, marks, suggestions and takes (recordings). It is stored as JSON.
- **Tokens** (`token.dart`): the text split on whitespace, with punctuation kept on the word.
  Each token knows its character offsets, the line breaks around it, and a normalized `bare`
  form. `bare` is lowercased, has its punctuation and Arabic diacritics stripped, and folds
  أ/إ/آ to ا, ى to ي and ة to ه. Use `bare` for all comparisons and word-list lookups.
- **Marks** (`mark.dart`) point at token indices:
  - *Gap marks* (`pauseShort`, `pauseLong`, `breath`) sit after token `end`; `start == end`.
  - *Span marks* (`stress`, `slower`, `faster`, `energy`) cover tokens `start..end` inclusive.
  - `accepted == false` means the markup proposed the mark and the user hasn't reviewed it.
  - `origin` is `rules` (the on-device engine), `ai` (any language model, cloud or local) or
    `user`. Older files that say `local` or `cloud` still load.
- **Invariants.** `normalizeMarks` enforces these, so call it on every new mark list:
  - Every index is in range, and no gap mark sits after the last token.
  - There is at most one gap mark per position. An accepted mark beats a pending one; otherwise
    the stronger kind wins (long pause, then short pause, then breath).
  - Spans of the same family (stress, energy, and pace, which is slower or faster) don't
    overlap. Accepted spans claim their words first; a span that collides is cut down to its
    longest free run, or dropped.
  - The list is sorted by start.
- **Edits** (`mark_remapper.dart`). `ScriptDocument.withText` aligns the old tokens with the new
  ones: it matches the unchanged runs at both ends directly, then aligns the middle with a
  longest common subsequence on `bare`. Marks follow their words. A gap mark whose word
  disappears is dropped, and a span shrinks to its surviving words. A suggestion survives only
  if its exact original text is still there.

## Markup engines (`lib/src/markup/`)

Every engine implements `MarkupEngine.markup(ScriptDocument) -> MarkupResult`, which returns
pending marks and suggestions. `applyMarkup` merges a result into a script: it keeps accepted and
user marks, replaces the old pending proposals, and replaces the suggestions.

The user picks the engine in Settings (`MarkupProvider` in `providers.dart`):

| Provider | Engine | Server | Key |
|---|---|---|---|
| On-device (default) | `LocalMarkupEngine` | none | none |
| Claude | `ClaudeMarkupEngine` (Anthropic Messages API) | api.anthropic.com | required |
| OpenAI, Google Gemini, Mistral | `OpenAiCompatibleEngine` | the provider's OpenAI-compatible API | required |
| Ollama, LM Studio | `OpenAiCompatibleEngine` | `localhost:11434` or `localhost:1234`, or a LAN address | optional |
| Other | `OpenAiCompatibleEngine` | any OpenAI-compatible server (OpenRouter, Groq, llama.cpp, vLLM…) | optional |

- **`LocalMarkupEngine`**: free, offline, deterministic apart from mark ids. It reads
  punctuation, line breaks and `Lexicon` word lists (steps, actions, emphasis, conclusions,
  calls to action, conjunctions, numbers, units, wordy phrases) for each language, and applies
  the rules of each style:
  - **Presentation:** a long pause after paragraphs, questions and sentences with numbers;
    stress on numbers and claims; slower pace on sentences with figures written in digits; an
    energy lift on conclusions and the close.
  - **Tutorial:** a long pause before each step (first, then, ensuite, ثم...); stress on the
    action verb; slower pace on technical terms (camelCase, file.ext, acronyms, mixed digits).
  - **Short social video:** a short pause after the hook; heavy stress, with a punch word in
    the hook; faster pace through long sentences; energy on the hook and the call to action.
  - **All styles:** breaths once a stretch passes the style's `wordsPerBreath` (at a comma, or
    before a conjunction); a short pause after a mid-sentence colon; "tighten" suggestions for
    wordy phrases; hook advice when the opening line is long.
- **`MarkupPrompt`** (`markup_prompt.dart`) is shared by the language-model engines. It sends
  the script as `[index]word` pairs, with a system prompt built from the style and language, and
  defines `responseSchema`. `parseReply` is forgiving, because local models are weaker:
  - it strips `<think>` blocks, code fences and chatter;
  - it accepts kind aliases (`emphasis`, `long-pause`, `slow down`) and numbers sent as strings;
  - it checks every anchor: `locateWords` moves a mark up to 6 tokens to where its quoted words
    are, or drops it, and a suggestion must quote the exact original text.
- **`ClaudeMarkupEngine`** uses structured outputs (`output_config.format`), streaming, effort
  `medium` and `fallbacks: "default"` on models that support it.
- **`OpenAiCompatibleEngine`** posts to `{baseUrl}/chat/completions` with `stream: true`.
  - It asks for `response_format: json_schema` first. If the server rejects that (400 or 422),
    it retries with `json_object`, then with no format at all; the prompt spells out the JSON
    either way.
  - It reads SSE, or a plain JSON reply from servers that ignore `stream`.
  - Local servers get a 5-minute timeout, because loading a model is slow, and error messages
    about starting the server and about context length.
- Both remote engines implement `RemoteMarkupEngine.listModels()`, which Settings uses for the
  model picker and "Test connection". `remote_http.dart` holds the shared retry (429 and 5xx,
  twice, honouring `retry-after`), timeouts and error-message parsing.
- Keys: one per provider, in secure storage under `api_key_<provider>`, never in the settings
  file. When the chosen provider isn't set up (no key, no model), the editor runs the on-device
  engine and says why.
- Local servers over plain HTTP: Android sets `usesCleartextTraffic`, and iOS sets
  `NSAllowsLocalNetworking` and `NSLocalNetworkUsageDescription`, so a phone can reach
  Ollama or LM Studio on a computer on the same Wi-Fi.

## Theme (`lib/src/theme/`)

- **`tokens.g.dart` is generated** from `docs/design/tokens.json` by
  `dart run tool/gen_tokens.dart` (run from `app/`). Never edit it by hand;
  `test/theme/tokens_test.dart` fails when it is stale. It holds:
  - `SaPalette.light` and `SaPalette.dark`: every colour and shadow;
  - `SaType`: every type style;
  - `SaFonts`: the four families and their Arabic fallbacks;
  - `SaSprings`: `SpringDescription`s;
  - `SaDurations`, `SaEasing`, `SaSpace`, `SaRadius`, `SaPrompter` and
    `SaScreenFx`.
- **`theme.dart`** has:
  - `buildTheme(brightness)`, which builds the Studio `ThemeData` from the
    palette;
  - `SaTheme.of(context)`, the palette of the current theme, for what
    `ColorScheme` has no slot for;
  - `atWidth(style, width)`, which sets a variable font's width axis (it
    also sets `wght`, because any variation replaces Flutter's automatic
    weight mapping).
- **Fonts** are bundled in `app/assets/fonts` with their OFL licences, which
  `main.dart` registers with the `LicenseRegistry`. They are all variable
  fonts: `FontWeight` maps to the weight axis automatically.
- **The Stage never follows the theme.** Stage widgets read
  `SaPalette.dark.stage*` directly, and `CueColors.stage`. Studio widgets use
  `CueColors.forStudio(context)`.

## Prompter (`lib/src/prompter/`)

- **`DeliveryTimeline`** (pure Dart) plans a read-through. Each word gets
  `60 / wpm` seconds, weighted by its length (weights average to 1, so the
  words per minute hold). Slower spans stretch a word ×1.25 and faster spans
  squeeze it ×0.8. After each word the timeline holds for the gap mark's
  length (the style's short or long pause, or 350 ms for a breath), or for a
  natural beat: 500 ms at a paragraph end, 250 ms at a sentence or line end,
  120 ms at a comma. `spokenAt(t)` is speaking time with the holds left out;
  the scroll follows it, so it stands still at pauses.
- **`PrompterController`** (a `ChangeNotifier`) holds the position in the
  timeline, play state, speed (0.5× to 2.0×) and scroll mode (timed or
  manual). The view calls `advance(dt)` every frame; listeners are notified
  only on discrete changes: the current word, the pause being held, play
  state, speed or mode. The prompter shows **accepted marks only**.
- **`PrompterLayout`** maps tokens to screen lines (measured after layout).
  `scrollYAt(timeline, t, motion:)` follows the speaker's **motion** choice
  (`PrompterMotion` in `guide.dart`):
  - **Line step** (the default): the top of the line being spoken. The line
    being read stays still under the reading line, and the view glides to the
    next line (about 300 ms, no overshoot) as its first word starts. Testers
    found a continuous drift hard to read.
  - **Smooth**: an even scroll through each line while it is spoken.
- **Voice pacing** (`ScrollMode.voice`, the default where a microphone level is
  available, Windows for now):
  - The timeline advances only while `speaking` is true.
  - A planned pause still runs out in silence, then the next word waits for
    the voice.
  - `VoiceActivity` (pure Dart) turns microphone levels into "speaking", with an
    adaptive noise floor and hangover.
  - `MicMonitor` (`lib/src/recording/`) polls the level at 20 Hz.
- **The guide** to the word to say now is the speaker's choice
  (`PrompterGuide` in `guide.dart`, kept in `Settings.guide`, G key):
  - **Dot** (the default): `BouncePath` (pure Dart) turns the word boxes, the
    cues and the timeline into a `DotFrame` at any moment: where the dot is,
    its squash, its tint, the ring at a pause and the burst on a stressed
    word. Painting is stateless, so seeking, pausing and voice waits need no
    bookkeeping. The rules are in `docs/design/prompter.md`, "The bouncing
    dot".
  - **Underline:** a white bar fills across the word over its planned length.
  - **Spotlight:** everything fades back except the word to say (full) and
    the next one (70%).
  - **Off:** only the reading line.
  - With Dot and Underline, words already said on the line fade back, and the
    reading caret lights amber while the voice is heard.
  - **Layers:** fading uses `BlendMode.dstOut`, so the text sits in its own
    layer (a no-op `ShaderMask` around the scroll view); otherwise it would cut
    holes in the glass behind it. The dot is painted by `_DotLayer` above the
    read-zone fades, so they never dim it, translated by the scroll offset.
- **`PrompterView`** is the widget. It shows:
  - large type on `stage` black, or on glass over a camera (`glass: true`);
  - a reading line at 30% of the height;
  - a fade over what has been read;
  - pace bars in the gutter;
  - a glass PAUSE, LONG PAUSE or BREATHE badge while the prompter holds,
    whose ring empties over the hold (`DeliveryTimeline.holdAt`).

  A drag or mouse wheel pauses the timed scroll and moves the reader to the
  line under the reading line. Mirror mode flips it for teleprompter glass.
- **Kinetic text** (`kinetic: true`, the default) is painted **around a
  paragraph that never changes layout**:
  - `_KineticLayout` measures, once per layout, the boxes of stressed words,
    energy and pace runs, and gap glyphs.
  - Two painters redraw every frame from the timeline position and the scroll
    offset. `under` draws the energy glow, speed lines and breathing tints;
    `over` draws the stressed words (grown and popping) and the rings when a
    hold starts.
  - In kinetic mode `MarkedText` leaves stressed words transparent
    (`StressStyle.stageOverlay`), and the overlay draws them with a
    `TextPainter` aligned to the paragraph's glyph box.
  - The motion maths (liveness near the reading line, the pop spring, hits)
    is pure and tested, in `kinetic.dart`.
  - Kinetic and Still lay out identically, because the spaces beside a
    stressed word are widened by `Kinetic.stressRoom` in both. A test checks
    this. **Never animate anything that changes layout.**
- **`MarkedText`** builds the styled span shared by the prompter and the
  editor.
  - Stress (`StressStyle`) is amber, bold and 1.15× on the stage. In the
    Studio it is ink at weight 700, and the page paints a marker swipe behind
    it (`stressRanges`).
  - Energy runs are coloured and open with a bolt.
  - Pace runs are tinted and open with a labelled arrow.
  - Pauses and breaths are icons after their word.
  - It records each token's character offset and each cue's range, for
    measuring and tap hit-testing.

### Right-to-left gotcha

Cue icons are **glyphs of the Material Icons font inside the text**, not
`WidgetSpan`s. In right-to-left paragraphs Flutter swaps widget spans between
slots, which put Arabic cues on the wrong side of their words. Icon glyphs are
private-use characters (bidi class L), so each becomes its own run and stays
where it is written. A narrow no-break space (U+202F) joins each icon to its
word so a line can't break between them. `test/prompter/marked_text_test.dart`
checks the placement in both directions; keep it passing. Wrap
mixed-direction strings in UI chrome in isolates (U+2068 … U+2069), as the
library subtitle does.

## Storage (`lib/src/storage/`)

- `FileScriptStore`: one JSON file per script in
  `<documents>/SpawnAlpha/scripts/`, written to a temp file and renamed.
  `ScriptLibrary` is the in-memory list the screens listen to.
- `Settings`: `<documents>/SpawnAlpha/settings.json` holds the markup source,
  model, default style, text size, mirror and kinetic settings. The Claude API key
  lives in `flutter_secure_storage` (Keychain, Keystore or Windows
  Credential Manager), never in the JSON file.
- Takes (recordings) go to `<documents>/SpawnAlpha/recordings/`, and their
  paths go in the script's `takes`.

## Screens (`lib/src/ui/`)

`AppScope` (an InheritedWidget) provides the library, the settings and the
recordings folder.

- **HomeScreen** (the start screen): the director's desk from design v3.
  - One stage hero, Record next: the most recently edited script (or another
    picked from a menu), its opening lines as the prompter shows them, the
    recording modes, and Record and Practice.
  - The scripts as marked pages (`ScriptPage` with the director's pass), a
    New script page, and the recent takes.
  - A sidebar on wide windows, a tab bar with a raised record button on
    phones, and a first-run panel with the samples.
  - Going on stage from here or from the editor goes through
    `ui/stage_launch.dart`, which asks once about unreviewed marks.
- **LibraryScreen**: the full script list (Home's "See all"), with a button
  that adds one sample script per language and style.
- **TakesScreen**: every take, newest first. Opening one selects its file in
  Explorer on Windows; in-app playback is still to come.
- **EditorScreen**: a title, a style picker and a language picker (the
  language is detected from the first words typed). It has two tabs:
  - **Write** is the text, remapping marks on every edit.
  - **Marks** runs the markup and shows the script as a **`ScriptPage`**
    (`ui/script_page.dart`). One render object lays out the text and the
    director's notes, and paints the marker swipes:
    - notes sit in a trailing margin (the left side for Arabic), level with
      their lines;
    - a note that can't sit near its line is left to the word sheet;
    - the margin folds away below 640px;
    - after a markup run, the director's pass animates `reveal` from 0 to 1:
      markers swipe in and notes write on, with no reflow.

    The tab also has the pending banner (Accept all, Discard), a `MarkSheet`
    when a word is tapped (accept, change kind, remove, add; notes in the
    pencil face), and suggestion cards (Apply or Dismiss).

  Changes autosave after 600 ms. Before opening the prompter or the
  recorder, the editor asks what to do with pending marks.
- **PrompterScreen**: the practice prompter with controls. Keyboard: Space
  plays or pauses; Up and Down change speed (timed) or move a line
  (manual); Left and Right move a sentence; T switches mode; K switches
  Kinetic and Still; Home returns to the start; M mirrors; + and − change
  the text size.
- **RecordScreen**: the camera preview with the prompter as a glass panel
  under the lens (top centre, at most 720px wide).
  - **Wide windows (desktop):** the set-up rail beside the preview
    (`ui/record_setup.dart`): what to record, the camera, every microphone
    with its own meter plus a sound check, and the prompter's guide, motion,
    pace, cues, size and mirror. The record button sits at the bottom with
    one line that says what will happen, or what is missing. **A take is
    never silently soundless:** when Windows blocks the microphone, or the
    sound check heard nothing, Record is off until the user fixes it or
    picks "record without sound".
  - **Narrow windows and phones:** the controls bar and the record row under
    the preview, as before.
  - A 3-2-1 countdown (`CountdownNumeral`: the display face lands wide and
    settles on the pop spring) starts the recording and the timed scroll
    together.
  - The take stops when the script ends or on Space. Each take is saved and
    added to the script.
  - Controls: a glass timecode pill, and the take number, `RecordButton`
    and camera flip in one row (`ui/recording_widgets.dart`).
  - On mobile, the camera is released when the app goes to the background.
- **Microphone (`lib/src/recording/`)**:
  - `AudioInputs` lists microphones, chooses the one takes record from, and
    meters levels. On Windows it goes through the `spawnalpha/audio_input`
    channel of the vendored camera plugin (`app/packages/camera_windows`).
    That plugin records from the chosen or default microphone; upstream used
    the first one listed, which recorded silence on the owner's PC.
  - The record and practice screens show a `MicChip` (name and meter) and a
    picker.
  - During the record set-up, `MicMonitor.watchEveryMic` meters every
    microphone at once (one WASAPI stream each, native `watchAll`), so the
    one that moves when you talk is easy to spot. It stops for the take.
  - `MicMonitor.blocked` is true when Windows denies access
    (`E_ACCESSDENIED`: the microphone privacy switches). The rail then shows
    the switches to turn on and opens `ms-settings:privacy-microphone`.
  - `SoundCheck` (pure Dart) judges a sound check from the loudest level
    while the speaker reads a line: heard, quiet or silent.
  - After a take, `mp4HasAudioTrack` and the loudest level during the take
    catch silent recordings, and the save dialog says so.
- **Windows screen sources (first recorder slice):** `ScreenSources` talks to the
   runner's `spawnalpha/screen_sources` channel. `EnumDisplayMonitors` and `EnumWindows`
   read names and dimensions only, filtering the app's own, hidden, minimized, cloaked,
   tool and protected windows. Display IDs use the Windows device name; window IDs
   include process ID and HWND. Never persist these handles. `SourceSelection` owns
   refresh/selection/confirmation outside the widget, rejects vanished sources and
   suppresses private error details. No thumbnails or input hooks yet.
- **Windows screen preview (second slice):** `ScreenPreviews` uses the runner's
  `spawnalpha/screen_preview` channel. A source is resolved again before creating a
  `GraphicsCaptureItem` via the HWND/HMONITOR interop. A free-threaded capture pool
  converts BGRA to RGBA on its worker and supplies a Flutter pixel texture (preview
  readback capped at 15 fps). Pixel snapshots stay alive through Flutter's release callback;
  resize recreates the frame pool. Stop revokes events and closes the capture before
  asynchronously unregistering its texture. Session generations prevent a late stop
  from stopping a newer preview. C++/WinRT exceptions are enabled only for the runner.
  `ScreenPreviewController` handles startup, status, retry, timeout and disposal outside
  the widget. Closed/minimized/failed sources hide the old texture. The camera is released
  while screen preview is open and reopened afterward. No files, audio, hooks or network.
  Recording will use GPU surfaces and platform encoders; the preview CPU readback is
  not the recording pipeline. Windows capture border remains enabled.
- **Excluded Windows prompter (third slice):** the runner owns one separate Flutter
  engine/window, started at the retained `floatingPrompterMain` entry point. The main
  engine passes only an in-memory script/presentation over `spawnalpha/floating_prompter`;
  the child reads it over `spawnalpha/floating_view`. No file paths, API keys or recordings
  are sent. The host checks Windows 10 build 19041 or newer and confirms
  `WDA_EXCLUDEFROMCAPTURE` before the first frame can show. Unsupported or failed exclusion
  keeps the window hidden. The preview's `FloatingTrialController` owns its lifetime,
  polls visibility and releases late opens after navigation/disposal. Matching session IDs
  stop an old close from closing a replacement. Closing the page destroys the child engine.
  The native window is an independent, frameless, layered tool window with global shortcuts
  (minimizing the main app must not hide it);
  all shortcuts must register before click-through Lock is allowed. Hide/destroy releases
  them and always clears click-through. Drag/resize/dock/snap use native window movement;
  geometry, snap distance and minimum opacity come from design tokens. The child runs
  Timed preview playback using the same controller/view; microphone and recording
  synchronization, a separate HUD and cursor companion still need integration.
- **Windows GPU video saver (fourth slice, not wired to capture yet):** `GpuVideoWriter`
  owns a Media Foundation fragmented MP4 sink and Windows H.264 encoder. D3D11 video
  processing converts captured BGRA surfaces to separate NV12 GPU surfaces per sample.
  Source size changes recreate the converter while fitting into fixed even output bounds.
  Baseline H.264 keeps timestamps ordered. The caller must initialize COM and serialize
  writes/finalization; existing output files fail rather than being replaced. The explicit
  non-shipping native check target encodes/decodes generated colors and validates useful
  completed fragments after an abrupt exit. An optional PCM16 mono/stereo stream
  uses the operating system AAC encoder in the same sink. Audio samples must carry
  non-overlapping common-clock times and positive durations. `MicrophoneCapture`
  pins the chosen/default capture endpoint and uses Windows shared-mode conversion
  to mono PCM16 at 48 kHz; QPC packet timestamps are in 100 ns units. Failed chosen
  IDs never fall back. Real capture/common-clock/UI integration is still pending.
- **Windows recording pipeline (sixth slice, UI integration pending):**
  `ScreenRecordingCore` owns a dedicated MTA worker, free-threaded WGC frame pool,
  copied GPU snapshots, chosen microphone and writer. It never borrows a reusable
  capture-pool surface beyond the frame callback. Video cadence and microphone packet
  times share QPC in 100 ns units; pre-start audio is trimmed, overlaps are removed,
  missing timestamps or discontinuous audio stop explicitly. Output bounds are fixed
  from the first frame, within 1920 px on the long edge, 30 fps. Stop/source loss
  closes capture and finalizes; status retains counts/duration/reason but no private
  content. Native `ScreenRecorder` exposes asynchronous start/status/stop; only matching
  session IDs stop an active worker, and engine shutdown joins it. Dart `ScreenRecordings`
  validates replies and exposes partial results. The explicit native check records its
  own generated window and verifies decoded pixels, resize and audio/video endpoints.
  Durable metadata, recovery, hidden recording controls and setup integration are next.
- **Durable screen takes (seventh slice):** `ScreenTakeStore` reserves a random local
  video name and flushes a pending manifest before native capture. The manifest snapshots
  the script/presentation, source description and audio choice, excluding volatile handles,
  old takes, suggestions and secrets. Finish uses the native `ProbeRecording` worker to
  decode one frame and verify visible aperture, audio track and duration; unfinished
  fragmented MP4 can fall back to encoded-sample times. The library is saved before the
  manifest changes from pending, allowing idempotent retries without losing later edits.
  Startup recovery is serialized with reservations/finishes, ignores external paths and
  symlinks, leaves unreadable files local, and never resurrects deleted scripts. Take's
  extra mode/metadata/camera/recovered fields preserve legacy camera-file compatibility.
- **Recording pause clock (eighth slice):** `RecordingClock` removes QPC pause intervals
  from the shared video/audio timeline and splits microphone packets at pause/resume
  boundaries. The worker keeps monitoring source/microphone health and current pixels/
  levels while paused, but saves no paused audio/video or elapsed duration. Cadence resumes
  on the same timeline; no timestamp reset or growing paused queue. The native/Dart pause
  method uses matching session IDs. Pure clock and decoded silent/audio fixture checks
  verify trimming, fixed paused counts and resumed endpoint alignment.
- **Excluded recording HUD (ninth slice):** `RecordingHud` creates a separate Flutter
  engine at `recordingHudMain`, verifies its own and the main setup window's capture
  exclusion before visibility, and restores the owner's prior affinity on close/failure.
  Native bounds centre countdown on the chosen source and dock HUD on that monitor;
  the widget tolerates native resize arriving one frame before the new phase. The child
  receives only phase/time/mic display data and returns guarded commands; no script or
  file paths. Flutter reports interactive control/grip rectangles, and an in-process
  timer toggles native click-through outside them using transient cursor positions only.
  No input hook or persisted telemetry. Engine shutdown finalizes the recorder before
  destroying the HUD/restoring affinity.
- **Normal Screen recording:** `ScreenTakeController` owns protected windows, countdown,
  pending manifest, native capture and save. Native `release` joins finalization before
  HUD close restores main affinity, including cancellation/disposal and exception paths.
  A failed release keeps protection and prevents a second take. Polling at `recording-poll`
  sends only recording/pause/speech state to the reader and timer/meter to the HUD. Voice
  uses the capture microphone's own RMS and pure `VoiceActivity`; repeated updates never
  restart a manually paused or finished read. Screen capture continues at end of script.
  Setup releases camera in Screen mode and owns inline preview, stopping/reopening it
  around the detailed preview route or recording. Saved/recovered takes are mode-labelled.
  `native_screen_take_check.dart` uses an independently generated window and ignored files
  to test the whole protected silent take; it reads no owner data or private desktop.
- **Paired Windows video core (eleventh recorder slice):** `CameraCapture` opens only
  the selected opaque Media Foundation video-device link. An asynchronous reader
  converts frames to owned top-down BGRA snapshots, handles changed formats/stride,
  and balances callback draining and device shutdown. No default-camera fallback.
  `ScreenRecordingCore` writes a separate silent fragmented camera MP4, bounded to
  1280 px on the long edge; microphone audio stays in the screen MP4. Both pictures
  use the same cadence slot and pause clock. Camera loss/stale frames stops safely
  with a camera reason, including during Pause. Native checks use generated video,
  not the owner's camera; fixture entry points are compiled only into explicit check
  targets. Dart validates paired arguments/counts. `ScreenTakeStore` reserves both local
  paths before capture and verifies their dimensions/durations independently. Paired
  recovery restricts camera paths/links too; missing/unreadable camera output retains
  the useful Screen take, local camera bytes and explicit cameraReadable metadata.
  EN/FR/AR edits and failed-save retries preserve one pair.
- **Excluded camera self-view (thirteenth slice):** `CameraBubbleHost` verifies affinity
  before visibility and starts a separate retained `cameraBubbleMain` engine. Its native
  ellipse and Flutter ClipOval use `camera-bubble-size`; drag is native and close/Hide
  hides only the self-view. The UI-thread timer reads immutable owned `LatestCamera`
  snapshots from `ScreenRecorder`, converts BGRA to RGBA, and retains pixel leases until
  Flutter releases them. It opens no second device, accesses no files, and transfers only
  display name/texture dimensions to the child. Live framing continues during Pause.
  Matching session IDs guard close; recorder finalizes before engine shutdown. Generated
  pause/retained-snapshot and native exclusion/lifetime checks pass; EN/FR/AR widget/layout
  and screenshot cases pass. Its pixel holder is initialized in OnCreate because the
  Win32Window base invokes OnDestroy before initial creation. Preview starts after the
  recorder reaches recording/paused, and raw-pointer conversion keeps the UI copy bounded.
- **Normal Both recording:** setup parses the vendored camera's friendly name and exact
  opaque link separately, opens a preview without audio, and generation-guards late opens.
  At Record it freezes the choice and disposes that preview before the recording owner
  opens protected HUD/reader/bubble and captures. Bubble safety is checked each poll;
  cancellation/disposal owns late replies and release failure retains all protection.
  Missing/unreadable camera output preserves Screen with an explicit local-data warning.
  Both setup is remembered, source/camera framing coexist, and Stop remains enabled after
  setup camera release. EN/FR/AR setup/identity/ownership/snapshot tests pass. The explicit
  `paired_ui_fixture` CMake target compiles fixture-only camera input and uses
  `native_paired_take_check.dart` to test real native windows/channels/clock/store against
  a generated MP4/window without accessing the owner's camera/mic/desktop. It is excluded
  from all normal builds; normal runner has no file/URL camera input path.
- **Windows computer-sound core (fifteenth slice):** `SystemAudioCapture` pins the
  default render endpoint once and uses shared-mode WASAPI loopback with Windows'
  conversion to stereo PCM16 at 48 kHz. It owns each packet before releasing the
  endpoint buffer, propagates timestamp/device errors, and never changes endpoints
  silently. `RecordingAudioMixer` maps both inputs through RecordingClock into a
  bounded two-second stereo ring. Mono microphone is copied to both channels; stereo
  playback stays stereo, duplicate/late samples are trimmed, idle gaps are silent and
  sums saturate rather than wrap. A 100 ms arrival margin is flushed to the saved
  video end on safe stop/loss. Computer sound contributes no microphone meter or Voice
  activity. Its frames/strongest level and failure reason are separate in the guarded
  Dart/native protocol. The explicit audio pipeline check links generated endpoint
  implementations; no real microphone/playback content can reach fixture files. A
  separate format/lifetime check opens real loopback but discards every sample in memory.
  Normal Screen/Both setup offers the explicit Computer sound switch, initially off
  per visit and frozen during a take. The owner passes its snapshot to native start,
  manifest and HUD; recovery preserves that choice without native endpoint IDs.
  Playback-only takes still need an explicit no-microphone choice and Timed pace;
  HUD labels them Computer sound only with an empty microphone meter. Quiet playback
  and device failure warn without losing readable video. Native loopback checks the
  default every 250 ms and stops if routing changes, without opening a replacement.
  `audio_ui_fixture` links only generated endpoints and completes the whole protected
  take via `native_audio_take_check.dart`; a native fixture handshake refuses the
  shipping binary before any capture. This target is excluded from normal builds.
- **Windows cursor companion:** the existing excluded reader engine changes placement;
  it never restarts the timeline, opens a second reader or accesses recording files.
  Pure `CompanionMotion` chooses the trailing side, flips/clamps the entire spring path
  to the pointer monitor's work area and docks after two seconds of stillness. Geometry,
  jitter, rest/poll intervals and spring coefficients arrive from design tokens.
  Native sampling runs only while a following card is visible and capture-excluded;
  hide, dock, reduced motion and destruction release the timer and transient samples.
  Following is click-through and never activates the window. Camera following needs
  an explicit remembered choice; the HUD expands inside its own protected window for
  that choice, keeping Pause and Stop available. The docked reader can request only this
  guarded panel, not arbitrary input forwarding. Its camera reminder contains no device
  IDs. Settings retain one nullable preference, never cursor history. Session IDs and
  the recording owner guard commands and late placement replies. Reader state ignores
  stale visibility polls during placement/show/hide changes, and native resize changes
  preserve WS_VISIBLE. Compact One phrase views step within a phrase
  only when its measured height exceeds the reading viewport, keeping the current word
  visible. Regular reader layout is unchanged. Finalization
  precedes removing capture protection. Generated paired-take checks verify both
  placements, click-through, reduced motion, hide/show sampling cleanup and saving.
- **Optional recording activity:** only opted-in Screen/Both takes create
  `id-activity.jsonl`, reserved in the flushed pending manifest before capture.
  `RecordingActivity` owns one message-only raw-input receiver thread and a 60 Hz
  high-resolution cursor timer. It respects an existing raw-input registration,
  never suppresses legacy input, and releases registration/timer/window on stop.
  Source-window/root and display bounds filter input; own-process windows are
  excluded from cursor, clicks and focus. Only anonymous key counts and a fixed
  Ctrl shortcut enum enter the bounded queue. No characters, scan codes, device
  IDs, window handles or titles enter disk serialization. The encoding worker
  removes pauses through `RecordingClock.Event`, writes source-relative geometry,
  flushes once a second and joins the receiver before finalizing the sidecar.
  Failure stops safely and leaves readable video. Dart inspects JSONL incrementally
  with bounded row size, rejects unknown/private payloads and ignores only a torn
  final row. Recovery limits usable activity to the decoded surviving video duration;
  the original bytes are preserved. Old/off takes have no activity path.
  `recording_activity_check` covers sanitization/common-clock boundaries;
  `recording_activity_runtime_check` verifies receiver lifetime and own-window
  exclusion in memory only. The explicit `activity_ui_fixture` replaces all input
  sampling with generated records. Its Dart handshake refuses normal binaries.
  `tool/native_activity_take_check.dart` exercises full protected saving; `crash`
  exits deliberately, then `recover <generated fixture directory>` tests actual
  partial video/sidecar recovery. No owner input or private desktop is saved.
- **SettingsScreen**: the markup source, API key, model, default style, text
  size and mirror setting, plus **Privacy and licences**: what leaves the
  device, and the licence page (`showLicensePage`).

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

- A library document can select `RecordingAid.script` or `RecordingAid.notes`.
  Old JSON defaults to Script. The immutable `NoteDeck` stores cards separately
  from token indices/marks and survives text edits and aid switches. Manual
  `NoteController` has no playback clock or end-of-take signal. `NoteTimeline`
  stores index changes on the existing recorder clock; paused browsing is
  coalesced on resume. Screen manifests freeze the deck and trim recovered
  chapter indices to surviving video. Camera metadata freezes the same aid.
  The protected child relays only indices to the recorder, never key text.
  Script library disk writes are serialized across editor/recording owners.

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
  Source-window/root and display bounds filter input; display typing requires a
  fully contained foreground window. Modifier-only state tracks raw events in order,
  including key releases, and reserved prompter shortcuts are dropped. Own-process windows are
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
- **Render-core spike and portable plan:** see [render-core-spike.md](render-core-spike.md).
  The non-shipping generated check verifies GPU NV12 decoding, two-stream composition,
  source-range cuts and matching AAC against the existing encoder. The pure immutable
  `model/cut_plan.dart` uses half-open source intervals, maps continuous output time and
  carries no file paths/platform data. This is a foundation, not an enabled export UI.
- **SettingsScreen**: the markup source, API key, model, default style, text
  size and mirror setting, plus **Privacy and licences**: what leaves the
  device, and the licence page (`showLicensePage`).

## Word timing foundation (build step 3)

See [word-timing.md](word-timing.md) for the Windows runtime, pinned
inputs and quality trials still required. Pure `transcription/` types
hold immutable word estimates and assemble tokenizer UTF-8 fragments before
decoding Arabic text. Alignment compares existing normalized script words,
preserves each spoken word/attempt and flags additions/substitutions/misses.
Both restart anchors need exact word runs; punctuation is unspoken. Computation
is bounded to four million cells and runs in a Dart isolate. Larger alignment
preserves the transcript with a review notice. No widgets, paths or platform imports enter the alignment logic.
The separate native test project decodes local media through Media Foundation
and runs a pinned CPU recognizer with suppressed logs and cancellation. Its
15-minute PCM bound is a prototype limit, not a silent product restriction.
The normal Windows runner owns one cancellable `spawnalpha/speech` worker.
It verifies the pinned model with CNG SHA-256, reuses one CPU context across
26-second cores with two-second overlap, and decodes at most 30 seconds of mono
16 kHz PCM at once. DTW audio-attention boundaries estimate actual token times.
Effectively-zero leading/trailing samples may be trimmed for recognition only;
their exact offset is restored, and ordinary room tone/quiet speech is not gated.
Whole UTF-8 words are assembled before overlap selection. Conflicting or zero
word intervals fail explicitly instead of shifting/dropping/inventing words.

`SpeechModels` downloads only public weights with explicit first-use disclosure,
size/hash checks, bounded streaming, cancellation and atomic replacement.
`SpeechProcessor` reads the frozen take aid, recognizes on the native worker,
assembles/aligns in an isolate and atomically saves a versioned local sidecar.
Library attachment preserves later document edits. Notes and explicit
computer-sound-only takes have no script adherence alignment. Older takes with
no snapshot still receive speech captions, with a notice. The original is never
modified. Failed/interrupted jobs can be retried; orphan sidecars remain local.
`Take.wordsPath` is optional for legacy compatibility. Take review shows actual
speech, progress/cancel/retry and local SRT/VTT export; full Cut is still next.

`TakeProcessing` owns the post-stop sequence: installed-only verification,
actual speech, latest take revision and reversible cut creation. Its automatic
path never downloads a model and reuses saved words/cut choices. Explicit setup
can download after disclosure. `SpeechModels` shares a guarded work future so
concurrent checks/setup and cancellation before scheduling cannot start a second
native owner or reset cancellation. Camera/Screen/Both release live input previews
and microphone meters before opening review, carry persistent capture warnings,
and restore setup on return. The saved setting can disable this sequence.
Initial review reads compare word/cut/export revisions before applying results.

`SpokenWord.recognizedText` optionally retains the first recognized spelling;
`withText`/`WordTranscript.withWord` change one word without changing its interval
or probability. Restoring the original clears the correction marker. Legacy JSON
remains valid. `SpeechProcessor.correctWord` loads the requested saved revision,
computes existing frozen Script alignment off the UI thread and atomically saves
a fresh word file. Null alignment never becomes scoring (Notes, computer-only,
older or unsupported scripts). The attachment checks word revisions before/after
disk work and clears stale cuts while preserving export history. Review rebuilds
the quiet plan; caption retiming retains correction provenance. One-word editing
never invents timings for splits/merges/deletions. `ScriptLibrary.save` rolls back
a failed optimistic attachment only while that same document is still current.

## Reversible cleaning foundation (build step 4)

Native recognition also returns conservative 20ms measured quiet intervals,
clipped to the same core clocks. `quietFromWindows` rejects malformed/unordered
evidence and merges touching seams. Saved transcripts keep that evidence;
older sidecars without it remain supported, with no automatic removals.
Pure `cut/clean_plan.dart` protects recognized word neighbourhoods and accepted
marked pauses/breaths. A frozen alignment is required for Script; Notes use
actual speech. Screen takes keep visual context until activity review is wired.
Each quiet removal is immutable and individually reversible. Complementary
kept ranges produce the portable `CutPlan`; `speechOnCut` moves actual captions
onto that clock and rejects any cut that would lose or split a spoken word.
The local cut editor can shrink a quiet removal inside its original measured
proposal, restoring more source sound. `CutChange.originalRange` is an additive
immutable bound; legacy plans use their current range as the bound. Filler and
retake handles are prohibited. Public saves freeze proposal identity/bounds,
review flags and retake provenance, allowing only quiet handles and switches.
The source timeline is a pure union/complement of the same EDL. Editor drafts
do not touch storage until Save changes; the review checks the captured words/
cut revision before writing a fresh plan. The prior player pauses on entry and
does not restart on return. Captions and later batch exports share the revised
clock; earlier plans/media/exports remain intact.
`cut/filler_review.dart` adds disabled proposals from the normalized shared
EN/FR/AR lexicon. Camera Script requires added speech absent from its frozen
script; Notes has no adherence, and Screen remains protected. Candidate and
neighbour confidence margins, complete phrase timing, accepted cue gaps and
80ms measured silence on both sides gate proposals. Binary searches find quiet
boundaries without scanning an entire recording for each word. Proposal ranges
cannot overlap existing quiet changes or each other. An old quiet plan can be
extended while retaining its switch choices.
`CutChangeKind.filler` records consecutive spoken indices and actual phrase,
with additive JSON fields; legacy quiet plans still load. `speechOnCleanCut`
checks that these match complete recognized filler words before excluding
explicitly enabled words from output captions. It retains every other word and
its recognition provenance. Full transcripts and earlier exports are untouched.
New wording revisions rebuild proposals with fillers and attempts kept again.
`cut/quiet_evidence.dart` shares the measured-boundary and confidence margins.
`cut/retake_review.dart` adds immutable, initially unselected `RetakeChoice`
groups from the same frozen alignment. Only complete attempts can replace a
section, and every discarded attempt needs safe measured boundaries. Protected
cue gaps are indexed by the word that owns them: retained words keep their cues;
explicitly discarded attempts may leave with their own cues. Notes, Screen and
null alignment do not acquire choices. `CleanPlan` unions selected quiet,
filler and discarded-attempt intervals without deleting an overlap twice.
Caption retiming validates the actual indices, phrase and source-word times
before excluding complete, confident discarded words. Every other word remains.
Public saves compare proposal provenance against the current saved plan;
only the bounded derivation can enrich an older plan. JSON is additive and
bounded to the same 8 MB limit on write and load. Keep all restores one group;
Restore all also restores quiet/filler choices. Full transcripts and older
exports remain immutable.
`CleanCutStore` computes off the UI thread, writes new atomic sidecars, and
attaches only to the same transcript and cut revision before and after I/O,
preserving current script edits and rejecting stale switches.
`Take.cutPath` is optional; new speech clears stale cuts. `durationUs` now
preserves the exact clock across disk, with `durationMs` retained for compatibility.
Take review renders the switches and exports captions from the selected plan.
The first native video export now uses these kept ranges; remaining Cut tracks
are still next.

## Local take playback

`LocalPlayback` exposes guarded open/status/play/pause/seek/mute/close sessions.
`TakePlaybackController` owns polling, late opens and disposal; a removed view
never keeps its own player. `TakePlayer` renders a paused preview and accessible
controls inside the Studio. Background pause waits for an in-flight playback command and
is bound to its handle/generation; replacing or disposing a player cannot apply
that delayed pause to another session. Native `LocalPlayer` creates Windows
MediaPlayer off the UI thread from a checked local StorageFile. No URI/network fallback,
alternate streams or reparse points. Frame-server previews are bounded to
1280×720 and about 15 fps; immutable RGBA leases survive Flutter's render callback.
This preview bound does not limit full-resolution exports. Stop revokes playback,
closes the OS source, waits for active frame work and releases texture ownership.
OS exceptions and media paths never enter logs or user-facing error text.

Filler review sends an explicit excerpt/request number to `TakePlayer`, returns
to the original file and reveals the player even beyond the list's cache.
The player retains its state while scrolling so old requests cannot replay.
`preview` pauses, seeks, unmutes and plays only the current media/request
generation; manual controls and background pause cancel the excerpt. The
existing 250ms status poll pauses at its end (a listening aid, not a sample-
accurate cut preview). Late status, mute and replay-seek completions also check
the media generation, including backends that reuse a handle value.

## Repeated-section comparison

`review/repeated_sections.dart` groups frozen Script alignment by sentence and
anchored attempt. Each comparable section requires at least three exact matches
(all words for a shorter section). Ordinary script repetition, a lone echo and
Notes do not become retakes. Partial coverage is factual; changed/added wording,
initial unanchored speech and trailing additions stay in the compared source
span. Adjacent sections never duplicate mapped words. Timing, uncertainty and
actual wording stay intact; this comparison supplies no performance rank.

Take review runs this bounded derivation in an isolate only for saved results
with script alignment. Null alignment (including computer-sound-only), Notes
and missing snapshots stay unscored. Wording updates replace the derived list;
generation checks reject stale results after another update or disposal.
`RetakeReviewPanel` pages sections and attempts, and explicit Hear actions reuse
the original excerpt player. The selected saved clean plan now connects safe
Keep attempt/Keep all controls. Partial or unsafe choices stay disabled. Older
plans can add proposals through Review retakes while retaining existing
quiet/filler switches. Filler switches inside a discarded attempt keep their
independent preference but stay disabled until that attempt is restored.
Wording updates rebuild proposals with all attempts kept. Full delivery scoring
and automatic best-performance ranking remain later slices.

## Local video export

`VideoRenderer` sends a portable plan plus explicitly resolved local files to
`spawnalpha/render`. One generation-guarded worker owns COM/MF, bounded PCM
packets, GPU NV12 source frames and D3D11 compositing. A two-frame lookahead
retains source timestamps through preroll and variable cadence. Display
apertures exclude decoder padding. The output clock is fixed at 30 Hz with an
exact shorter final frame; PCM uses cumulative sample boundaries across cuts.
Mono/stereo resample to 48 kHz; short uncovered source tails keep their clocks.
Missing audio produces a silent video. A partial camera disappears at its end.

The complete source picture fits each selected output. Optional paired camera
uses the shared export layout tokens; no inferred face or screen crop. H.264
and AAC use installed Windows encoders. `GpuVideoWriter` keeps fragmented MP4
for recordings and uses finalized MP4 for exports: fragment duration hints
underreported a generated 1080p result. No extra codec/package is shipped.
Output files are created exclusively. Cancel/failure deletes only the file
created by that job after all native handles release, preserving originals.

`ExportProcessor` checks the current saved word/cut revisions, loads actual
speech and retimes captions without losing/splitting words. `VideoExportStore`
flushes a fresh-name reservation before rendering, verifies output dimensions
and duration, then journals completion before caption/metadata/library writes.
Recovery retries complete journals, including caption-save or library failures;
interrupted renders stay unpromoted. If completion itself cannot be journaled,
the unlinked bytes stay preserved for later inspection. File checks are local
and bounded. Shared native recording probes are queued across callers.
`Take.exportsPath` references a new immutable history catalog. Later transcript
or cut changes preserve earlier exports. Review watches the selected saved video
or original, with local file discovery and access to earlier history.

`CaptionOverlay` shapes complete phrases from saved actual speech (including
word corrections) on the kept output clock. The optional first Readable style
uses worker-owned DirectWrite/Direct2D and a private collection of the existing
bundled Anybody/Reem Kufi fonts. Fonts are not installed or downloaded. The
owned BGRA compositor frame gets caption ink before NV12 encoding; one layout
and one target bitmap are cached, with bounded text and at most two lines.
Type, geometry and safe margins come from design tokens. Glyph overhang includes
Arabic diacritics/descenders; failed fitting never clips, drops or fabricates words.
`VideoExport.burnedCaptions` is additive, defaults false for old history and
requires actual caption metadata. Disabling it still writes SRT/VTT. Generated
decoded-pixel checks use the negotiated RGB stride/aperture, including padded
portrait rows, rather than assuming export width equals storage width.

`CaptionWord` preserves whole-word UTF-16 ranges and the exact kept start/end
times. Requests own immutable copies and validate complete coverage, word
limits, surrogate boundaries and chronological intervals on both Dart/native
sides. Readable retains its legacy phrase-only API. Karaoke requires these
actual intervals; missing/invalid timing fails without guessing. A single
stable DirectWrite layout changes brushes per word with `SetDrawingEffect`;
`HitTestTextRange` supplies shaped boxes, sorted in logical order, whose bidi
levels determine underline direction. Geometry is cached per phrase, bounded
by text length; the shadow clears drawing effects first. The plate's footprint
reserves underline height so ink stays inside portrait safe margins. Gaps have
no underline, and every spoken word remains in subtitle phrases.
`VideoExport.captionStyle` is additive with Readable as the legacy default;
local recovery/history and portable metadata preserve each video's choice.
The Studio picker appears only for enabled video captions and stays disabled
during processing. The fixed Cut palette/type controls its exported appearance.
Microsoft API references: [drawing effects](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritetextlayout-setdrawingeffect)
and [shaped text ranges](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritetextlayout-hittesttextrange).

`captionCuesOnCut` aligns the frozen full Script on a worker, then carries each
source word's accepted cue identity through kept ranges, including retakes and
reordering. Only exact reliable or explicitly corrected matches get stress,
energy or pace. Changed/added/uncertain words and Notes get no borrowed cues.
Accepted gaps break phrases. Subtitles stay complete; Punch separately groups
one to three words and isolates stress. Arabic tatweels decorate only display
text; adjusted UTF-16 ranges retain the actual word clock. All non-Readable
styles require complete word timing. `VideoExport.captionMotion` is additive
with true as the old default; local/portable history records Still.

Native Cue/Punch use token-derived deterministic spring transforms on the
output clock, never animated text layout. Static per-word axes and maximum
motion bounds fit first; spaces reserve neighboring stress-pop room. Anybody
supports the width axis; Reem Kufi uses proportional static pace size and
decorative stress. Drawing a bounded shaped phrase with transparent other
words preserves Arabic joining/bidi. Cue skips future words; Punch reveals
the whole chunk; Karaoke dims future words. Still omits transforms and the
progressive underline. Both Cue/Punch retain plate/shadow and safe margins.
The UI starts Cue for wide/feed and Punch for portrait until explicitly chosen,
and starts Still with system reduced motion. Approved Stage defaults stay intact.
Microsoft API references: [font axes](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/win32/dwrite_3/nn-dwrite_3-idwritetextlayout4),
[character spacing](https://learn.microsoft.com/en-us/windows/win32/api/dwrite_1/nf-dwrite_1-idwritetextlayout1-setcharacterspacing)
and [drawing transforms](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-transforms-overview).

`CutPlan.hasJoins` distinguishes discontinuous internal joins from contiguous
source spans and outer trims. New exports start `softAudioJoins` on for those
joins, with an optional review switch and additive history/portable field;
old exports default false. Native `ApplyAudioJoinFade` applies the design's
20ms de-click envelope, half on each retained side, to bounded PCM packets.
It is packet-independent, shortens to tiny ranges and never amplifies or
overlaps audio. No extra samples, caption/word clock shift, source writes or
changes at continuous boundaries. Invalid duration/packet/range inputs fail
before mutation. Generated decoded AAC verifies join attenuation and unchanged
distant tone levels; contiguous split/whole exports have identical decoded PCM.

`ScreenZoomPlanner` streams only bounded click/shortcut/typing-burst targets
from the existing anonymous local activity. Clusters stay within the token
time/distance window; typing needs three timings and a fresh same-size visible
cursor or focus rectangle. Burst evidence must all survive the kept range.
`pointingPhrases` uses the normalized EN/FR/AR lexicon and full frozen Script
alignment to retain only complete exact reliable/corrected actually spoken
phrases. Notes, absent alignment, uncertainty, changed/added words, separate
attempts/sentences and long gaps supply no evidence. A visible click within
the point-window token can count as a target; the whole phrase and click must
survive the same source range. Losing phrase evidence retains the click's
ordinary cluster evidence. Point intervals/text never enter portable tracks.
Oversized/unusable script alignment leaves ordinary activity zooms available.
Discarded/reordered ranges carry only their own targets; contiguous splits
produce the same track. Lead/hold clamp to each range, overlapping targets pan
and a discontinuous cut resets the view. Source dimensions translate resized
window targets into the recording's full-picture fit. Work/targets/keyframes
are bounded, without retaining cursor paths or key identities.

The worker rejects symlink, oversized, misplaced or malformed activity and
returns a generic full-picture notice. Optional Auto-zoom starts on only for
Screen/Both activity; switching off leaves the full image. Immutable export
journals/portable metadata freeze validated target steps, with no activity or
source paths. `zoomCount` is additive, zero for legacy history. Recovery uses
these frozen steps even if activity later disappears. Journals enforce the
same byte bound before writing as the recovery reader uses.

Native `ScreenZoom` evaluates camera-token springs on the output clock,
including over/critical/underdamping and interrupted pans. Even NV12 source
rectangles clamp inside the visible source aperture; destination geometry,
camera inset and captions stay fixed. Generated wide/portrait decoded pixels
verify zoom-in and restored full view; app-channel EN/FR/AR exports verify
wide/feed/portrait on/off, caption clocks, history and unchanged originals.
Microsoft API reference: [video processor source rectangle](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11videocontext-videoprocessorsetstreamsourcerect).

Room-tone crossfades, noise/loudness polish,
face reframing and cursor tracks remain. Exported EDL metadata has no
source media path; private revision references remain in local take history.

`ScreenClickPlanner` collects only visible anonymous click positions, bounded
to 20,000 input/output pulses. It retimes retained clicks through source ranges,
clamps each lifetime at a discontinuity and merges contiguous source splits.
The same strict activity worker creates zoom/click tracks independently. The
Highlight clicks switch starts on for screen activity; Camera and unavailable
traces have no track. Additive `clickCount` defaults zero for old videos.
Journals, portable metadata and recovery freeze validated pulse times/geometry,
without source/activity paths or key/text payloads. Caption clocks stay intact.

Native `ClickOverlay` caches one Direct2D GPU target, draws fixed-token amber
spring rings with radial-gradient halos and fades on each pulse's output clock.
Source resize and current zoom crop map the center into the fixed destination.
Clipping excludes black margins and the paired camera, and captions draw above
the ring. At most the latest 64 active pulses draw. Generated decoded pixels
verify onset/fade in wide/portrait zooms; camera-covered pulses decode identically
to the no-highlight baseline. Actual app-channel EN/FR/AR independent on/off
exports preserve pulse metadata, subtitles, history and original bytes.
Microsoft API references: [ellipse outlines](https://learn.microsoft.com/en-us/windows/win32/direct2d/id2d1rendertarget-drawellipse),
[clipping](https://learn.microsoft.com/en-us/windows/win32/direct2d/id2d1rendertarget-pushaxisalignedclip)
and [radial gradients](https://learn.microsoft.com/en-us/windows/win32/direct2d/how-to-create-a-radial-gradient-brush).

`ScreenShortcutPlanner` consumes only the existing allowlisted shortcut enum,
never plain key timings as text. Bounded source events retime through retained
ranges, merging adjacent continuous spans and clipping at cuts. The latest
badge replaces the previous one (including equal timestamps), giving an
immutable nonoverlapping `ScreenShortcuts` track of labels/start/end, capped
at 20,000. The shared strict worker creates zoom/click/shortcut tracks
independently; Camera and unavailable traces have none. Show shortcuts starts
on for existing Screen/Both activity. Additive `shortcutCount` defaults zero
for old history. Journals, portable metadata and recovery validate exact count,
allowlist and output clock without source/activity paths; recovery never needs
the original sidecar. Subtitle words/times and original media stay intact.

Native parsing and the worker validate the same 14 Ctrl / Ctrl+Shift chords.
A separate `CaptionOverlay` instance uses a private Martian Mono font
collection (already bundled OFL), fixed LTR single-line signal text and
top-left safe-edge glass. Whole-plate smooth spring rise and bounded exit fade
do not reflow text. Standard caption collections/styles stay separate. Generated
decoded wide/portrait pixels verify onset, safe bounds, rise, fade and rejected
private labels; app-channel EN/FR/AR exports exercise independent choices and
exact caption/history/original-byte preservation. No new collection, font
installation, package, model, copied code or upload.

Optional `screenFrame` starts on for Screen/Both even without activity, and
defaults false for legacy exports. The renderer fits the complete source into
the token inset before composing it; zooms keep their source crop/output clock.
Click positions map through that same fixed fitted picture. Native
`ScreenFrame` uses installed Direct2D geometry to mask only the area outside
the rounded screen and outside the independently composed camera rectangle.
The mask receives a locally generated fixed dark gradient and cached Gaussian
shadow effects from the existing shadow-float layers. It draws after click
rings, keeping corners/margins clear, then captions/shortcuts draw above it.
GPU targets, geometry and shadow sources are cached and bounded; camera end
invalidates only the exclusion mask. The installed SDK dxguid library supplies
the Gaussian effect identifier; no dependency or wallpaper asset was added.
Choice/history and recovery preserve originals and exact subtitle clocks.

`cameraPunchesOnCut` derives optional centre-camera accents from already verified
frozen Script caption cues, independently of burned captions and their style.
Only exact reliable/corrected actually spoken accepted stress words qualify.
Notes, missing alignment, changed/added/unsaid words and uncertain speech do not.
Original/output duration and original/retained paired-camera availability must
reach 20 seconds. Entrances stay at least eight output seconds apart; the hold
ends at the word plus 1.4 seconds or a source/camera boundary. Adjacent continuous
source splits merge. Immutable `CameraPunches` contain bounded alternating
entrance/return times only, with no text, face coordinates or private paths.
Additive `cameraPunchCount` defaults zero for old history. Reservation, recovery
and render requests validate the count, duration, spacing and output clock.
Recovery uses the frozen track without rereading later words or camera metadata.

The native renderer reuses the analytic camera spring with a fixed centred
1.12x source crop, separately for the Camera main picture or the Both inset.
The camera's fitted destination rectangle, screen frame/targets and captions
stay fixed. Source discontinuities reset the crop; absent camera frames remain
absent. Direct3D/Media Foundation still stream bounded frames into a fresh local
file. The separate Emphasize the camera choice starts off under system reduced
motion and supports an explicit override. No guessed face tracking, recognition
model, performance score, dependency or upload is introduced.

Failed or cancelled render unwinding shuts down the writer's owned sink before
releasing it, rather than synchronously finalizing an unfinished encoder queue.
Successful recording Stop/export completion still explicitly finalizes samples.
An empty writer has no video to finalize. Generated zero/one-sample exceptions
verify bounded cleanup; only the render's exclusively created output is removed.
Microsoft references: [Finalize can block until completion](https://learn.microsoft.com/en-us/windows/win32/api/mfreadwrite/nf-mfreadwrite-imfsinkwriter-finalize)
and [the creating client owns sink Shutdown](https://learn.microsoft.com/en-us/windows/win32/api/mfidl/nf-mfidl-imfmediasink-shutdown).

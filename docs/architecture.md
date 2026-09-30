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
  `scrollYAt(timeline, t)` is the top of the line being spoken. The line being
  read stays still under the reading line, and the view glides to the next
  line (about 300 ms, no overshoot) as its first word starts. Testers found a
  continuous drift hard to read.
- **Voice pacing** (`ScrollMode.voice`, the default where a microphone level is
  available, Windows for now):
  - The timeline advances only while `speaking` is true.
  - A planned pause still runs out in silence, then the next word waits for
    the voice.
  - `VoiceActivity` (pure Dart) turns microphone levels into "speaking", with an
    adaptive noise floor and hangover.
  - `MicMonitor` (`lib/src/recording/`) polls the level at 20 Hz.
- **The current-word guide** is drawn in every mode:
  - an amber underline fills across the word to say now, over its planned
    length;
  - words already said on that line dim;
  - the reading caret lights amber while the voice is heard.
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

- **LibraryScreen**: the script list, with a button that adds one sample
  script per language and style.
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
  - After a take, `mp4HasAudioTrack` and the loudest level during the take
    catch silent recordings, and the save dialog says so.
- **SettingsScreen**: the markup source, API key, model, default style, text
  size and mirror setting, plus **Privacy and licences**: what leaves the
  device, and the licence page (`showLicensePage`).

# AGENTS.md: guide for agents working on SpawnAlpha

Read this file first, then [`docs/status.md`](docs/status.md) to see where the work stands.
**Update `docs/status.md` before you end a session**: what you finished, what is half done,
and what should happen next. The next agent starts from that file.

## What this is

A teleprompter that coaches delivery. The AI marks up a script with delivery cues (pauses, stress,
pace, energy, breaths), the prompter shows those cues while the user records, and later the app
checks the recording against them. The full product brief is in
[`docs/product-brief.md`](docs/product-brief.md). "SpawnAlpha" is a placeholder name.

Targets: **Windows, Android, iOS**, from one Flutter codebase. Script languages: **English, French,
Arabic** (Arabic is right to left).

## Repository layout

```
AGENTS.md              this guide (CLAUDE.md points here)
docs/
  product-brief.md     the product brief: what to build and why
  status.md            progress log and next steps; keep it current
  architecture.md      how the code fits together, with the key invariants
  design-language.md   entry point to the design language
  roadmap.md           product direction (Director's Cut), pushback, build order (approved)
  compliance.md        licences, privacy, store and consumer-law rules and checklist (commercial product)
  design/              the design language: brand book, prompter, recording, motion, tokens, components
app/                   the Flutter app (package name: spawnalpha)
  lib/main.dart
  assets/fonts/        the design's fonts (OFL) and their licences
  lib/src/theme/       tokens.g.dart (generated from docs/design/tokens.json) and the theme
  lib/src/model/       pure Dart: tokens, marks, script document, remapping
  lib/src/markup/      markup engines: on-device rules and Claude (cloud)
  lib/src/prompter/    delivery timeline, playback controller, guides (the bouncing dot),
                       prompter widget
  lib/src/storage/     scripts and settings on disk
  lib/src/ui/          screens
  test/                mirrors lib/src/
  tool/                dev tools: screenshots_test.dart renders the screens to PNG;
                       gen_tokens.dart regenerates lib/src/theme/tokens.g.dart
```

## Toolchain and commands

- Flutter **3.47.5 stable** (Dart 3.13). Run every command from `app/`.
- `flutter pub get`, then `flutter analyze` (must print "No issues found!"), then `flutter test`
  (must pass).
- Run it: `flutter run -d windows`, or an Android or iOS device. Windows builds need a Windows
  host and iOS builds need macOS; a Linux container can only analyze and test.
- Claude Code cloud containers don't include Flutter. Install it into the session scratchpad:
  ```sh
  curl -sSL -o flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.5-stable.tar.xz
  tar xf flutter.tar.xz && export PATH="$PWD/flutter/bin:$PATH"
  git config --global --add safe.directory '*'
  ```
- **CI:** `.github/workflows/build.yml` runs on every push to `app/` or `.github/`:
  - `flutter analyze` and `flutter test`;
  - then a Windows build and an Android APK, uploaded as run artifacts (test builds only).

  Flutter comes from the official release archive, checked against its published SHA-256
  (`.github/actions/setup-flutter`). Keep `FLUTTER_VERSION` in the workflow equal to the
  version above. Don't add third-party actions without checking them like any other
  dependency.
- **Seeing the UI without a device:** `flutter test tool/screenshots_test.dart --update-goldens`
  renders every main screen to `app/tool/screenshots/*.png` (git-ignored):
  - Home (desktop, dark, phone and first run), the library, the editor (desktop, dark and
    phone), the mark sheet and settings;
  - the prompter (kinetic in a hold, still, each guide, One phrase, and the dot acting out
    each cue);
  - the record screen and the countdown;

  for all three sample scripts, with the bundled fonts, including Arabic.
  Open the PNGs to check layout and right-to-left rendering after UI changes. Add a case there
  for any new screen.

## Conventions

- **Follow the design language** in [`docs/design/`](docs/design/) (start at
  [`docs/design-language.md`](docs/design-language.md)) for every UI change:
  - use its tokens, and never add literal colours, sizes or durations. In Dart they are
    `SaPalette`, `SaType`, `SaSprings`, `SaSpace` and friends (`lib/src/theme/`). Change a
    token in `docs/design/tokens.json`, then run `dart run tool/gen_tokens.dart` from
    `app/`;
  - keep the Studio (themed) and the Stage (always dark) apart;
  - draw cues only with the cue vocabulary's glyphs and colours;
  - keep the prompter hidden from capture in the screen modes;
  - drive motion with the `spring` tokens, and never animate anything that reflows script text;
  - use the four type voices only for their jobs: display for one hero per screen and
    captions, reading for everything read, signal for timers and stage labels, pencil for
    the director's notes.

  If a change needs something the design language lacks, add it there first.

- **Keep logic out of widgets.** `model/`, `markup/` and the timeline and controller in
  `prompter/` must not import Flutter widgets, so they stay unit testable. Widgets only render and
  forward input.
- **Immutable data.** `ScriptDocument` and `Mark` are immutable; edits return copies
  (`copyWith`, `withText`, `applySuggestion`). Run marks through `normalizeMarks` whenever you
  build a new list.
- **Marks point at token indices, never at character offsets or inline tags.** Read
  `docs/architecture.md` before you change how marks are stored.
- **Every text feature must work in English, French and Arabic.** Add test cases in all three
  when you touch tokenizing, word lists or markup rules. Word lists live in
  `lib/src/markup/lexicon.dart` and are normalized on load, so write entries naturally, with
  accents or hamza.
- **Right to left:** set `Directionality` from `ScriptLanguage.isRtl` wherever script text shows.
- **AI providers:** the markup prompt, reply schema and parser live in
  `markup/markup_prompt.dart` and are shared by every language-model engine. Claude uses its
  native Messages API over raw HTTP (`claude_markup_engine.dart`; there is no Dart SDK), with
  default model `claude-opus-5-5`, structured outputs, streaming and `fallbacks: "default"`.
  Every other provider goes through `openai_compatible_engine.dart`. Add a new provider as a
  preset in `markup/providers.dart`; write a new engine only if it can't speak either protocol.
  Keep request shapes in line with each provider's current docs, and never put model names in
  commit messages.
- Tests sit under `app/test/`, mirroring `lib/src/`. Add or update tests with every change.
- Lints: `flutter_lints` plus the rules in `app/analysis_options.yaml`.

## Gotchas

- **Don't put `WidgetSpan`s inside script text.** Flutter misplaces them in right-to-left
  paragraphs. Cue icons are icon-font glyphs (`cueSpans` in `prompter/marked_text.dart`).
  The reason is in `docs/architecture.md`.
- **Write invisible or bidi characters as escapes** (`'\u202F'`, `'\u2068'`), never as
  literal characters. Some editing tools turn an escape into the raw character, which is
  invisible in review; check with a search for the code point after editing.
- Some Material icon code points lie outside the basic plane and take two UTF-16 units.
  Measure text offsets with `toPlainText().length`, never by counting spans.
- In widget tests, a `Ticker`'s first frame has elapsed time zero. Pump once after `play()`
  before pumping a duration.
- In widget tests, anything that calls `WakelockPlus` needs its platform channel mocked (see
  `tool/screenshots_test.dart`).

## Commercial and legal

SpawnAlpha is sold (free tier plus subscription), so licences, privacy law, store rules and
consumer law are part of every change. Follow the rules in
[`docs/compliance.md`](docs/compliance.md):
- check a licence before adding any dependency, font, model or copied code (no GPL or AGPL,
  no non-commercial assets);
- keep data on the device unless the user sends it, and say so in the UI;
- never log scripts, recordings, keys or typed characters;
- keep the checklist current.

## Working agreement

- Work on the branch you were given; commit small, descriptive commits; push when done.
- Follow the build order in the brief. Don't start a later step until the earlier one works.
- Record product decisions (a model choice, a pricing limit, a name) in `docs/status.md` under
  "Decisions", and update the brief when a decision changes it.

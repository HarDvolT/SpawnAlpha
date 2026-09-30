# Status

Last updated: 2026-09-30

## Where we are

**Build step 1 of 4: script markup and coached prompter. In progress.**
(Build order is in [product-brief.md](product-brief.md#build-order).)

| Area | State |
|---|---|
| Flutter app scaffold (`app/`, Android, iOS, Windows) | Done |
| Data model: tokens, marks, script document, remapping marks through edits | Done, tested |
| On-device markup engine (EN, FR, AR; three coaching styles) | Done, tested |
| Cloud markup engine (Claude, Messages API, structured outputs) | Done, tested against a mock HTTP client; not yet run against the live API |
| Delivery timeline and prompter playback (timed and manual scroll) | Not started |
| Prompter widget (cue rendering, RTL, mirror mode) | Not started |
| Editor UI (write, pick style, run markup, review marks and suggestions) | Not started |
| Camera recording (mobile and Windows) | Not started |
| Local storage of scripts and settings; API key in secure storage | Not started |

## Next steps

1. Delivery timeline (`lib/src/prompter/delivery_timeline.dart`): word timings from WPM, pace
   marks and gap marks, so the scroll holds at pauses.
2. Prompter controller and widget.
3. Storage, then the editor, prompter, recording and settings screens.
4. Run the app on a real Windows machine and an Android phone, then fix what breaks.

## Decisions

- 2026-09-30: The Flutter app lives in `app/`, leaving the repo root free for docs and any
  later backend.
- 2026-09-30: Marks are anchored to token indices, not character offsets or inline tags. Text
  edits remap them with a word-level diff (see [architecture.md](architecture.md)).
- 2026-09-30: The markup has two engines: an on-device rule-based one (free, offline) and Claude
  (cloud, higher quality). Until the subscription backend exists, users bring their own Claude
  API key. Default model `claude-opus-5-5`. The brief's open question about which cloud model to
  use is still open; the model id is a setting.

## Open questions (from the brief)

- Which cloud model to use for markup, and how much the free tier includes.
- How reliably stress can be detected from volume and pitch (needs a prototype, step 2).
- App name.

## Session log

- 2026-09-30: Added the brief to `docs/`. Scaffolded the Flutter app. Built the model layer, the
  on-device markup engine and the Claude markup engine, with 41 passing tests. Added
  AGENTS.md, CLAUDE.md and this file.

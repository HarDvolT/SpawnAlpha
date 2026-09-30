# Architecture

This covers how the app is built and the rules the code relies on. For what the product is, see
[product-brief.md](product-brief.md); for progress, see [status.md](status.md).

## Layers

```
ui/        screens and widgets       (Flutter)
prompter/  timeline + controller     (pure Dart)  +  prompter widget (Flutter)
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
  - `origin` is `local`, `cloud` or `user`.
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

Both implement `MarkupEngine.markup(ScriptDocument) -> MarkupResult`, which returns pending marks
and suggestions. `applyMarkup` merges a result into a script: it keeps accepted and user marks,
replaces the old pending proposals, and replaces the suggestions.

- **`LocalMarkupEngine`**: free, offline, deterministic apart from mark ids. It reads
  punctuation, line breaks and `Lexicon` word lists (steps, actions, emphasis, conclusions,
  calls to action, conjunctions, numbers, units, wordy phrases) for each language, and applies
  the rules of each style:
  - **Presentation:** a long pause after paragraphs, questions and sentences with numbers;
    stress on numbers and claims; slower pace on sentences with numbers; an energy lift on
    conclusions and the close.
  - **Tutorial:** a long pause before each step (first, then, ensuite, ثم...); stress on the
    action verb; slower pace on technical terms (camelCase, file.ext, acronyms, mixed digits).
  - **Short social video:** a short pause after the hook; heavy stress, with a punch word in
    the hook; faster pace through long sentences; energy on the hook and the call to action.
  - **All styles:** breaths once a stretch passes the style's `wordsPerBreath` (at a comma, or
    before a conjunction); a short pause after a mid-sentence colon; "tighten" suggestions for
    wordy phrases; hook advice when the opening line is long.
- **`ClaudeMarkupEngine`**: sends the script as `[index]word` pairs, with a system prompt built
  from the style and language, and requests JSON that matches `responseSchema` (structured
  outputs), streamed over SSE. Each returned mark repeats its words; `locateWords` checks them
  and moves a mark up to 6 tokens to the nearest match, or drops it. Suggestions must quote the
  exact original text. It retries 429 and 5xx responses twice, honouring `retry-after`, and
  turns refusals, `max_tokens` stops and HTTP errors into `MarkupException` messages fit to show
  the user.

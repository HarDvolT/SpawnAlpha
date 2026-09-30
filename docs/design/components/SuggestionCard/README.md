# SuggestionCard

A rewrite the markup proposes, with the original, the replacement, a short reason, and Apply and Dismiss.

- **Use** in the editor's Marks view, under the script, one card per suggestion.
- **Consumer provides** the kind (Stronger hook or Tighter line), the original text, the replacement (none for advice-only cards, which show "Got it" instead of Apply) and the reason.
- Original in `ink-2` with a line through it; replacement in `ink` at weight 600; reason in `caption`. Set both texts in the script's direction.
- Apply rewrites the script, and cues on surviving words move with them. Dismiss removes the card. Neither asks for confirmation; after Apply, the snackbar offers Undo.
- Card: `surface`, `line` border, `radius-md`, no shadow.
- **Don't** apply suggestions automatically or in bulk.

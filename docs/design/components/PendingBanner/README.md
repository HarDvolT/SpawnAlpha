# PendingBanner

The banner above the script while proposed cues wait for review, with the count, Discard and Accept all.

- **Use** in the editor's Marks view whenever at least one cue is pending. It disappears when none are left.
- **Consumer provides** the number of pending cues and the two handlers.
- The count sits in a `cue` disc with `on-cue` text; the banner is `surface` with a `line-strong` border and `radius-md`. Accept all is the cue button; Discard is plain.
- Before the stage opens with pending cues, ask once in a dialog: "Accept all" or "Leave them out". The prompter shows accepted cues only.
- **Don't** block editing: the person can keep typing, tapping words and accepting cues one by one.

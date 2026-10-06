# Speaker notes

Requested by the owner on 2026-10-06 for videos spoken freely, without a complete
script. This is an additional recording aid alongside the coached prompter.
The initial UI label is **Notes**: "Speak freely from topic cards."
This feature is specified and queued; it is not implemented yet.

## A private presentation for the speaker

A note deck is an ordered list of cards. Each card contains an optional topic
title and short bullet points: reminders of what to talk about, not sentences
the speaker must read exactly. The first version lets the person create, edit,
reorder and remove text cards. It does not require a slideshow file or a cloud
service. Notes are distinct from the AI director's annotations on a script.

Before recording, choose **Script** or **Notes** independently of **Camera**,
**Screen** or **Screen + camera**. Notes work with each recording mode. The
camera/source/microphone checks and explicit record-without-sound choice remain
the same. Script retains its existing saved guide, motion, alignment and pace.

Notes show one card at a time. There is no automatic scrolling, bouncing word
guide, timed advance or requirement to follow the text word for word.

- **Next** advances one card; **Previous** returns to one already seen.
- The counter reads "Card 2 of 6" and the buttons have accessible names.
- Start on card one for a new take. Practice can browse the deck without capture.
- At the first/last card, the corresponding navigation button is disabled.
- The last card stays visible. Reaching it never stops a recording, including
  Camera mode. Stop is always a separate recording control.
- Advancing cards never pauses/resumes the take or changes the microphone.
- While the take is paused, cards can still be browsed to prepare the next topic.

## Desktop window and shortcuts

Reuse the protected floating reader host: always on top, movable, resizable,
hide/show and Lock. In screen modes, verify capture exclusion before showing
any notes. If exclusion fails, keep notes hidden and show the existing plain
error/retry state. The captured audience sees the selected screen/camera only;
the notes window and its navigation controls are never part of the output.
Camera mode keeps notes outside the camera's recorded pixels.

Use the reader's existing reserved global chords in Notes mode:

| Shortcut | Notes action |
|---|---|
| Ctrl+Shift+Right | Next card |
| Ctrl+Shift+Left | Previous card |
| Ctrl+Shift+L | Lock/unlock |

The arrow shortcuts navigate sentences only in Script mode, and cards only in
Notes mode. Register/unregister them under the existing reader lifetime rules,
and verify navigation/unlock is available before allowing click-through Lock.
Prompter Play/speed controls do not appear as note controls. Recording Pause and
Stop remain available in the protected HUD. Reserved chords must stay excluded
from activity timing, just like the existing prompter shortcuts.

On phones, Notes use the existing Stage panel beside the camera preview, with
Previous/Next buttons; no desktop global-shortcut promise applies there.

## Design and language

Edit cards in the Studio and present them on the always-dark Stage. Reuse
`stage-glass`, `radius-lg`, existing spacing/control tokens and the reading face
for titles and bullets; use the signal face for the counter. Speaker notes are
reading content, not pencil annotations or a new display type voice.
Do not add literal colours, sizes or durations. New values must enter tokens
first if layout testing shows an existing token is inadequate.

Use a restrained opacity transition driven by the existing spring tokens when
the selected card changes; reduced motion switches cards immediately. Never
animate text reflow while the person reads. Long content scrolls within the
card without obscuring navigation; empty cards need an explicit edit state.

Card text and titles support English, French and Arabic. Directionality follows
the deck language, including RTL bullet alignment. Logical previous/next order
and the named keyboard commands stay stable. Test large text, keyboard access,
screen-reader announcements, reduced motion and Arabic on minimum window sizes.

## Storage, timing and speech processing

Use an immutable deck/card model and a pure manual navigation controller, separate
from ScriptDocument token marks and PlaybackController. Save decks locally.
Capture a deck snapshot when a take starts, so later note edits cannot change the
meaning of an old take. Preserve old scripts/takes when adding the new content kind.

Record the selected card index on the same pause-adjusted take clock, not the
wall clock. Initial selection and each change can later anchor topic navigation.
Coalesce browsing during a recording pause into the final selection on resume;
do not generate fake chapter durations or text from intermediate paused cards.
These events stay beside the take, do not contain typed keystrokes, and are
separate from the optional mouse/key activity switch.

For Notes takes, captions come from what was actually said. Card text may help
with vocabulary, but is never treated as a verbatim script. Do not label
paraphrased bullets as missed/changed words, fabricate their word times, or score
script adherence. The pending word-processing integration must branch on the
take's recording aid. Review/retake policies for free speech remain later work.

Notes and takes stay on the device. Nothing is sent to an AI provider merely
because a deck is written or recorded. Any later cloud action needs an explicit
named action and the same privacy/notice rules as script markup.

## First implementation slice

Build/save the immutable text deck and test manual Previous/Next boundaries in
EN/FR/AR. Then add the Studio card editor and Stage view, connect the protected
reader/recording controls and shortcuts, and test real capture exclusion. Add
screenshots for every new screen, durable deck snapshots/card clock tests, and
an owner trial of button and shortcut navigation. Keep the existing Script path
and approved defaults intact. No dependency or imported asset is needed for this
text-card version.

# Take review

After a new recording saves, Camera/Screen/Both open this review directly,
carrying any sound/camera/activity warning as a persistent reading-voice notice.
The recorder releases live previews and microphone meters while reviewing.
**Record another** returns to setup after processing ends or is cancelled.

**Make a cut after recording** starts enabled in Settings. It checks only the
installed offline model, then finds actual words and saves a reversible cut.
Automatic processing never downloads anything. If speech is not set up, review
explains the 148 MB public model and offers **Find spoken words** for explicit
setup. Saved words/cuts are reused when reopening; review does not repeat a job.
Progress/cancel spans the installed-model check, speech and cut saving. Failure
keeps the original and any successfully saved words for retry.
Setup and active processing sit above the video preview so their progress and
cancel action are visible without scrolling. Record another aligns to the left.

The take opens in the themed Studio with a paused local video player. Play/pause,
seek and mute controls sit below the picture and support keyboard focus and
accessible labels. The preview uses the Stage dark background inside the Studio,
with the review width/height tokens; portrait previews keep their aspect ratio.
It never starts sound automatically. Leaving the view closes the player;
backgrounding the app pauses it. Failed playback has a generic retry message and
the file remains available. Playback uses the Windows platform first.
Its original stays on the device and is
available through **Show original file**. Use the reading voice for the title
and transcript, signal for the word count, and the existing Studio spacing.

**Find spoken words** starts local processing. First use says that it downloads
a 148 MB public speech model from Hugging Face; recordings and scripts are never
uploaded. Download, verification, recognition and saving have progress states.
Cancel keeps the original. Offline speech is Windows first and supports takes
up to 24 hours; other platforms show that limit plainly.

The transcript keeps actual speech in English, French or Arabic. Arabic has its
own right-to-left Directionality. Frozen Script takes may show words missed or
changed; Notes takes are free speech and never receive script adherence scores.
Computer-sound-only takes never receive delivery scores either. Older takes
without a snapshot use actual speech, with an explanation.

Word times are estimates. Invalid or conflicting times stop processing with a
plain retry message; never shift, drop or invent words to make a cut possible.
**Review wording** expands a paged word list with original-clock times in tenths
of a second. Arabic wording aligns to the right. Words
without confidence or below the existing 0.6 confidence guard say **Check wording**; this is an estimate,
not a speech-quality score. Corrected words say **Corrected**. Each word has an
**Edit word** action. Its Studio dialog uses reading type and the transcript's
direction for the field, with **Cancel** and **Save word**. Keep one timed word
per entry: splitting, merging or deleting words needs separate timing work.
Invalid input says **Enter one word, with its punctuation if needed**.
**Restore word** returns the original recognized spelling. Changes retain the
recognizer's original text, confidence and time range. They never claim a new
recognition or better timing. A new immutable local word revision recomputes
existing frozen Script alignment; Notes/computer-sound-only remain unscored.
Rebuild the quiet cut from that revision, preserving originals and earlier
exports. Saving is atomic and cannot be cancelled midway. File/save failures
keep the earlier words and show a generic retry message. Captions follow the
latest saved words. The list uses existing Studio spacing, type and size tokens.
No speech is an explicit empty result. **Copy transcript** is an explicit local
clipboard action. **Save SRT + VTT captions** writes both local subtitle files;
it does not publish or overwrite the original video.

This surface now includes the first **Your cut** panel: original/cut duration,
the measured quiet-gap changes, an individual switch and **Restore all gaps**.
Saved plans and cut-caption clocks preserve all actual words. Screen context
and missing/uncertain script alignment keep the original. Video preview,
individual word corrections and coaching will extend it, using the same frozen
take and actual speech.

**Possible filler** choices extend this list using the conservative evidence
rules in [autoedit.md](autoedit.md#first-windows-filler-review). The phrase uses
reading type and its language's direction. Its switch starts off and the label
says **Kept · check meaning**; it only removes the phrase after the person
chooses it. Other words, accepted pauses and breaths remain protected. Restore
all changes brings back every gap and filler. An older quiet plan has **Review
fillers**, which preserves its existing switches. No new style tokens are needed.
Each filler has **Hear this phrase**. It returns the player to the original,
reveals it and plays the phrase with 600ms of context on both sides, clamped
to the file. This explicit action turns preview sound on and pauses after
the excerpt on the existing playback poll. This is listening, not a rendered
sample-accurate cut preview. Manual Play/Seek/Pause ends excerpt mode;
backgrounding, replacing the file and leaving the screen cancel it. Initial
review/reopening never starts sound. Scrolling retains the player and cannot
repeat the previous request. Player ownership must reject late commands.

**Compare attempts** lists repeated sections found in a frozen Script take.
Each section shows the intended script in reading type and each attempt's
actual words in their language direction, source time, exact matches out of
the section's word count, changed/added words and uncertain wording. A partial
attempt is labelled **Partial section**. **Hear attempt 1**, **Hear attempt 2**,
and so on use the same explicit original excerpt player. Page the sections and
attempts so long takes remain usable. Existing Studio tokens apply.
**Keep all attempts** starts selected. Safe complete choices offer **Keep
attempt 1**, **Keep attempt 2**, etc.; the selected one says **Kept in cut** and
the others **Removed from cut**. Hearing always plays the original. Disabled
choices explain that the section is partial or a safe cut was not found.
Older plans offer **Review retakes**, preserving their quiet/filler choices.
Keep all restores this section, and Restore all changes restores all passes.
This comparison makes no best-performance claim: loudness, pitch and full
breath/pace scoring remain subsequent work. Notes and computer-sound-only takes have no script
comparison. Ordinary repetition written into a script is not a retake.
Comparison runs off the UI thread, follows saved wording revisions and rejects
stale results. Nothing is uploaded or cut by listening.

**Open in editor** opens a local draft of the saved cut. A source timeline shows
kept and removed ranges with text labels as well as colour. It uses Studio
tokens; time always reads left to right. Tapping a range explicitly plays that
original excerpt, never the draft automatically. A list has the existing
gap/filler switches and retake choices. For shortened quiet gaps only, two
handles adjust which part of the originally safe removal stays removed:
dragging inward restores sound. Keep the handles within the initial proposal,
so editing cannot cut an extra word, marked pause or screen activity. Fillers
and retakes remain whole choices. Keep a gap, or reset its handles to the
initial proposal. Show the resulting duration immediately. Page long lists.

**Save changes** returns the draft to review and writes a new cut revision;
**Cancel** or Back discards the draft. Detect changed word/cut revisions before
saving. Reopening remembers the handles and original safe bounds. Previous
plans, original media and earlier videos stay intact. Captions, room-tone
eligibility and later batch exports use the new cut clock. This first editor
does not extend a removal beyond its measured quiet proposal or add arbitrary
speech cuts. No new data collection, dependency or upload.

**Chapters and description** prepares editable local text for the current cut.
Use the take's frozen aid and saved actual speech, including corrections;
never use the later edited script. Description is an excerpt of retained speech,
not a cloud summary. Script paragraphs have chapters only where a reliable exact
retained word anchors the section. Notes use the frozen card titles and saved
card clock; never copy private bullet bodies or score script adherence. Missing
card timing leaves chapters unavailable rather than guessing. Merge sections
that start within the same whole second. The first retained chapter starts at
zero; subsequent times follow the cut. Say that starts are estimates and need
checking, and that earlier videos may use another cut.

Show title/description in reading type and their language direction. Chapter
times use left-to-right signal type; titles use reading type in their direction.
Allow changing title/description/chapter titles and keeping/removing each chapter.
Page chapters. **Copy text** uses the clipboard only; **Save text files** creates
a fresh local folder with title, description, chapters and combined text/JSON.
The user can open that folder. Save/copy are explicit and never post or upload.
Previous files/media/exports remain intact; drafts are discarded on Back.

**Save your video** makes a separate local MP4 from the saved cut (or the whole
take when no cut exists). The first Windows renderer fits the complete picture
inside 16:9 1080p/4K, 9:16 or 4:5; unused space stays black. Screen/Both with
local activity offer **Auto-zoom screen activity**, initially on. Nearby clicks,
shortcuts and anonymous typing bursts produce spring zooms on the kept clock.
Reliable actually spoken frozen Script pointing phrases also justify a nearby
visible click. Notes/uncertain/unsaid words and discarded phrases supply no
bonus; ordinary click clusters still work. English, French and Arabic use
their normalized language lexicon. Switching off keeps the full picture.
**Highlight clicks** starts on and has its own switch. Retained visible clicks
get a fixed amber spring ring and soft halo on the output clock. The pulse ends
at a source cut, follows zoom/resize geometry, stays inside the screen picture
and leaves the camera/captions clear. History lists the click-highlight count.
No keys, typed text or hidden cursor positions appear; old videos have none.
Missing/unreadable activity explains
the full-picture fallback. History lists the zoom count. Original media/input
remains intact; no typed characters are used. Face reframing remains separate.
Both takes can include the separate camera in
the bottom-right corner, fitted inside 28% of each output dimension with a 4%
short-edge margin. These proportions are `video-export` tokens. A switch can
omit the camera. The original sound keeps its source clock through each cut.
**Soften sound at cuts** appears for internal discontinuous joins, starts on
and can be switched off. A short 20ms envelope uses 10ms of each retained side,
with no overlap or clock change. Continuous spans and outer edges keep their
sound. History labels the choice as **Soft sound joins**. Noise/loudness and
room tone are independent controls. **Use room tone at cuts** starts off and
appears only with soft joins and a retained measured quiet sample clear of
recognized words. It adds that bounded sample beneath join edges without
overlapping words or changing clocks. Source-coordinate decisions survive
history/recovery. Native quiet validation falls back to the ordinary fade
when the sample is unsuitable; the saved label records the room-tone choice.
See autoedit.md for the conservative word/quiet gates. Optional background
noise reduction and S sound softening start off, and volume balance starts on.

Progress has **Cancel export** until saving starts. Saving verifies decoded
dimensions and duration before attaching history. Each saved video shows its
date, format and duration, with **Watch saved video** and **Show saved files**.
Earlier exports remain available after restoring a gap or processing speech
again. The player labels saved videos and provides **Watch original take**.

**Also save other formats** starts off. Enabling it reveals chips for formats
besides the main dropdown choice. Keep at least the main format; extras are
explicit, including 4K. The action says **Save 2 videos**, etc. Each video uses
the same frozen take, cut, caption style and effects. Save them sequentially
to limit memory and GPU use. Show the current format, video number and overall
progress. Cancellation stops the active render and the remaining queue; while
the current file is being attached, **Stop after this video** finishes that
file and skips the rest. A failure stops the queue and explains how many videos
were saved. Every completed version remains playable. Completed-job recovery
still protects interrupted attachments; unfinished queue entries are not
silently started after reopening the app. No extra dependency or upload.
Actual SRT/VTT captions and the portable cut plan save beside each video.
**Put captions on video** starts enabled when actual words exist. Its first
Windows style is **Readable**: complete phrases in the display face (Anybody,
Reem Kufi for Arabic), centered in the lower third on the fixed caption plate
and shadow. Words come from the saved transcript, including corrections, on
the selected cut clock. Safe margins keep vertical captions above the bottom
21%, below the top 13% and left of the rightmost 14%; other edges use 6%.
The short output edge scales the 1080px caption type and geometry tokens.
Fit at most two lines, shrinking to the caption minimum if necessary; fail
explicitly rather than clip or omit words. The switch can keep just subtitle
files, and history records whether captions are on the video. Original media
is never changed. **Caption style** offers **Readable**, **Cue**, **Punch** and
**Karaoke**. Cue starts for wide/feed formats and Punch for portrait until a
style is chosen explicitly; changing format then preserves that choice.
Karaoke keeps the shaped phrase stable, lights each word at its actual start
and sweeps an amber underline across its saved duration, in each glyph run's
direction. Gaps have no invented underline. History shows the chosen style;
older exports remain Readable. Caption type, dim ink and underline geometry
come from fixed Cut tokens. Cue words rise at their saved starts; Punch uses
one to three words in the center, with a stressed word alone. Reliable exact
frozen Script matches carry accepted stress/energy/pace cues; other actual
words and Notes keep their wording without invented cues. Arabic stress is
decorative only; subtitle wording stays unchanged. **Still captions** removes
transforms and the underline sweep while keeping timing/color. System reduced
motion starts Still; the explicit switch can choose motion. History records
style and Still separately. Sound polish and smooth cut transitions remain.

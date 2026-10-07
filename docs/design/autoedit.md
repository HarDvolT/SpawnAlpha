# Director's Cut

The Director's Cut is the edit that is ready when you stop recording. The goal is that most takes need **no editing at all** before they are published, and the rest need one or two decisions. It is possible because SpawnAlpha knows three things other recorders have to guess:
- **the script**: what you meant to say, word for word;
- **the cues**: where you meant to pause, stress and change pace;
- **the telemetry** of a screen take: every click, key burst and window.

## The pipeline

A take goes through five passes. Their output is one **edit decision list** (EDL): source ranges, a caption track, a cursor track and zoom keyframes. The finish screen, "Open in editor" and the renderer all read and write that EDL. Nothing is baked until export.

### 1. Align
- Transcribe the take with word-level timestamps, using the script as the vocabulary and prompt. This runs on the device (whisper.cpp) or through the chosen online provider.
- Align the transcript to the script tokens. Each token gets a time range, or is marked **missed**. Spoken words that aren't in the script are marked **added**.
- Detect **restarts**: a script span spoken twice or more. Each attempt is a candidate retake.

The **Notes** recording aid has no verbatim script. Transcribe its actual
speech for captions; the deck can provide vocabulary and timed topic anchors.
Never force bullet text into word alignment, call paraphrases missed/changed,
or use script-adherence scoring on free speech. Its review/retake policy needs
separate implementation; see [speaker-notes.md](speaker-notes.md).

### 2. Clean
- **Dead air:**
  - Gaps longer than 0.7s shrink to 0.25s.
  - **Marked pauses are kept** at their marked length, give or take 30%, and breaths are kept too. This is the rule no generic silence-remover can follow.
- **Fillers:** remove filler words that are outside marked pauses and not in the script:
  - English: "um", "uh", "like", "you know";
  - French: "euh", "ben", "du coup", "genre";
  - Arabic and Darija: "امم", "يعني", "واش", "إيه".
- **Retakes:** keep the best attempt at each span. It is scored on:
  - match with the script;
  - fillers;
  - pace against plan;
  - pauses held;
  - stress landed, detected from loudness and pitch on the stressed words.

  The list shows "1 of 2".
- **False starts:** remove partial words before a restart.
- **Cutting:** never cut inside a word. Cuts land in silence of at least 80ms, with 20ms audio crossfades and room tone under any gap.

### 3. Polish
- **Captions** are written from the **script**, timed by the alignment. Where you said something different, the caption follows **what you said** and the difference is flagged.
  - Phrases break at gap cues and sentence ends. The markup already knows where a caption should end.
  - Stressed words pop in amber at width 125. Slow runs set wide (118) and fast runs narrow (82).
  - Arabic stress stretches with kashida.
  - There are three styles; see CaptionStyles.
- **Zooms** come from telemetry:
  - A cluster of two or more events (clicks, a typing burst, a shortcut) within 1.3s and 30% of the screen gets one zoom, to `zoom-default`. A small target gets up to `zoom-max`.
  - A lone click gets a ripple, not a zoom.
  - Script words that point ("here", "this button", "ici", "هنا") near a click also zoom.
  - Zooms lead by `zoom-lead` and hold for `zoom-hold`. Nearby clusters pan instead of zooming out and in.
- **Cursor:**
  - It is smoothed (70ms follow) and drawn at `cursor-scale`.
  - It hides after `cursor-idle`.
  - Clicks get ripples.
  - Modifier chords show as keycap badges. Plain typing is never shown.
- **Frame:**
  - The screen is inset 6% on a backdrop, with `radius-md` corners and a soft shadow.
  - A window capture crops to the window.
  - Motion blur is directional and proportional to camera speed, capped at `blur-max`.
- **Camera takes:**
  - A subtle punch-in to 1.12× on `spring-camera` at a stressed phrase, at most once every 8s. It is off for takes under 20s.
  - The camera bubble slides out of the way of the cursor and of zoom targets.
- **Sound:**
  - Loudness is normalised to −14 LUFS.
  - Noise is reduced on the device (RNNoise class).
  - De-essing is light.
  - No music is added unless the person asks for it.

### 4. Review: the one-question rule
- If the edit is confident, it decides and lists what it did.
- If it isn't, it asks **one clear question** with the choices spelled out. Examples:
  - "At 1:48 you said 'Tuesday'; the script says 'Thursday'."
  - Two retakes too close to call.
  - A zoom target it can't find.
- It asks at most three questions per take. Anything beyond that, it decides and lists.

### 5. Export
- **Formats**:
  - 16:9 at 1080p or 4K.
  - 9:16 at 1080×1920. It reframes on the face for camera takes, and on the zoom target and cursor for screen takes.
  - 4:5 at 1080×1350.
  - Each is one tap on the finish screen, and several export together.
- **Safe zones in 9:16:** keep captions and faces out of the platform UI areas:
  - top 13%;
  - bottom 21%;
  - right 14%.
- **Captions** are burned in, or exported as SRT and VTT from the script, so they are correct.
- **Chapters and descriptions:** chapters come from the script's sections. A title and description are proposed from the script. They are never posted automatically.

## The finish screen

See the DirectorsCut component. It has:
- a headline;
- the duration rolling from the take to the cut;
- the preview in 16:9 with the 9:16 inset;
- the edit list with a switch per change;
- the one question, if there is one;
- the timeline, which tightens as the edit plays out;
- the export row.

The ship action is amber: **Export 2 videos**. **Open in editor** shows the EDL as a normal timeline with every automatic cut as a soft edit that can be dragged back.

## Guarantees

### First Windows cleaning slice

Automatic silence changes require measured quiet audio, not just a gap between
estimated word times. The first detector uses conservative 20ms frames with
RMS at most -60 dBFS and peak at most -60 dBFS. It leaves ordinary room tone and
quiet speech alone if they do not pass that gate. These are evidence thresholds,
not a loudness-normalization claim. Keep 250ms of each long quiet interval.

Keep every recognized word with a safety margin, all accepted marked gaps and
breaths, and any interval near low-confidence words. Script takes with no usable
frozen alignment keep the original. Notes never use script adherence. Screen
takes need separate activity/context handling before automatic tightening.

Every removal is listed with its source time and an individual switch. Turning
it off restores that original interval; saving the plan never modifies media.
Caption times follow the kept source ranges and actual speech. Filler/retake
selection and screen zoom/cursor polish are subsequent slices; never label this
conservative first pass a finished Director's Cut.

### First Windows filler review

Possible fillers are review choices, initially kept. Vocabulary alone cannot
tell a hesitation from meaningful "like", "du coup" or "يعني"; do not remove
these automatically before real-language evidence exists. Use the language's
normalized filler phrases from the shared lexicon. Script candidates must be
added speech outside the frozen script and outside accepted pauses/breaths;
Notes use actual speech without adherence. Screen context remains protected.
Require recognized confidence of at least 0.6, safe neighbouring words and
measured quiet intervals of at least 80ms on both sides. Reject uncertain or
overlapping boundaries, never split words or infer silence from timestamps.
Existing quiet choices survive reviewing fillers.

The edit list says **Possible filler** and shows the actual phrase in its
language direction, source times and a removal switch. **Kept · check meaning**
is the initial state; choosing removal excludes only those complete words from
cut captions and video, retaining all other words. **Restore all changes**
restores fillers and quiet gaps together. Originals, full transcripts and
earlier exports remain available. **Review fillers** extends an older quiet
plan without changing its switches. New wording revisions rebuild the plan
with fillers kept again. Full retake scoring and sound crossfades remain later.

### First Windows retake selection

Repeated frozen Script sections start with **Keep all attempts**. After hearing
them, **Keep attempt 1**, **Keep attempt 2**, etc. selects a complete section
and removes the other attempts from the cut and actual captions. Partial or
unsafe choices stay disabled with a plain explanation. Require measured quiet
of at least 80ms at both cut boundaries, word safety margins and confident
discarded wording. Notes, computer-only and Screen context remain protected.
Accepted pauses/breaths owned by retained words stay protected. Cues owned by
an explicitly discarded attempt may leave with that attempt; this does not
shorten a retained attempt's planned pause. All original words/media remain.

Selections are immutable, bound to the words/cut revision and saved locally.
Keep all restores just this section; Restore all changes also restores silence
and fillers. Existing quiet/filler switches keep their choices when retake review
is added. Wording edits rebuild proposals with all attempts kept. A performance
rank is not inferred from word matching: full pitch/loudness/pace scoring remains
later. Every selection changes video and subtitle clocks together.

### Windows room-tone joins

**Use room tone at cuts** is a separate saved-take export choice, initially off.
It is offered when the current cut has internal joins and frozen measured quiet
audio has a retained 100ms sample clear of every recognized word by 100ms.
Choose the first eligible source sample deterministically. Removed ranges,
uncertain wording, a script gap alone and an unavailable quiet analysis never
supply sound. Notes and Script use the same actual-speech protection.

Mix that same quiet sample under the existing 20ms join envelope, returning to
the retained sound outside its edges. Keep the source and output clocks fixed;
never overlap speech, add duration or put words back into a discarded section.
Both the final renderer and volume prepass use the same bounded sample and mix.
Treat the quiet sample with the selected noise and de-essing stages first.
Native decoding rechecks the conservative -60dBFS peak/RMS quiet gate; an
unusable sample leaves the ordinary fade in place. A missing or disabled choice
keeps the ordinary join behavior. Save the immutable source sample coordinates
and choice with the video; originals and earlier versions remain intact.

The control says **Uses quiet sound from the parts you keep. Words and timing
stay the same.** Actual listening remains needed before making it a default.

### Windows volume balance

Save controls offer **Balance sound volume**, initially on. The choice can be
changed after recording and on a reopened take. Measure retained mono/stereo
sound with K weighting and gated 400ms windows on the output clock, then apply
one fixed gain toward -14 LUFS. Cap amplification at 12dB and reserve a -2dB
estimated true-peak ceiling using four-times oversampling. Peak protection may
leave a take quieter than the target. Silence and audio shorter than 400ms
keep their volume. No compressor pumping, noise-removal claim, added samples,
timing change or source modification. Existing sound joins are measured and
applied consistently. The new version and saved choice keep earlier exports
intact; legacy exports have the choice off. This first sound slice does not
replace noise reduction, de-essing or room-tone work.

### Windows light de-essing

**Soften harsh S sounds** is a separate after-recording export choice. It starts
off until the person chooses it, and can be changed later for any saved take.
A 5kHz high-pass detector compares smoothed high-frequency energy with total
energy. A soft knee above a 55% energy ratio and a -42dBFS floor gates a linked
mono/stereo gain reduction of at most 3dB, with a 2ms attack and 80ms release.
The high-pass filters only the detector: the output is the original full-band
sound multiplied by this gentle gain, preserving stereo balance and phase.
This is light wideband de-essing, without a learned model or language guesses.
The same treatment precedes volume measurement and final gain. Source cuts
reset the detector; contiguous ranges preserve it. It adds no samples/delay,
leaves silent/short takes unchanged and never modifies originals/earlier videos.
An explicit choice affects the whole saved mix, including computer sound.
Noise reduction and room-tone joins remain separate work.

### Windows steady-noise reduction

**Reduce background noise** is an independent saved-take export choice,
initially off. Explain that it is best for steady hiss/fan noise and affects
the whole mix, including computer sound. Use the classic SpeexDSP noise
estimator with AGC, echo cancellation, reverb and VAD audio removal disabled.
Limit suppression to -12dB and blend 65% treated sound with the aligned
original. It is not a neural model or a promise to remove other voices/music.
Process bounded 10ms mono/stereo blocks and compensate the processor's 10ms
overlap delay, including first/last partial blocks. Never borrow samples from
discarded ranges: reset at source cuts and flush with silence. Contiguous
ranges preserve state and a common rounded audio clock. Noise treatment
precedes S softening, join fades and volume measurement/final gain, using
the identical pipeline twice. Shorter-than-400ms/silent-source takes stay
unchanged. Earlier videos/originals stay intact; legacy exports remain off.

### Windows sound joins

**Soften sound at cuts** starts enabled when the selected plan joins separated
or reordered source ranges. It applies a `audio-join-fade` 20ms de-click
envelope, half on each side of the join, without overlapping words or changing
the video/subtitle clock. Adjacent continuous ranges and the take's outer
edges keep their sound. Tiny ranges shorten the envelope to their available
room; gains never exceed one. The switch can keep the original cut sound.
History records the choice for each saved video. This first sound slice is a
join fade, not a room-tone crossfade, noise reduction or a LUFS normalizer.

### Windows activity zooms

**Auto-zoom screen activity** uses only the anonymous local sidecar, and can
be disabled before export. It groups at least two clicks/shortcuts/typing
bursts within `zoom-cluster-window` and `zoom-cluster-distance`. Three anonymous
key timings make one typing burst; no typed text or arbitrary key identity is
read. Key/shortcut positions require a recent source-sized focus rectangle or
visible cursor. A lone click remains full-picture until ripple rendering exists.
Use `zoom-default`, or `zoom-max` for a measured small focused target. Enter
at `zoom-lead` before the first event and hold until `zoom-hold` after the last.
Overlapping zooms pan on `spring-camera`; the source boundary resets the view
when a discontinuous cut enters another range. Never borrow removed activity.

Coordinates keep their source dimensions through resizing and translate to
the recorded full-picture fit before cropping. Clamp the viewport to the
recorded image; no guessed face targets or hidden windows. Captions retain
their output clock and safe zones. Save the local zoom decisions alongside
the export without the private source/activity path. Missing or unreadable
activity keeps the whole picture and explains that choice. Cursor cleanup,
keycaps, backdrop and directional blur remain subsequent tracks.

For a frozen Script, a nearby click can also use reliable actually spoken
pointing phrases: English "here"/"this button", French "ici"/"ce bouton"/
"cette option", and Arabic "هنا"/"هذا الزر"/"هذه الخانة". Use the normalized
language lexicon and the full source alignment, never Notes bullets or unsaid
script text. Every phrase word must be an exact reliable or explicitly corrected
match in the same attempt, without extra words or a long intervening gap.
`zoom-point-window` is the maximum distance from the spoken phrase to the click.
Both the click and the whole phrase must survive the same kept source range;
discarded attempts cannot supply evidence. A visible click still supplies the
position. The ordinary Auto-zoom switch controls these targets too, and no
transcript text is written into portable zoom metadata.

### Windows screen motion blur

Screen zoom exports offer **Soften zoom motion**, initially on unless system
reduced motion is requested. The switch can be changed after recording or from
a saved take. Directional blur follows the largest viewport-edge displacement
between frames, scaled by a 16ms shutter and capped at `blur-max` (6px at a
1080px short edge). Below 0.5px it draws nothing; a still frame stays sharp.
Only the screen picture is blurred, before composing the camera, click rings,
shortcuts, captions and rounded frame. Source cuts reset motion so they never
produce a blur flash; continuous source splits preserve it. Disabling zooms
removes this effect. No blur is added to Camera takes or static camera emphasis.
Save the choice with each new video; old versions remain unchanged and legacy
exports have it off. This is local rendering with installed Windows effects,
without a new dependency, asset, upload or recognition claim.

### Windows camera placement

Screen + camera exports with saved local activity offer **Keep the camera clear**,
initially on unless system reduced motion is requested. The switch applies to a
new saved version and works after reopening a take. The bubble keeps its size
and vertical position, sliding between the two lower corners on `spring-camera`
only when its current corner covers a fresh visible pointer or an active zoom
target. Pointer targets hold for 700ms, coalesce within 2% of source dimensions,
and expire at source cuts. A 24px clearance at a 1080px short edge protects the
target. A 1400ms minimum between moves prevents rapid corner hopping. When both
corners are occupied, retain the current corner; never hide or shrink the camera.
Do not spring back just because activity ends. A discontinuous cut resets to
the lower-right corner; continuous source splits do not reset motion.

Targets use the existing explicitly enabled local activity only: no new hooks,
typed characters, face inference or upload. Resize/letterbox/zoom/frame mapping
must match the screen compositor. Click effects and frame masks follow the same
moving camera rectangle. Missing camera frames remain absent. Notes need no
script alignment. Bounded immutable target windows and the switch survive
history/recovery; old exports keep their fixed corner.

### Windows camera emphasis

Scripted Camera/Both exports offer **Emphasize the camera**, initially on
unless system reduced motion is requested. Zoom the camera's centre to
`camera-punch` on spring-camera at reliable actually spoken accepted stress
words. Use the frozen Script and retained source-word identity, independently
of caption style and whether captions are burned in. Notes, absent alignment,
uncertain/changed/added/unsaid words and unaccepted cues never trigger it.
No face target is guessed and this is visual emphasis, not a delivery score.

Both the original and edited duration must reach `camera-punch-minimum`.
For a partial paired recording, the available original camera and its retained
intervals must also reach that minimum; never emphasize a missing camera frame.
Space entrances by `camera-punch-interval` on the output clock; return after
the word plus `camera-punch-hold`, clamped at discontinuous source cuts.
Continuous source splits preserve the effect. Keep the camera rectangle,
screen/zoom targets and subtitle clock fixed. The separate switch disables
the effect; hiding the paired camera removes its emphasis track too. Save
bounded immutable entrance/return times and count without transcript text.
The camera follows the existing centre crop; face reframing remains later.

### Windows screen frame

**Frame the screen** starts on for Screen/Both exports and has an independent
switch, including takes without activity. Fit the complete screen picture
inside `frame-inset` on every output axis. Do not crop extra source content.
Keep zoom crops on their existing output clock inside this fixed placement.
Use radius-md corners scaled by the short output edge, a fixed dark gradient
from dark surface to dark paper, and the existing dark shadow-float layers.
The camera stays at its ordinary output corner and size; do not resize it with
the screen. Click targets map through the inset and stay clipped outside the
camera and rounded corners. Captions and shortcuts retain their safe positions.
Turning the frame off restores the full-picture placement with black margins.
Save the choice with each immutable video; old exports remain unframed.
The backdrop is generated locally, with no wallpaper assets or downloads.

### Windows shortcut badges

Screen/Both with local activity offer **Show shortcuts**, initially on and
independent of zooms and click highlights. Show only the existing allowlisted
Ctrl and Ctrl+Shift chords for A, C, S, V, X, Y and Z; ordinary typing never
becomes text. Keep the modifier label left to right in every script language.
One glass keycap uses the bundled Martian Mono signal voice at
`keycap-font-size` / `keycap-line-height`, signal-label weight, stage-text on
stage-glass, radius-md and space-3 padding. It sits at the top left with the
export's safe edges (13% top / 14% right in portrait), clear of bottom camera
and captions. The whole plate rises `keycap-rise` on spring-smooth, without
reflow, and fades for `keycap-fade` at the end of `keycap-duration`.

The newest chord replaces the previous badge. Clamp at discontinuous source
cuts, merge continuous source splits, and keep retained/reordered times on
the output clock. Save a bounded immutable label/time track without private
paths or typed text. Native validation also rejects unapproved labels.
Missing activity draws no badges; history remembers each video's badge count.

### Windows click highlights

Screen/Both with local activity also offer **Highlight clicks**, initially on
and independent of Auto-zoom. Every retained visible click gets the fixed amber
ring and soft halo from the motion language: `ripple-radius` grows to
`ripple-grow` on `spring-smooth`, fading over `ripple-duration`. Geometry scales
with the short output edge. Hidden clicks, plain keys and removed source
activity draw nothing. Clamp the lifetime to the retained source range;
continuous source splits preserve the same effect and cuts never carry it into
another range. Map source dimensions through the current zoom crop, clipping
to the visible screen picture and outside the camera inset. Captions draw above
the highlight. Save immutable normalized pulse/timing decisions without paths,
key identities or text. At most the latest 64 simultaneously active pulses
draw, with bounded tracks and work; unusual oversized input keeps a plain video
with the same generic activity notice. Legacy exports have no highlights.

### First Windows video export

Effects are chosen after recording and can be changed when reopening a saved
take. Beneath the save controls, say: **Add or remove effects after recording.
Each save makes a new version and keeps your original and earlier videos.**
Toggling an effect applies to the next saved video; it never overwrites an
existing MP4. Camera emphasis still uses the take's frozen accepted cues and
reliable spoken words. No re-recording or recording-time effect choice is needed.

The saved plan now renders to a separate finalized H.264/AAC MP4 in 16:9
1080p/4K, 9:16 or 4:5. This slice fits the complete source on black space unless
optional screen activity zooms are enabled. Face reframing,
further sound polish and room-tone crossfades are still pending.
Optional Readable, Cue, Punch and Karaoke captions now follow saved actual
speech, using bundled display fonts, the fixed caption plate and safe margins.
Corrected words and subtitle files share the kept clock. Cue reveals words
with a rise; Punch shows one to three centered words, with stress alone.
Reliable exact frozen Script matches supply accepted stress/energy/pace cues;
Notes, changed/added/uncertain words never borrow them. Cue identity survives
discarded/reordered attempts. Karaoke fills stable phrases and sweeps a
directional underline over saved word intervals; no phrase-divided timing.
Still omits transforms/sweeping, starts with system reduced motion and is
saved with each export. SRT/VTT keep complete actual phrases without decoration.
Both can include its separate camera in a token-sized corner inset.
Source ranges drive video, bounded audio and actual SRT/VTT captions together.
Progress/cancel, decoded verification, recoverable completed jobs and immutable
saved-video history are part of take review; see [take-review.md](take-review.md).

- Never cut inside a word, and never remove a marked pause.
- Never change what was said. Captions follow speech, and mismatches with the script are flagged.
- Every automatic change is listed, can be undone on its own, and survives into "Open in editor".
- Telemetry and takes stay on the device unless the person chooses an online provider for transcription.

## Honest limits

- **Arabic, Darija and code-switching.** Whisper-class models are good at English, French and Modern Standard Arabic. They are clearly weaker on Moroccan Darija and on Darija–French switching. Expect more flags and weaker filler detection there until we test with real speakers and choose or tune a model. This decides how good the Cut feels for a core audience, so it needs early testing.
- **Retake choice is a heuristic.** It is right most of the time, and when it is close it asks.
- **Rendering needs a native core.** Flutter can't encode video or composite zooms, blur and captions at speed. The Cut needs a native pipeline, which is the largest engineering item in the product:
  - platform encoders (Media Foundation, MediaCodec, AVFoundation), or an LGPL FFmpeg build;
  - GPU compositing;
  - reached from Flutter through FFI, with a Rust core as the likely choice.
- **Speed on low-end laptops.** Preview plays the EDL in real time at preview quality, and the final render runs in the background. 4K60 with blur will be slow on low-end laptops.
- **Face reframing** needs on-device vision (ML Kit or MediaPipe class). It is fine on current phones and PCs, and costs battery.

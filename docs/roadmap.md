# Roadmap and product direction

**Status: approved by the owner on 2026-09-30.**
- The build order below is now the brief's build order.
- The Director's Cut is the core promise.
- The cursor companion may follow the mouse with the camera on, after a one-time warning.

The design is in [design/](design/), with the auto-edit in
[design/autoedit.md](design/autoedit.md).

## The direction: "finished when you stop"

SpawnAlpha records camera, screen or both, with a coached prompter that is never recorded. When
the take ends, a **Director's Cut** is already waiting:
- silences trimmed, with the pauses you marked kept;
- fillers removed and the best retake kept;
- zooms on your clicks;
- captions written from the script, with stressed words popping;
- a vertical version.

The person checks the list of changes, answers at most a few questions, and exports.

The script and its cues are what make this possible. Other recorders guess where a sentence
ends, which pause was deliberate, and which of two takes was the good one. SpawnAlpha knows,
because the script says so.

## Pushback on the owner's ideas (2026-09-30)

These are the places where the owner's requests were built differently, or where a risk needs
saying plainly.

1. **"The prompter follows the mouse."**
   - This is right for screen-only recording. There it became the **cursor companion**: a
     small glass prompter beside the cursor that docks under the lens when you stop moving.
   - It is **risky on camera**: eyes that chase the mouse look shifty. **Owner's decision:**
     it is allowed with the camera on, but docked by default. Turning it on shows a
     one-time warning, and the card then carries an "eyes to the lens" reminder.
2. **"Animated text popups and growth."**
   - The big pops belong in the **captions** viewers see (the Cut).
   - On the prompter, motion must stay subtle, because the speaker is reading. The **kinetic
     prompter** only animates words near the reading line, and it never reflows a line.
   - A Still mode keeps just the scroll and the holds.
3. **"Little to no editing before publishing."**
   - This is achievable because the script drives the edit.
   - It is also the largest engineering item in the product. Flutter can't encode video or
     composite zooms, motion blur and captions. It needs a **native render core**, reached
     through FFI, with a Rust core as the likely choice. The options are platform encoders
     (Media Foundation, MediaCodec, AVFoundation) or an LGPL FFmpeg build, plus GPU
     compositing.
   - The edit is stored as a renderer-agnostic edit decision list (EDL), so the engine can
     change later.
4. **Auto-zoom, smooth cursor and motion blur are table stakes, not the moat.**
   - Screen Studio, OpenScreen, Tella, Descript and CapCut all do some of this. We have to
     match them, but they are not why anyone would switch.
   - The moat is:
     - coaching the delivery;
     - an edit driven by the script: correct captions, kept pauses, retakes chosen by script
       match, zooms on the words "here" and "ici";
     - Arabic and French treated as first-class.
5. **Arabic and Darija are a real risk.**
   - Whisper-class models do well on English, French and Modern Standard Arabic, and clearly
     worse on Moroccan Darija and on Darija–French switching.
   - The review and the Director's Cut both depend on word alignment. Test with real speakers
     early, before promising the Cut in Arabic.
6. **Phones are limited.**
   - Android records overlays, unless the recording uses single-app sharing (Android 14 and
     later).
   - iOS can't float a prompter over other apps, so screen recording there needs the
     companion prompter on a second device.
   - The desktop gets screen features first.
7. **Scope.** This is now three products in one: a prompter, a screen recorder and an editor.
   Ship it in slices that are each useful on their own.

## Proposed build order

| # | Step | Why here |
|---|---|---|
| 1 | Markup and coached prompter (**done**, device testing pending), then apply design v2 to the app | The base everything else uses |
| 2 | **Windows recorder**: Camera, Screen, Screen + camera, with a hidden Prompter window, HUD and cursor companion, telemetry capture and fragmented MP4 | Screen recording is now a core mode. The Cut needs the telemetry. Moved up from step 4 |
| 3 | **Word alignment**: whisper.cpp word timings aligned to the script tokens | The foundation for the review, the Cut, retakes and voice-follow |
| 4 | **Director's Cut v1**: trims (dead air, fillers), captions from the script (Cue and Punch), auto-zoom, smooth cursor, ripples, backdrop, 16:9 and 9:16 export, and the finish screen | The promise users will notice first |
| 5 | **Delivery review and retakes** | Shares the alignment. Best-take choice feeds the Cut |
| 6 | **Voice-follow scrolling** | Uses the same recogniser, running live |
| 7 | **Mobile parity**: Android screen (single-app), iOS companion prompter, face reframing | Platform limits make these slower |

## Owner's decisions (2026-09-30)

- The Windows recorder comes next, as step 2. **Yes.**
- "Finished when you stop" (the Director's Cut) is the core promise. **Yes.**
- The cursor companion is allowed with the camera, with a warning. It stays docked by
  default when a camera is recording.
- The next work in the app is to apply design v2.
- Still open: the render core. Spike it during step 2, so the risk is known early. Codec
  patents and licences favour the platform encoders (Media Foundation, MediaCodec,
  AVFoundation) over a bundled encoder; see [compliance.md](compliance.md).

## Fonts (design v2)

- **The fonts:** Anybody (display), Readex Pro (reading), Martian Mono (signal), Caveat
  (pencil), Aref Ruqaa (Arabic pencil) and Reem Kufi (Arabic display).
- **Licence:** all are under the SIL Open Font License, which allows bundling them in the app.
- **Source:** download them from Google Fonts and bundle them as assets. Don't fetch them at
  run time.

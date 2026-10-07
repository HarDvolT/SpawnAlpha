# Teleprompter Recorder: Product Brief

Draft · 30 Sep 2026 · Repo: [HarDvolT/SpawnAlpha](https://github.com/HarDvolT/SpawnAlpha)

## The idea

This is a teleprompter that coaches your delivery. Most teleprompters only show your words. This one uses AI to direct how you say them: where to pause, which words to stress, and when to slow down or lift the energy. It shows those cues while you record, then checks afterwards how well you delivered them.

**Pitch:** the AI directs, you perform, the AI checks.

The owner also requested **Notes mode** on 2026-10-06: a private deck of talking
points for a video spoken freely. It is an additional recording aid, alongside
the scripted prompter; its design is in [design/speaker-notes.md](design/speaker-notes.md).
It is implemented on Windows, including capture exclusion and frozen take cards.

## Who it's for

The app is for three kinds of speaker, and each script gets a coaching style that sets how the AI marks it up.

| Style | Coaching goal | Typical marks |
|---|---|---|
| **Short social video** | Grab attention in the first seconds and keep the energy high | A strong hook, short punchy pauses, heavy emphasis, faster pace |
| **Presentation** | Sound confident and persuasive | Longer pauses around key points, stress on numbers and claims, steady pace |
| **Tutorial** | Be clear and easy to follow | Pauses between steps, slower pace on technical terms, stress on actions |

## How it works

### 1. Before recording: script markup
- The user writes or pastes a script and picks a style.
- The AI returns the script with marks added:
  - pauses, short or long
  - words to stress
  - pace changes, slower or faster
  - energy lifts
  - places to breathe
- The AI can also suggest a stronger hook or tighter lines.
- The user can accept, edit or remove each mark. Marks are stored as structured data rather than as text in the script, so the prompter can render them.

### 2. While recording: the coached prompter

Starting choices approved by the owner on 2026-10-05: Dot guide, One phrase motion,
Center alignment, Kinetic word effects and Voice pace when a microphone works
(otherwise Timed). The other choices remain available and saved per device.
- Cues appear visually:
  - stressed words are larger or in color
  - pauses show as a visible gap or icon
  - pace shows as color or a pace bar
- The scroll follows the user's voice and holds at each pause mark.
- The app records the camera, the screen, or both, with a screen and webcam layout on desktop.
- On desktop, the prompter window is hidden from the screen recording.

### 3. After recording: delivery review
- The recording is transcribed with word-level timings and lined up against the script.
- The review checks:
  - whether each pause was taken
  - whether each stressed word stood out, through a rise in volume or pitch
  - whether the pace (words per minute) stayed in range
  - how many filler words ("um," "like") were used
  - which lines were skipped or changed
- Each section gets a score. The user can jump to the weakest one and retake just that section.

### Speaking freely with Notes

- Prepare cards with a topic title and a few bullet-point reminders.
- See one private card while recording Camera, Screen or Screen + camera.
- Move to the next/previous card with a button or desktop shortcut.
- Notes stay hidden from the recording; the last card never ends the take.
- Speak in your own words. Captions follow the recorded speech, and review does
  not judge whether each note was read word for word.

## Decisions so far

- **Recording aid:** Script for coached reading, or Notes for private manually
  advanced talking-point cards. Requested by the owner on 2026-10-06.

- **Effects after recording:** add or remove effects such as camera emphasis
  from a saved take, including when returning later. Each save creates a new
  video and keeps the original and earlier versions. No re-recording is
  needed. Clarified by the owner on 2026-10-07.

- **Platforms:** Windows on desktop plus Android and iOS. The proposed stack is **Flutter**, which covers all three from one codebase.
- **Languages:** English, French and Arabic.
  - Scripts, markup and speech analysis must work in all three.
  - Arabic needs right-to-left layout in the prompter and the editor.
- **AI runs both locally and online.**
  - Transcription can run on the device with whisper.cpp, for offline use and privacy.
  - Windows starts with a verified multilingual base model, downloaded explicitly
    on first speech use. This is an implementation default, pending real French,
    Arabic, Darija and code-switching quality trials. Word times remain estimates.
  - Script markup and review can also use a cloud model, for higher quality.
- **Business model:** a free tier plus a subscription. The subscription is the natural home for the online AI, because it costs money per use.
- **Name:** to be decided later. The repo is called SpawnAlpha for now.
- **Core promise:** "finished when you stop". The Director's Cut edits every take automatically from the script, its cues and screen telemetry, so most takes publish without manual editing. Decided 2026-09-30; spec in [design/autoedit.md](design/autoedit.md).
- **Windows captions:** Readable, Cue, Punch and Karaoke are implemented.
  Cue starts for wide/feed export and Punch for portrait until explicitly
  chosen. Still starts with system reduced motion. All styles follow actual
  saved words; reliable frozen Script matches supply accepted cues, and Arabic
  decoration never changes subtitle spelling. Decided 2026-10-06.

## Build order

Revised 2026-09-30 by the owner. Screen recording moves up, and the automatic edit becomes the core promise. The reasons are in [roadmap.md](roadmap.md).

1. **Script markup and coached prompter.** This includes timed or manual scroll and camera recording on mobile and Windows. It delivers the core value on its own. Then apply design language v2.
2. **Windows recorder.**
   - Camera, Screen, and Screen + camera.
   - The prompter window, HUD and cursor companion, all hidden from capture.
   - Cursor, click and key-burst telemetry for the edit.
   - Private Notes cards as an extension requested on 2026-10-06, with manual
     navigation independent of the selected recording mode.
3. **Word timing.** Word-level transcription aligned to the script. The review, the Director's Cut, retakes and voice-follow all build on it.
4. **Director's Cut v1.** The automatic edit, ready when you stop:
   - automatic processing starts enabled after offline speech setup, with a
     Settings switch; it checks installed weights without downloading;
   - trims that keep marked pauses, and filler removal;
   - captions from the script;
   - Windows screen activity auto-zoom is available with an on/off export
     choice and saved target/history track, including reliable spoken EN/FR/AR
     pointing phrases near a visible click; optional amber click highlights
     are connected too, along with optional glass shortcut badges for
     allowlisted modifier chords. Ordinary typing stays hidden.
     Optional rounded screen frames, local dark backdrops and soft shadows
     are connected. Optional paired-camera placement avoids fresh pointers
     and zoom targets using saved local activity and a reversible export
     choice. Optional directional blur follows screen zoom/pan springs and
     keeps the camera, captions and still frames sharp. Optional camera emphasis uses reliable spoken accepted
     Script stress cues, with a subtle centred crop, a separate switch and
     a reduced-motion default. It stays off for takes/cuts under 20 seconds
     and spaces entrances by eight seconds. Optional paired-camera placement
     and directional screen motion blur are connected. Optional sound balance
     measures retained audio, applies one gain toward -14 LUFS, caps boosts at
     12dB and protects estimated true peaks with -2dB headroom. The choice can
     change after recording; originals and earlier videos stay intact. Smooth
     cursor remains. Optional room-tone joins use only retained measured
     quiet audio clear of recognized words, with an independent later choice
     and fixed word/video clocks. Optional classic background-noise
     reduction is connected, initially off, using a commercial BSD-3 backend
     without learned weights. It targets steady hiss/fans, preserves the
     output clock and explains whole-mix scope; see [noise-runtime.md](noise-runtime.md).
     Optional light
     wideband S sound softening is connected, starts off, and limits gain
     reduction to 3dB without filtering the audible output or adding delay;
   - 16:9 1080p/4K, 9:16 and 4:5 exports, with optional serial batch saving
     from one frozen cut/effect choice; finished versions survive cancellation;
   - the finish screen.
     Windows take review now has a local cut editor: restore more of a shortened
     quiet gap with bounded handles, keep/revert individual changes and save a
     fresh cut revision. Broader timeline operations and chapter text remain.
5. **Delivery review and section retakes.** The best take is chosen by how well it matches the script.
6. **Voice-following scroll.** This needs real-time speech recognition on the device.
7. **Mobile parity.** Android screen recording (single-app sharing), a companion prompter for iOS, and face reframing.

## Reference project: OpenScreen

[getopenscreen/openscreen](https://github.com/getopenscreen/openscreen) is a desktop screen recorder and demo-video editor. It's under the MIT license, built with Electron, TypeScript and Rust, and very active. It supports Windows, macOS and Linux, but not mobile.

**Decision:** use it as a reference and a source of parts, not as the base of the app.

- **It can't be the base.** Electron doesn't run on phones. Most of its code is for demo-video editing (zooms, cursor effects, wallpapers), which this app doesn't need.
- **Parts worth reusing or learning from.** The MIT license allows reuse as long as its copyright notice is kept.
  - Local transcription with whisper.cpp, including snapping to word boundaries. This is the core of the delivery review.
  - A prompter window hidden from screen capture, using content protection.
  - AI where users bring their own key for Claude, OpenAI, Gemini, Mistral and others. This matches the local-plus-online approach.
  - Native Windows capture of the screen and the webcam as separate files, for build step 4.
- **It's also a signal about competitors.** It already has a basic teleprompter in its Notes window, with speed, font size and mirroring. Desktop recorders are adding prompters, so the AI coaching layer is what sets this app apart.

## Market check (Sept 2026)

- **Teleprompter apps** each cover one part:
  - Teleprompter.com has cue tags like [pause] that users type by hand.
  - PromptSmart scrolls along with the speaker's voice.
  - BIGVU writes scripts with AI and corrects eye contact.
  - Source: [BIGVU comparison](https://bigvu.tv/blog/best-teleprompter-apps-481af/).
- **Speech coaches** such as [Orai](https://orai.com/blog/best-ai-speech-coach-apps/) and [Poised](https://poised.com/) analyze how someone spoke, but they aren't tied to a script being read.
- **The gap:** I found no app that marks up delivery on the script, prompts with those marks, and then checks the recording against them.

## Still open

- **Cloud model:** which one to use for markup, and how much the free tier includes.
- **Stressed words:** how reliably emphasis can be detected from volume and pitch, especially across three languages. This needs a prototype.
- **App name.**

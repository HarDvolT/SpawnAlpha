# Teleprompter Recorder: Product Brief

Draft · 30 Sep 2026 · Repo: [HarDvolT/SpawnAlpha](https://github.com/HarDvolT/SpawnAlpha)

## The idea

This is a teleprompter that coaches your delivery. Most teleprompters only show your words. This one uses AI to direct how you say them: where to pause, which words to stress, and when to slow down or lift the energy. It shows those cues while you record, then checks afterwards how well you delivered them.

**Pitch:** the AI directs, you perform, the AI checks.

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

## Decisions so far

- **Platforms:** Windows on desktop plus Android and iOS. The proposed stack is **Flutter**, which covers all three from one codebase.
- **Languages:** English, French and Arabic.
  - Scripts, markup and speech analysis must work in all three.
  - Arabic needs right-to-left layout in the prompter and the editor.
- **AI runs both locally and online.**
  - Transcription can run on the device with whisper.cpp, for offline use and privacy.
  - Script markup and review can also use a cloud model, for higher quality.
- **Business model:** a free tier plus a subscription. The subscription is the natural home for the online AI, because it costs money per use.
- **Name:** to be decided later. The repo is called SpawnAlpha for now.

## Build order

1. **Script markup and coached prompter.** This includes timed or manual scroll and camera recording on mobile and Windows. It delivers the core value on its own.
2. **Delivery review.** Transcription and analysis run on the recorded file after the fact, which is simpler than doing it in real time.
3. **Voice-following scroll.** This needs real-time speech recognition on the device, so it's the hardest step.
4. **Screen and webcam recording on desktop, plus section retakes** that are stitched back into the full recording.

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

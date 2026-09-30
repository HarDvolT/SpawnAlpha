# Recording

SpawnAlpha records three ways, and the prompter works in all of them. The rule that shapes every mode: **the prompter is visible to the speaker and never to the viewer.**

## The three modes

| Mode | Records | Platforms | Output |
|---|---|---|---|
| **Camera** | a camera and the microphone | Windows, Android, iOS | one video |
| **Screen** | a display or one window, the microphone, optionally system audio | Windows first; Android; iOS later | one screen video |
| **Screen + camera** | the screen and a camera at the same time | Windows first; Android later | a screen video and a camera video, kept separate so the layout can change after recording |

Pick the mode with the mode switcher on the record screen (icons `videocam_rounded`, `screen_share_rounded`, `picture_in_picture_alt_rounded`). The app remembers the last mode per device.

## One flow for every mode

| State | What the speaker sees | Prompter | Tally |
|---|---|---|---|
| **Set up** | Mode, source (display or window), camera, microphone, system audio, prompter placement; a live preview | First lines on the reading line, not moving | off |
| **Countdown** | 3, 2, 1 in the centre of what is being recorded (see Motion) | Still; Space cancels | off, then on at "go" |
| **Recording** | The HUD or bottom bar: `rec` dot and running `timecode`, microphone meter | Scrolls: Timed from the first word, or Voice | `rec` dot, steady |
| **Paused** | The dot becomes a hollow ring; the timer stops | Holds where it is | ring |
| **End of script** | "End of script" on the reading line | Stopped | Camera mode stops the take 1.5s after the last word; screen modes keep recording until Stop, because demos often continue |
| **Saving** | "Saving take…" with the duration | Hidden | off |
| **Director's Cut** | The finish screen: the edit plays out, the list of changes, one question if the edit is unsure, export (see Director's Cut) | Back to the start | off |

Stopping never loses a take: files are written as fragmented MP4, so a crash keeps what was captured.

## Where the prompter goes

### Camera, on a phone
- The front-camera preview fills the screen. The prompter is a **glass** panel (`stage-glass`, `radius-lg`) right under the lens, three lines of `stage-s`, with its reading line on the first line. The glass blurs the feed behind the text but never hides you, so framing stays visible.
- Glass pills for the timecode and the mode sit under the panel. The take number, record button and camera flip sit along the bottom. Nothing else floats over the preview.
- The countdown and the tally appear over the preview, never over the prompter panel.

### Camera, on a desktop
- A webcam usually sits on top of the monitor, so the prompter docks **top-centre, directly under the webcam**, as a narrow column (`column-max`, `stage-m`).
- The camera preview shrinks to a thumbnail in a bottom corner once the take starts: a large self-view pulls the gaze away from the lens. Before the take, the preview can be full size for framing.
- With a teleprompter rig, choose "Glass" placement: the stage fills a chosen display, mirrored, in `stage-l`.

### Screen, on a desktop
- The prompter becomes a **Prompter window**: frameless, always on top, and **excluded from capture**, so it never appears in the recording. By default it docks top-centre under the webcam, 3 to 5 lines tall, `stage-s` on `stage-scrim`.
- It carries a small "Hidden from recording" label (eye-slash icon) so the speaker can trust it.
- Drag it anywhere; it snaps to top-centre and to the display edges. Resize from its bottom edge. Opacity runs from 60% to 100%, so the speaker can see the screen through it.
- **Lock** makes it click-through, so the speaker can work in the app underneath. While locked, the global shortcuts drive it: Ctrl+Shift+Space play or pause, Ctrl+Shift+↑/↓ speed, Ctrl+Shift+←/→ sentence.
- The **Recording HUD** is a floating glass pill (`stage-glass`, `radius-lg`, `shadow-float`) at the bottom centre of the recorded display. It is also excluded from capture, and click-through except for its buttons. It holds:
  - tally and timer;
  - Pause and Stop;
  - the microphone meter;
  - show or hide prompter, Companion, and Lock.
- During the countdown only, the recorded area gets a 2px `rec` frame so the speaker sees exactly what will be captured. The frame is excluded from capture and fades out at "go".
- Source picker: displays and windows as live thumbnails with their names. A window keeps being recorded if it moves.

### The cursor companion (Screen only)
- **What it is:** a third placement for the Prompter window, set with **Companion** in the HUD. The prompter becomes a small glass card that rides beside the cursor, so a demo can be read without looking away from the work.
- **Where it sits:**
  - It trails the pointer on `spring-follow`, on the side the pointer is not heading to.
  - It flips away from edges.
  - It docks under the lens after 2s of stillness.
- **Visibility:** it is hidden from capture like every prompter window, and the "The recording sees" preview proves it.
- **Camera on:** it is **disabled while a camera is recording**. It stays docked under the lens with the note: "Following is off while the camera is on." A speaker whose eyes chase the mouse looks shifty on camera. This is a deliberate limit, not a missing feature.

### Screen + camera, on a desktop
- Everything in Screen mode, plus a **camera bubble** (`radius-full`) the speaker can see. The bubble is a preview only and is excluded from capture, because the camera is recorded to its own file.
- Park the bubble beside the prompter, under the webcam, so both sit near the lens. In the Cut, a bubble that would cover the cursor or a zoom target slides to the nearest free corner on `spring-smooth`.
- After recording, pick a layout: **Bubble** (a circle in any corner, a quarter of the frame's height), **Side by side** (screen 70%, camera 30%), **Camera only**, **Screen only**. With section retakes (step 4), the layout can change per section.

### Screen, on a phone (later)
- **Android** records with MediaProjection. The prompter floats over other apps (it needs the "Display over other apps" permission). Android records overlays, so prefer single-app sharing (Android 14 and later), which leaves the prompter out. For full-screen recording, warn before starting that the prompter will be recorded, and offer to shrink it to a small pill. Verify on real devices.
- **iOS** doesn't let apps float over other apps, and a ReplayKit broadcast records the whole screen. The answer there is the Companion prompter.

### Companion prompter (later)
A second device (phone or tablet) shows the stage, synced over the local network, while the first device records: the answer for iOS screen recording and for camera rigs. It follows the same timeline, and either device can pause.

## Every surface at a glance

| Surface | Camera (phone) | Camera (desktop) | Screen | Screen + camera |
|---|---|---|---|---|
| Prompter | panel over the top 45% | docked under the webcam | Prompter window, hidden from capture | Prompter window, hidden from capture |
| Self-view | full screen | thumbnail once recording | none | camera bubble, hidden from capture |
| Controls | bottom bar | bottom bar | HUD pill, hidden from capture | HUD pill, hidden from capture |
| Countdown | over the preview | over the preview | centre of the recorded display, hidden from capture | same |

## Making things "hidden from capture"

- **Windows:** `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` (Windows 10 2004 and later) on the prompter window, the HUD, the countdown overlay and the camera bubble. Windows Graphics Capture honours it. This is what Electron's `setContentProtection` does in OpenScreen.
- **macOS** (not a target): OpenScreen found that on macOS 26 a content-protected window is never drawn at all, so the capture layer must exclude these windows by their IDs instead.
- **Android:** only single-app sharing keeps an overlay out. `FLAG_SECURE` blacks a window out instead of hiding it, so don't use it for the prompter.

## Telemetry for the Cut

The Director's Cut edits screen recordings from what happened, not from pixels. While a screen take runs, the recorder logs the following next to the video:
- **Cursor:** position at 60 Hz, and the cursor shape (arrow, text beam, hand).
- **Clicks:** time, position and button.
- **Keys:** times of key presses and modifier chords, such as Ctrl+S. Letters are **never** logged: typing is recorded as "a burst of 16 keys", not the text. Shortcut badges show only modifier chords.
- **Windows:** the focused window's rectangle and title, so zooms frame the right thing and the backdrop can crop to one app.

Telemetry stays with the take on the device. It is what makes zooms land **before** a click (`zoom-lead`) and the cursor smooth without guessing.

## Effects at set-up

The set-up screen for Screen and Screen + camera shows the Cut's effects as chips, all on by default: **Auto-zoom, Smooth cursor, Motion blur, Click ripples, Keystrokes, Backdrop**. They change nothing while recording. They are defaults for the Cut, and can be switched after the take too.

## Audio

- The microphone meter is always visible while recording: a 3px bar in `stage-chrome-text` that turns `warning` near clipping.
- System audio is a toggle in the screen modes (loopback on Windows), off by default.

## Takes

A take records its files, duration, mode, source and the version of the script that was on the prompter, so the review (step 2) compares against the cues the speaker actually saw.

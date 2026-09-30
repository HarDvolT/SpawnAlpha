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
| **Take saved** | A sheet: duration, mode, Record again, Review delivery (step 2), Show in folder | Back to the start | off |

Stopping never loses a take: files are written as fragmented MP4, so a crash keeps what was captured.

## Where the prompter goes

### Camera, on a phone
- The front-camera preview fills the screen. The prompter is a `stage-scrim` panel over the top 45%, the part nearest the lens, in `stage-s`, with its reading line at 35% of the panel.
- The mode switcher, camera flip, record button and prompter controls sit in a bar along the bottom. Nothing else floats over the preview.
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
- The **Recording HUD** is a floating `stage-chrome` pill (`radius-lg`, `shadow-float`) at the bottom centre of the recorded display, also excluded from capture and click-through except for its buttons: tally and timer, Pause, Stop, microphone meter, show or hide prompter, Lock.
- During the countdown only, the recorded area gets a 2px `rec` frame so the speaker sees exactly what will be captured. The frame is excluded from capture and fades out at "go".
- Source picker: displays and windows as live thumbnails with their names. A window keeps being recorded if it moves.

### Screen + camera, on a desktop
- Everything in Screen mode, plus a **camera bubble** (`radius-full`) the speaker can see. The bubble is a preview only and is excluded from capture, because the camera is recorded to its own file.
- Park the bubble beside the prompter, under the webcam, so both sit near the lens.
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

## Audio

- The microphone meter is always visible while recording: a 3px bar in `stage-chrome-text` that turns `warning` near clipping.
- System audio is a toggle in the screen modes (loopback on Windows), off by default.

## Takes

A take records its files, duration, mode, source and the version of the script that was on the prompter, so the review (step 2) compares against the cues the speaker actually saw.

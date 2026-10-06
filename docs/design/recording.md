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
| **Set up** | Mode, source (display or window), camera, microphone with a sound check, system audio, prompter placement, guide and pace; a live preview (see Setting up a take) | First lines on the reading line, not moving | off |
| **Countdown** | 3, 2, 1 in the centre of what is being recorded (see Motion) | Still; Space cancels | off, then on at "go" |
| **Recording** | The HUD or bottom bar: `rec` dot and running `timecode`, microphone meter | Scrolls: Timed from the first word, or Voice | `rec` dot, steady |
| **Paused** | The dot becomes a hollow ring; the timer stops | Holds where it is | ring |
| **End of script** | "End of script" on the reading line | Stopped | Camera mode stops the take 1.5s after the last word; screen modes keep recording until Stop, because demos often continue |
| **Saving** | "Saving take…" with the duration | Hidden | off |
| **Director's Cut** | The finish screen: the edit plays out, the list of changes, one question if the edit is unsure, export (see Director's Cut) | Back to the start | off |

Stopping never loses a take: files are written as fragmented MP4, so a crash keeps what was captured.

## Setting up a take

Set-up is one screen, on the stage: the live preview on the leading side, and four decisions in a rail on the other, top to bottom (see RecordSetup). Everything on it is chosen before the countdown, and nothing on it is hidden in a menu.

1. **What to record:** Camera, Screen or Both.
2. **Camera:** the device and its format ("1080p · 30 fps"), with its state (ON, or what is wrong).
3. **Microphone:**
   - **Every microphone is listed, each with its own live meter**, the Windows default first and labelled. PCs often have several (a headset, a laptop array, virtual devices from other apps), and the right one is the one that moves when you talk.
   - A **sound check**: "Say a line from your script", with a big meter. Then either "We hear you" (`stage-ok`), "Very quiet" or "Nothing heard from <microphone>. Pick another" (`stage-warn`). Nothing is recorded or saved.
   - **Blocked by the system:** Windows has no permission prompt for desktop apps; access is a switch in Settings. When no microphone gives a signal, say so plainly ("Windows is blocking the microphone"), name the two switches (Microphone access, Let desktop apps access your microphone), and offer **Open privacy settings** and **Check again**. On phones, the system prompt appears on the first visit to this screen, and a refusal shows the same panel with a link to the app's settings.
4. **Prompter:** where it sits (Under the lens, Floating, Off), the guide (Dot, Underline, Spotlight) and the pace (My voice, Timed). The preview shows the choice immediately, on the real script.

The **record button** sits at the bottom of the rail with one line under it that says what will happen ("3, 2, 1, then the script follows your voice") or what is missing.
- **Never record silence without saying so.** With no working microphone the button is off and the line reads "No microphone. Fix access above, or record without sound". Recording without sound is a deliberate choice.
- After every take, the take's audio is checked (the file has an audio track, and it was not silent), and the result shows in the saved toast: "Sound OK", or a warning with the fix.

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

### Source selection: first Windows slice

The first slice exposes **Choose screen** in the desktop setup rail. It opens a Stage
page with two lists, **Displays** and **Windows**, their names and pixel dimensions.
The main display is labelled. Choose a row, then **Use this source**; **Refresh** checks
the current list. Selection is explicit, keyboard accessible and checked again on
confirmation. Closed or minimized windows cannot be selected; restore them and Refresh.
Source names stay on the device and are neither saved nor logged. SpawnAlpha's own
windows are excluded from this list.

This slice reads metadata only. Camera remains the only enabled recording mode until
live thumbnails, screen capture and the excluded floating prompter are verified. The
selected source is held for this setup session; it does not start a recording.

### Live source preview: second Windows slice

After choosing a source, **Preview screen** opens an always-dark Stage page. It shows
the chosen name, the live source fitted inside the page with its aspect ratio preserved,
and **Live preview only · nothing saved**. Capture begins only on this page and ends when
it closes. No microphone or camera is added to the screen preview. Windows keeps its
capture border visible. A closed source shows **This source closed. Choose another.**;
an unavailable or minimized source offers **Try again** without leaving a frozen image
labelled live. Resizing a window updates its aspect ratio. Source switching uses the
picker again. The setup camera can resume when returning from preview.
If the first frame has not arrived after five countdown beats, stop the attempt and
offer the same retry; never leave the speaker waiting indefinitely.

This is a preview, not a take. Camera remains the only recording mode until the floating
prompter is excluded and the audio/video recording pipeline is verified. Live thumbnails
for every picker row will use this same capture backend in a later slice.

### Floating prompter: third Windows slice

The live-preview page offers **Show floating prompter**. This opens the real coached
script in a separate, frameless, always-on-top Stage window. Its header says **Hidden
from recording** only after Windows confirms capture exclusion; if exclusion cannot
be set, keep the window hidden and show an error in the preview. Dock it at the top
centre of the app's display initially. Drag the header to move it, use the bottom-right
resize handle to resize, or **Dock** to return it under the lens. Movement snaps to
nearby work-area edges and top centre using `space-6` as the snap distance.
Initial and minimum sizes use the `floating-*` prompter tokens. An opacity slider
ranges from `floating-min-opacity` to full opacity.

This trial runs in Timed pace and does not open another microphone or save a take.
The existing guide, motion, alignment, mirror and kinetic choices are copied into it.
It offers Play/Pause, Restart and speed buttons. Global Ctrl+Shift+Space, arrows and L
control play/pause, speed, sentences and Lock. Lock is click-through and only works
when all global shortcuts are registered; Ctrl+Shift+L always unlocks. If a shortcut
is already used by another app, keep Lock off and explain why. Closing the preview
also closes the floating trial and releases its shortcuts. Recording integration,
the separate recording HUD and Companion follow in the next slices.

### Recording controls: Windows slice

The recording HUD is a separate frameless, topmost tool window. Windows capture
exclusion is verified before its first visible frame. Its countdown uses the
existing spring-driven numeral in a `countdown-window-size` square at the centre
of the selected display/window; at go, it becomes the `hud-width` × `hud-height`
pill at the bottom of that source's display, inset by `space-6`. It offers a live
timer and tally, microphone name/meter, Pause/Resume, Stop, and reader visibility/
Lock controls. Waiting during Pause is removed from the saved picture and sound.
Closing the HUD asks to stop; the recording owner finalizes before destroying it.
The setup/main window is excluded for the same session, and restored afterward.
If any required exclusion fails, recording stays off and explains why. The source
capture border stays enabled. Companion and the excluded camera bubble follow.

### Normal Windows Screen mode

Screen is enabled in the Home mode choice and recording setup, and remembered per
device. The chosen display/window has an inline live preview; source changes and
the detailed preview page release and reopen that preview cleanly. Screen needs no
camera. Its setup and recording windows use explicit Stage control colours so choices
remain legible in either Studio theme. Language metadata uses the reading face to
include French accents and Arabic glyphs.

At Record, stop preview and unchosen mic meters, protect setup/HUD/reader, count down,
then capture to a flushed local manifest and fragmented MP4. Voice follows the recording
microphone's level at `recording-poll`; Pause holds the reader and saved picture/sound,
and Resume continues at that word. Reader hide/show preserves its position. Reaching
the last word never stops a Screen take. Stop saves it, then removes capture protection.
Partial source/mic stops keep readable video and explain why. Saved take cards show
Screen and, after crash recovery, Recovered. A missing mic requires Record without sound
and uses Timed pace. System audio remains off until loopback is implemented.

### Normal Windows Both mode

Both is enabled in Home and setup and remembered. Choose the screen, camera and microphone;
the camera has a circular framing preview beside the source preview. At Record the setup
camera is released, all required windows are protected, and the native recorder opens the
exact chosen camera after countdown. Its excluded bubble uses this same feed, beginning
only when both savers are ready. Files share one pause clock; the camera is saved separately
without duplicate microphone audio. Stop finalizes and verifies both, then removes capture
protection. If camera output cannot be read, the useful screen take is saved with a clear
warning and the camera data stays local. Device IDs are held in memory; manifests keep the
chosen display name and safe local file names. Director's Cut layout choices remain later.

### The cursor companion
- **What it is:** a third placement for the Prompter window, set with **Companion** in the HUD. The prompter becomes a small glass card that rides beside the cursor, so a demo can be read without looking away from the work.
- **Where it sits:**
  - It trails the pointer on `spring-follow`, on the side the pointer is not heading to.
  - It flips away from edges.
  - It docks under the lens after 2s of stillness.
- **Visibility:** it is hidden from capture like every prompter window, and the "The recording sees" preview proves it.
- **Camera on:** with a camera recording, it is **docked under the lens by default**, because a speaker whose eyes chase the mouse looks shifty on camera.
  - The card offers **Follow anyway**. The first time, a warning explains the eye-contact cost, with Keep docked as the default button and Follow anyway as the other.
  - The choice is remembered.
  - While following on camera, the card carries an "Eyes to the lens" reminder.

### Screen + camera, on a desktop
- Everything in Screen mode, plus a **camera bubble** (`radius-full`) the speaker can see. The bubble is a preview only and is excluded from capture, because the camera is recorded to its own file.
- Park the bubble beside the prompter, under the webcam, so both sit near the lens. In the Cut, a bubble that would cover the cursor or a zoom target slides to the nearest free corner on `spring-smooth`.
- The Windows bubble uses `camera-bubble-size`, with circular native and Flutter bounds.
  It verifies exclusion before becoming visible, initially says **Camera starts at go**,
  then uses the recording camera's latest owned frame without opening a second camera.
  A glass strip says **Hidden from recording** and shows the chosen camera's display name.
  Drag the strip to move it; **Hide camera preview** hides only this self-view. The camera
  file keeps recording. Closing/finalizing the take destroys the bubble. Pausing holds
  saved pictures while the self-view stays live for framing. Failed exclusion prevents
  a Both take from starting. File paths and opaque camera IDs never reach this child.
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

- The microphone meter is always visible while recording: a 3px bar in `stage-chrome-text` that turns `stage-warn` near clipping. The microphone's name sits beside it, and a tap opens the list.
- The take records from the microphone chosen at set-up, never from "the first device". If it disappears mid-take, the take stops safely (the fragmented MP4 keeps what was captured) and says why.
- System audio is a toggle in the screen modes (loopback on Windows), off by default.

## Takes

A take records its files, duration, mode, source and the version of the script that was on the prompter, so the review (step 2) compares against the cues the speaker actually saw.

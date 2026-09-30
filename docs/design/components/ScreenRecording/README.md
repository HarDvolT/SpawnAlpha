# ScreenRecording

How the prompter, HUD and camera bubble sit on a desktop while the screen is recorded, and what the video actually captures.

- **Use** as the reference layout for Screen and Screen + camera modes on Windows. The Recording section of this system is the full specification.
- **Prompter window:** docked top-centre under the webcam, 3 to 5 lines in `stage-s` on `stage-scrim`, `radius-md`, `shadow-float`. It carries the "Hidden from recording" tag, a drag grip and the Lock toggle. Draggable, snaps to top-centre and the display edges, opacity 60% to 100%.
- **Camera bubble** (Screen + camera only): `radius-full`, beside the prompter under the webcam, for the speaker's own view. The camera is recorded to its own file, so the bubble is hidden from capture.
- **HUD:** see RecordingHud, at the bottom centre.
- **Hidden from capture:** the prompter window, HUD, countdown overlay, recording frame and bubble all use `WDA_EXCLUDEFROMCAPTURE`. The video contains only the screen.
- **Consumer provides** the display or window being recorded, the webcam's position (top-centre unless the user moves the prompter), and the prompter controller.
- **Don't** put the prompter where the viewer's attention goes (the middle of the screen), and don't dim the recorded screen.

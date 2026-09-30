# CursorCompanion

The prompter that follows the mouse, for screen recordings: a small glass card that rides beside the cursor so a demo can be read without looking away from the work.

- **Use** in Screen and Screen + camera modes on desktop, when Companion is on in the HUD.
  - With a camera recording, it starts docked under the lens and offers **Follow anyway**.
  - The first use shows a one-time warning, with Keep docked as the default choice.
  - While following on camera, the header shows an "Eyes to the lens" reminder.
- **Consumer provides** the prompter controller (the same timeline as the Prompter), the pointer position and velocity, the display bounds, and whether a camera is recording.
- **Card:** a `.sa-glass` card, 300px wide, `radius-md`.
  - A header shows the tally, the state (FOLLOWING, DOCKED, UNDER THE LENS) and a hold ring.
  - Below are two lines of script in the Reading face. Spoken words fade.
- **Placement:**
  - It trails the pointer on `spring-follow`, 26px to the side and 22px below.
  - It sits on the side the pointer is not heading to, and flips away from edges and upward near the bottom.
- **Docking:** after 2s of stillness it docks centred under the lens and widens to three lines. It re-attaches on the next move.
- **Visibility:** it is always hidden from capture (`WDA_EXCLUDEFROMCAPTURE`). The preview's "The recording sees" view shows the video without it.
- **Don't** start following on camera without the warning, because eyes that chase the cursor look shifty. **Don't** cover the pointer or the menu it just opened.

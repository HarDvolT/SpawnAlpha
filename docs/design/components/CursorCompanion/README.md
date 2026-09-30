# CursorCompanion

The prompter that follows the mouse, for screen-only recordings: a small glass card that rides beside the cursor so a demo can be read without looking away from the work.

- **Use** in Screen mode on desktop, when Companion is on in the HUD. In Screen + camera mode it is disabled: it stays docked under the lens and says why ("Following is off while the camera is on").
- **Consumer provides** the prompter controller (the same timeline as the Prompter), the pointer position and velocity, the display bounds, and whether a camera is recording.
- **Card:** a `.sa-glass` card, 300px wide, `radius-md`.
  - A header shows the tally, the state (FOLLOWING, DOCKED, UNDER THE LENS) and a hold ring.
  - Below are two lines of script in the Reading face. Spoken words fade.
- **Placement:**
  - It trails the pointer on `spring-follow`, 26px to the side and 22px below.
  - It sits on the side the pointer is not heading to, and flips away from edges and upward near the bottom.
- **Docking:** after 2s of stillness it docks centred under the lens and widens to three lines. It re-attaches on the next move.
- **Visibility:** it is always hidden from capture (`WDA_EXCLUDEFROMCAPTURE`). The preview's "The recording sees" view shows the video without it.
- **Don't** follow the mouse while a camera is recording, because eyes that chase the cursor look shifty. **Don't** cover the pointer or the menu it just opened.

# CameraLayouts

The four ways to combine a Screen + camera take, chosen after recording: Bubble, Side by side, Camera only and Screen only.

- **Use** on the take screen of a Screen + camera recording, and per section once section retakes exist (build step 4).
- **Consumer provides** the screen and camera files, the current layout and a change handler. The bubble's corner is a second choice (top or bottom, left or right; the default is bottom right, or bottom left for Arabic scripts).
- Bubble: a circle a quarter of the frame's height with a 2px `surface` ring. Side by side: screen 70%, camera 30%, no gap. Camera only fills the frame. Screen only hides the camera.
- Thumbnails are schematic (`surface-sunk`, `line`, `ink-3`) until real frames are available; then show the take's first frame.
- **Don't** bake the layout into the recording: both files stay separate, and the layout is applied on export.

# RecordSetup

Setting up a take on a desktop: the live preview, and four decisions in a rail. Then 3, 2, 1.

- **Use** before every recording on Windows (and macOS later). Phones use RecordScreen, which puts the same choices in a sheet.
- **Consumer provides** the script, the cameras and microphones with live levels, the privacy state, and the handlers.
- **The view** (leading side) shows what will be recorded: the camera, or the screen with the camera bubble for Both. A pill marks where the webcam is ("Webcam · look here"), and the prompter's glass panel docks right under it, showing the real script with the chosen guide.
- **The rail** (trailing side), on `stage-chrome`, top to bottom:
  1. **What to record:** Camera, Screen, Both. The screen modes move the prompter into its floating window, tagged "Hidden from the recording".
  2. **Camera:** device and format, with its state.
  3. **Microphone:** every microphone with its own live meter, the Windows default first and labelled; a sound check ("We hear you", "Very quiet", "Nothing heard. Pick another"); and, when the system blocks access, a warning panel with **Open privacy settings** and **Check again**.
  4. **Prompter:** Where (Under lens, Floating, Off), Guide (Dot, Underline, Spotlight), Pace (My voice, Timed).
- **Go:** the record button with one line saying what will happen or what is missing. With no working microphone it is off, and "record without sound" is an explicit link.
- **Recording:** the countdown lands in the middle of the view, its ring collapses into the tally, the rail dims, and the guide leads through the script. **Stop** sits at the bottom of the view.
- **After the take:** a glass toast with the take number, the duration and the sound check ("Sound OK", or the problem).
- States: every step shows its state in `stage-ok` or `stage-warn`, always with an icon and words.
- **Don't** record silently when no microphone works, pick "the first microphone" for the user, or hide the device choice in a menu.

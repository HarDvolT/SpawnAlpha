# Take review

After a new recording saves, Camera/Screen/Both open this review directly,
carrying any sound/camera/activity warning as a persistent reading-voice notice.
The recorder releases live previews and microphone meters while reviewing.
**Record another** returns to setup after processing ends or is cancelled.

**Make a cut after recording** starts enabled in Settings. It checks only the
installed offline model, then finds actual words and saves a reversible cut.
Automatic processing never downloads anything. If speech is not set up, review
explains the 148 MB public model and offers **Find spoken words** for explicit
setup. Saved words/cuts are reused when reopening; review does not repeat a job.
Progress/cancel spans the installed-model check, speech and cut saving. Failure
keeps the original and any successfully saved words for retry.
Setup and active processing sit above the video preview so their progress and
cancel action are visible without scrolling. Record another aligns to the left.

The take opens in the themed Studio with a paused local video player. Play/pause,
seek and mute controls sit below the picture and support keyboard focus and
accessible labels. The preview uses the Stage dark background inside the Studio,
with the review width/height tokens; portrait previews keep their aspect ratio.
It never starts sound automatically. Leaving the view closes the player;
backgrounding the app pauses it. Failed playback has a generic retry message and
the file remains available. Playback uses the Windows platform first.
Its original stays on the device and is
available through **Show original file**. Use the reading voice for the title
and transcript, signal for the word count, and the existing Studio spacing.

**Find spoken words** starts local processing. First use says that it downloads
a 148 MB public speech model from Hugging Face; recordings and scripts are never
uploaded. Download, verification, recognition and saving have progress states.
Cancel keeps the original. Offline speech is Windows first and supports takes
up to 24 hours; other platforms show that limit plainly.

The transcript keeps actual speech in English, French or Arabic. Arabic has its
own right-to-left Directionality. Frozen Script takes may show words missed or
changed; Notes takes are free speech and never receive script adherence scores.
Computer-sound-only takes never receive delivery scores either. Older takes
without a snapshot use actual speech, with an explanation.

Word times are estimates. Invalid or conflicting times stop processing with a
plain retry message; never shift, drop or invent words to make a cut possible.
No speech is an explicit empty result. **Copy transcript** is an explicit local
clipboard action. **Save SRT + VTT captions** writes both local subtitle files;
it does not publish or overwrite the original video.

This surface now includes the first **Your cut** panel: original/cut duration,
the measured quiet-gap changes, an individual switch and **Restore all gaps**.
Saved plans and cut-caption clocks preserve all actual words. Screen context
and missing/uncertain script alignment keep the original. Video preview,
individual word corrections and coaching will extend it, using the same frozen
take and actual speech.

**Save your video** makes a separate local MP4 from the saved cut (or the whole
take when no cut exists). The first Windows renderer fits the complete picture
inside 16:9 1080p/4K, 9:16 or 4:5; unused space stays black. It does not yet
reframe faces or screen targets. Both takes can include the separate camera in
the bottom-right corner, fitted inside 28% of each output dimension with a 4%
short-edge margin. These proportions are `video-export` tokens. A switch can
omit the camera. The original sound keeps its source clock through each cut.

Progress has **Cancel export** until saving starts. Saving verifies decoded
dimensions and duration before attaching history. Each saved video shows its
date, format and duration, with **Watch saved video** and **Show saved files**.
Earlier exports remain available after restoring a gap or processing speech
again. The player labels saved videos and provides **Watch original take**.
Actual SRT/VTT captions and the portable cut plan save beside each video.
Burned-in captions, sound polish and smooth cut transitions are later slices.

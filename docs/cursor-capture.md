# Cursor-free recording foundation

This is the recording foundation for a later reversible **Smooth cursor**
export choice. Cursor replacement is not connected yet. Existing exports and
original recordings continue to show the recorded Windows pointer.

## Consent and files

**Activity for automatic edits** starts off on each recording setup visit.
Its caption explains local mouse/click/typing timing, that typed text is never
saved, and that an extra video for mouse effects uses more disk space.
Camera-only recordings do not create this extra picture.

With the choice enabled, `ScreenTakeStore` reserves a fresh
`<id>-cursor-free.mp4` beside the original, camera and activity files. The
pending manifest names it before capture. Two Windows Graphics Capture
sessions use the same source: the original includes the Windows pointer and
the optional second session excludes it. Both settings are checked. Each
callback copies the texture before releasing its reusable capture frame;
two bounded pools and the latest snapshots replace a growing frame queue.
The companion is silent. Original sound remains in the original video.

The required screen/camera encoders start before the optional encoder.
Unsupported cursor exclusion, a busy encoder, an existing companion file or
an optional-session error leaves ordinary recording available. A partial
companion is preserved locally but never advertised as usable. After saving,
the app explains when mouse smoothing is unavailable for that take.

## Eligibility and recovery

A filename alone never proves cursor exclusion. Normal finish requires all
of the following before attaching `Take.cursorFreePath`:

- Native capture reports successful companion finalization and equal,
  nonzero original/companion frame counts.
- The original probe matches the native dimensions and video endpoint. One
  30,000Hz MP4 track tick allows at most 34 microseconds of rounding.
- The companion is a regular local file, decodes, contains no audio, and
  matches the original dimensions and probed duration within two microseconds.

The saved manifest records `cursorFreeReadable`, version 1, the explicit
`wgcCursorExcluded` method, verified frame count and duration. Take JSON preserves
the optional path through word, cut and export revisions. Older takes lack
it and retain their baked pointer.

Pending-manifest recovery never promotes a companion: a crash cannot prove
finalization, even when some fragments decode. It preserves the original and
any companion bytes. A future export loader must recheck local manifest,
source, file and clock provenance before selecting the clean picture, and
must read sound from the original. That loader and the cursor track/renderer
are the next slice.

## Continuous picture and sound clocks

The shared QPC origin starts after encoder/activity setup. Picture starts at
zero and uses a continuous 30fps cadence. Brief stalls repeat the latest
snapshot while catching up. The optional picture stops if video falls more
than half a second behind; a required encoder more than one second behind
stops with an encoder warning and a readable partial original. Pressure is
checked before draining sound, so stopping cannot append the stalled
interval's sound after the useful picture. Pauses remove time from every
recorded stream and from activity.

`GpuVideoWriter` rejects a late first picture or gaps/overlaps in later
timestamps. Fragmented recordings require GOP size one: every picture is
independently decodable, so an AAC-triggered fragment boundary cannot put a
later keyframe's time on earlier pictures. Installed encoder support must be
available before recording starts. The target bitrate remains capped; quality
and disk-use trials on real material are still deferred.

The minimum fragment span is `(10,000,000 / fps) * (fps - 1)` in 100ns ticks
at 30fps, keeping recoverable fragments near one second. Audio can move a
boundary. Video times/endpoints therefore map to the nearest `fps * 1000`
MP4 clock tick, represented with an upward-rounded 100ns value so the sink
cannot truncate the index to the preceding tick. This prevents accumulated
rounding across mixed-sound fragments. Finalized exports keep their existing
encoder policy and exact last-frame duration.
Do not use a one-coded-sequence fragment limit: a
generated stereo fixture exposed truncated AAC with that experiment.

`ProbeRecording` decodes the first picture to verify readability/dimensions,
then scans encoded video sample endpoints with bounded memory. It anchors
encoder preroll to the first decoded frame. Movie-header duration can omit
a final short fragment or include audio padding, so it is not the take's
picture clock. Intentional final holds and shorter last export frames retain
their full sample durations.

## Checks and limits

The explicit non-shipping native checks use owned color windows, generated
camera pictures and generated sound only. They cover independent cursor
flags in both session startup orders, paired decoded frame clocks/pixels,
resize, pauses, long capture, encoder pressure, pre-existing-file protection,
AAC, interruption recovery and exact held/short-tail durations. The protected
Flutter recording helper checks the real save/reopen path using an activity
fixture handshake, without collecting owner input. Dart tests cover EN/FR/AR
take persistence, eligibility, missing/partial/substituted files and fallback.

Every native check embeds the same Windows compatibility/DPI manifest as
the app. Without it, Media Foundation selects an older MP4 behavior that
hid the fragment timing defect in console checks. Clock cases also cover
stops just beyond fragment boundaries, every-frame clean points, mono 48kHz
and stereo 44.1kHz four/eight-second fragment clocks. Golden captures explicitly repaint
without advancing time, avoiding missing retained text in Windows PNGs.

No dependency, codec, model, network upload or new input collection is added.
Real hardware and comfort trials remain deferred by the owner. Smooth cursor
is still unfinished until its verified loader, frozen track, rendering and
later on/off choice are implemented and tested.

## Primary API references

- [Independent session cursor exclusion](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturesession.iscursorcaptureenabled?view=winrt-26100).
- [Capture sessions and reusable frames](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture).
- [Minimum fragmented MP4 duration](https://learn.microsoft.com/en-us/windows/win32/medfound/mf-mpeg4sink-min-fragment-duration).
- [Installed H.264 encoder properties](https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-encoder).

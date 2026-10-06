# Windows render-core spike (2026-10-06)

The Windows candidate is the recorder's existing Media Foundation H.264/AAC encoder
plus D3D11 decoding/compositing. The generated-media spike succeeds on the owner's PC
in Debug and Release. No new package, bundled codec, Rust runtime or copied code was added.
This is a risk check for build step 2; the Director's Cut is not yet available in the app.

## Evidence

`app/windows/runner/tests/render_core_check.cpp`, the explicit `render_core_check` CMake
target, generates a four-second 640 x 360 source with a different colour/tone per second.
It opens two independent GPU-backed NV12 readers (hardware transforms enabled), retains decoder samples while using
their texture-array slices, then composites a cropped/zoomed main track and an inset.
It keeps [1s, 2s) and [3s, 4s), starting output video and audio at zero with a continuous join.
The result decodes to exactly 60 ordered frames with the expected crop/inset pixels;
440 Hz then 880 Hz sound survives, while the omitted 220/660 Hz spans do not.

Release rendered the two-second cut in **0.44 seconds** here (Debug: 0.48 seconds).
That includes opening readers, decoding source sound, GPU composition and encoding;
it excludes fixture generation and the final verification decode. It does not predict
1080p/4K speed, masks, blur or captions. The fixture bounds PCM memory to five seconds;
a production exporter must stream bounded PCM packets.

Two useful failures were fixed: selecting the frame containing a source time prevents
reading past the final frame after MP4 rounding, and all readers/managers/GPU objects
must be released before Media Foundation/COM shutdown. The result's presentation times
are checked within 1 ms of the intended 30 Hz cadence, with strict increasing order.

## Portable plan

`app/lib/src/model/cut_plan.dart` is a minimal immutable, versioned EDL foundation:
take ID, language, source duration and half-open source ranges in output order.
It maps output times to source times, supports retake reordering/reuse, rejects unknown
versions/languages/invalid intervals and contains no file paths, codec or platform fields.
Tests cover the native spike's exact two ranges in EN/FR/AR. Caption/cursor/zoom tracks
will extend this foundation after word alignment, rather than hiding arbitrary data in it.
The spike uses the same range semantics; it is not yet a Flutter export bridge.

## Next implementation work

Follow build step 3: on-device transcription and script-token alignment. Before the full
Cut ships, add a cancellable background exporter and preview bridge, incremental PCM,
capability/fallback checks across GPUs, arbitrary dimensions/frame rates, GPU masks,
caption shaping/fonts in EN/FR/AR, reversible cursor/zoom tracks and the designed finish UI.
WGC currently burns in the native cursor; smoothing/replacement needs a clean-source
capture/preview design so raw takes do not lose their cursor. Keep originals untouched.
The mobile backends and the final cross-platform native/FFI boundary remain open.

## Reproducing the generated check

From `app/`, build the explicit `render_core_check` target in the configured Windows
CMake build (Debug or Release), then invoke its executable with a new prefix under
`app/build/encoder-fixtures/`. It creates `<prefix>-source.mp4` and `<prefix>-cut.mp4`.
Existing source/output files cannot be overwritten. Normal builds exclude this target;
it never opens a camera, microphone, input receiver, owner recording or private desktop.

API references used for the independent implementation:
[Media Foundation D3D manager](https://learn.microsoft.com/en-us/windows/win32/medfound/mf-source-reader-d3d-manager)
provides GPU-backed decoder buffers;
[D3D11 video processing](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11videocontext-videoprocessorblt)
supports multiple input streams subject to the GPU's reported capabilities.

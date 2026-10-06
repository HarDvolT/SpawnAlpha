# Word timing: Windows runtime (2026-10-06)

Build step 3 is now available from a take's **Find spoken words** button on
Windows. The app verifies/downloads the offline model, processes the original
locally, saves actual words and frozen-script alignment, and exports SRT/VTT.
Automatic processing on stop and the full Director's Cut are the next slice.

The runtime uses DTW audio-attention boundaries, not equal distribution of a
segment across script words. The generated normal-app check passes verified
model handling, cancellation before the session reply, frozen Script/Notes,
durable results, captions and three bounded windows over a 70-second fixture
with long gaps. Speech is generated locally; no owner media/device/network is
used by the check. Source offsets survive quiet-edge trimming and seeks.

Jobs support takes up to 24 hours, with an explicit UI limit, 100,000 token
fragments and at most 30 seconds of decoded PCM per window. A CPU model context
is reused within a job. Alignment runs in an isolate; exceeding four million
cells keeps words but flags script review. Invalid/conflicting estimates need
retry/review. This is not a claim of transcription accuracy or automatic
word-boundary precision. Real language/long-recording quality trials remain.

## What passes

- `WordTranscript` stores immutable, versioned, ordered word ranges on the take
  clock, language and recognizer confidence. Invalid ranges, overlap, malformed
  Unicode, unsupported schemas and unsafe numeric values are rejected without
  including private text in exceptions.
- `transcriptFromPieces` joins UTF-8 tokenizer bytes before decoding. Arabic
  characters can span fragments. It keeps punctuation and the weakest fragment
  probability per word; it does not invent equally spaced word times. Zero-length,
  overlapping or multiword single-range estimates require retry/review.
- `alignTranscript` uses the existing EN/FR/AR word normalization. Every spoken
  word is preserved once as exact, changed or added. Punctuation-only script tokens
  are unspoken; missing words have no manufactured time. Anchored backward jumps
  retain each candidate attempt. Both sides need three exact matches (two for a
  two-word script); short stutters/false starts remain added speech. This is a
  conservative restart heuristic, not the final retake chooser. Low confidence
  still needs a review policy even when the recognized spelling matches.
- Work is capped at four million alignment cells. Run it off the UI thread and
  section long takes; exceeding the bound is explicit, never silently treated as
  a fully missed script.
- `local_transcription.cpp` decodes local WAV/AAC through Media Foundation to mono
  float PCM at 16 kHz, preserves timestamp gaps and trims negative codec preroll.
  It runs the multilingual recognizer without translation, supports script
  vocabulary, rejects remote paths/network drives/reparse points, and suppresses
  upstream logs before loading a model. No device, network request or temporary
  decoded audio file is opened by the core. The caller owns COM/MF lifetime.
- The explicit native check generated local SAPI speech, recognized WAV, encoded
  it with generated GPU frames as stereo/48 kHz AAC, decoded/recognized the saved
  MP4, checked its initial clock gap, and tested active/pre-start cancellation.
  The resulting byte fragments then passed Dart word assembly and exact script
  alignment. It prints results only. No owner's media, microphone or private text
  was used. WAV recognition took about 3.3 seconds here; this is not a quality or
  speed benchmark for long or multilingual recordings.

The Dart suite has 19 new cases covering EN/FR/AR, restarts, changed/added/missed
speech, silent/empty takes, malformed schema/timing/UTF-8 and memory bounds.
All 347 project tests pass and analysis is clean. No UI changed in this slice;
the earlier 112 screenshot cases remain the current layout evidence.

## Pinned prototype inputs and notices

The explicit `app/tool/native_word_timing` CMake project fetches
[whisper.cpp v1.9.4](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.4),
with source ZIP SHA-256:
`873e67727d51213d3a14a6700c7415900a6645b78c4e6edad9328eea90e53572`.
Only the CPU library is built, statically for the test. Examples/server/download
support and OpenMP/AVX/FMA/BMI2/SSE4.2/native tuning are off. No FFmpeg or Python
runtime is installed. The ZIP/source/build stay in ignored `app/build/asr` on E:.

The risk check uses the upstream distributor's converted multilingual base
weights, 147,951,465 bytes, from
[this pinned model revision](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1).
Its SHA-256, verified after download, is
`60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`.
This is now the implementation default, pending real language quality trials;
it is not a final accuracy decision.

The runtime/source is MIT; OpenAI states that both its Whisper code and weights
are [MIT licensed](https://github.com/openai/whisper#license). The converted model
repository also identifies MIT. Notices are retained under
`app/tool/native_word_timing/licenses/` and `app/assets/licenses/`; they are
registered in the app's licence page. No fine-tuned
or Darija-specific model is approved by this check.

## Reproduction for the next agent

From `app/`, configure `tool/native_word_timing` into `build/asr/native` with the
installed Visual Studio Community instance, then build the `word_timing_check`
Release target. CMake checks the source archive hash on a fresh fetch. The local
check reused the already hash-verified extracted source through
`FETCHCONTENT_SOURCE_DIR_WHISPER_CPP`; never point this override at unverified code.

Generate `build/asr/generated-speech.wav` locally using Windows System.Speech,
16 kHz/PCM16/mono, with the phrase hardcoded in `align_check.dart`. Do not speak
through a real microphone or send owner text to a speech service. Invoke the
native check with the verified local model path, generated WAV path and a new
absolute `build/asr/check-<guid>` prefix. It refuses existing MP4/JSON outputs.
Then `dart run tool/native_word_timing/align_check.dart check-<guid>` validates
the generated sidecar without printing text. All fixture files stay ignored.

## Runtime and remaining validation

These pieces are implemented: one cancellable native background job, verified
model store/download with size/progress/retry and licences, bounded overlapping
windows, model reuse, progress/shutdown and durable snapshot-based results.
Notes have no verbatim alignment; explicit no-microphone Screen takes are
labelled computer sound and receive no delivery scoring. Silence has no words.
Malformed timings fail with generic retry text, without private diagnostics.
`flutter run -d windows --release -t tool/native_speech_check.dart` runs the
generated full app-channel check using the verified files described above.
Use Release for native speech checks: Debug CPU recognition is much slower.

The current decoder intentionally caps PCM at 15 minutes (about 58 MB) and model
vocabulary at 8 KiB; these prototype bounds must never become a silent app limit.
Word timing remains approximate. Verify French, Arabic, Darija and French–Darija
switching with real consenting speakers before finalizing the default model.
Automatic processing after Stop, wording flags/corrections, reversible quiet
cuts and Windows video export with optional Readable captions are now connected. Corrections retain the
first recognition and its estimated confidence/times; they do not re-run ASR
or claim better timing. Optional filler review now preserves full recognition
and excludes only explicitly chosen complete words from cut captions. Repeated
Script sections can now be compared/listened to from frozen alignment, with
actual wording, source times, partial coverage and uncertainty. This derives
facts without grading a performance; Notes and computer-only remain unscored.
Safe reversible Keep attempt choices now connect the comparison to the cut,
requiring confident discarded words and measured quiet boundaries. Keep all
and Restore all preserve original words/media and earlier exports. Accepted
cues owned by retained words stay protected. Caption timing follows the same
union of kept source ranges; no word is split. Automatic best-performance
ranking, full Cut polish and delivery
review remain. The prototype 15-minute decoder limit
does not apply to the normal bounded runtime.

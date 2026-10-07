# Windows noise reduction

Saved takes offer **Reduce background noise**, initially off. It is aimed at
steady hiss and fans. It treats the entire recorded mix, including any computer
sound. It does not promise to isolate speakers or remove music. Every export
creates a new version; the recording and earlier videos stay unchanged.

## Commercial source and build

The classic backend is SpeexDSP 1.2.1, with no learned weights. Its BSD-3 source
permits commercial redistribution with notices. The runtime uses the official
tag `e762196693c487249d7061081915c8eaf7511f4f` and SHA-256
`be16e16bcbc26875916a8eedd3b5b46cb93bef4714c49895a28f8c86b81437cf`.
`app/windows/noise_runtime.cmake` compiles only unmodified preprocess, mdf,
filterbank, fftwrap and smallft sources. The residual-echo symbol requires mdf;
echo cancellation stays off. Upstream scripts, codecs, examples, jitter,
resampling and FFTW are excluded. No device or network interface is included.

The notice asset includes upstream COPYING and every compiled/included header's
copyright and licence notice; Settings registers it as speexdsp. See the
[upstream licence](https://github.com/xiph/speexdsp/blob/SpeexDSP-1.2.1/COPYING)
and [commercial checklist](compliance.md). RNNoise was not adopted: the current
separate weights have an unresolved explicit licence concern in
[upstream issue 284](https://github.com/xiph/rnnoise/issues/284).

## Sound and timing

Decode to bounded 48kHz mono/stereo PCM. Each channel has a separate classic
preprocessor with a 480-sample (10ms) frame. Set suppression to -12dB and mix
65% treated sound with 35% of the time-aligned original. AGC, dereverberation,
echo cancellation and VAD-based removal are off. Choices use design tokens.

Speex's overlap-add output describes the previous frame. The reader drops its
startup block, blends with that previous original block, and flushes the last
retained partial frame with zeros. It trims to the exact requested sample count.
No output sample, word or video timestamp is added or removed by this effect.
Lookahead never passes the end of the retained continuous source group; it
cannot borrow discarded speech. Every discontinuous source cut resets state.

Adjacent source ranges share one rounded source/output sample anchor. Fractional
microsecond splits and zero-sample subranges therefore do not duplicate, skip or
reset samples. This common clock also applies when processing is disabled.
Pipeline order is noise reduction, detector-only de-essing, sound joins, then
the measured fixed volume gain. The gain prepass and renderer share all stages.
No audio is invented for a video-only source, and exports shorter than 400ms
keep their original sound. Jobs remain cancellable and errors stay generic.

## Verification

Generated fixtures check steady-noise attenuation, preserved tones, exact
impulse position, silence, partial tails and identity at zero treatment strength.
Native exports check mono/stereo AAC, fractional continuous ranges, source cuts,
discarded-tone protection, 44.1kHz resampling, short/video-only protection,
invalid policies and cancellation before output ownership. Combined noise,
de-essing and volume balance measure the final treated mix. App tests check
EN/FR/AR saved-take on/off choices, strict old/new metadata and journal recovery.
Screenshots cover light/dark phone controls with RTL script titles. Actual
listening with the owner's microphones remains deferred; generated tones
cannot establish natural-speech quality.

# Compliance: licences, privacy, stores and consumer law

SpawnAlpha is a commercial product: a free tier plus a paid subscription. Everything it
ships, collects or sells has to be lawful in the places it is sold, starting with the EU
(France), Morocco, the US and the app stores. This file has two parts:
- the **rules every agent follows**;
- the **checklist** of what is done and what is still open.

**This is not legal advice.** It records what the team knows and decided. Before the first
paid release, a lawyer should review:
- the privacy policy;
- the terms of service and EULA;
- the subscription terms;
- the Moroccan data-protection filing;
- the name's trademark search.

## Rules for agents

1. **No new dependency, font, icon set, model or copied code without checking its
   licence first.** Record it in the table below.
   - Allowed: MIT, BSD, Apache-2.0, OFL, zlib, ISC, and MPL-2.0 (used unmodified).
   - LGPL only as a dynamically linked library, with its licence shipped and the owner's
     approval.
   - **Never** GPL or AGPL code, and never "non-commercial" or "research only" models or
     assets.
2. **Keep attribution.** Code copied or adapted from OpenScreen (MIT) keeps its copyright
   notice in the file header. Every licence must show on the app's licence page.
3. **Data minimisation.** Collect only what a feature needs, keep it on the device by
   default, and never log script text, recordings, API keys or typed characters.
   - Screen telemetry records cursor positions, clicks and key *timing*, never which keys
     were typed. The one exception is modifier chords, such as Ctrl+S, shown as badges.
4. **Say what leaves the device.** Anything sent off the device must be:
   - visible in the UI at the moment it happens (for example, "Mark up with Claude" sends
     the script to Anthropic);
   - described in the privacy policy.
5. **Secrets stay in secure storage.** Never commit keys, tokens or certificates. Search for
   them before each push.
6. **Store rules win over convenience.** Check the current Apple App Store Review
   Guidelines and Google Play policies before building:
   - billing;
   - screen capture;
   - overlays;
   - background services;
   - account features.
7. **Log decisions.** Record every legal or commercial decision in `docs/status.md` under
   "Decisions", and update this checklist.

## Third-party components

| Component | Licence | How we use it | Obligations | Status |
|---|---|---|---|---|
| Flutter SDK and Dart packages (camera, path_provider, http, flutter_secure_storage, wakelock_plus, cupertino_icons and their dependencies) | BSD-3, MIT, Apache-2.0; `dbus` (Linux only) is MPL-2.0 | Linked into the app | Keep the notices. Flutter bundles them into the app's NOTICES, shown by the licence page | Done: licence page in Settings |
| camera_platform_interface, plugin_platform_interface, fake_async (dev only) | BSD-3, Apache-2.0 | Test and screenshot fakes; not shipped | None | Done |
| camera_windows 0.3.0, **vendored and modified** in `app/packages/camera_windows` | BSD-3 | Windows camera, now with microphone choice and metering | Keep the licence and copyright notice; the README lists our changes | Done |
| Anybody, Readex Pro, Martian Mono, Caveat, Aref Ruqaa, Reem Kufi | SIL Open Font License 1.1 | Bundled in `app/assets/fonts` | Ship the licence with the fonts. Don't sell the fonts on their own. Rename any modified font | Done: OFL texts bundled and registered |
| Material Icons and Symbols | Apache-2.0 | Icons and cue glyphs | Notice | Done: comes with Flutter |
| OpenScreen (reference and parts source) | MIT | Ideas so far; any copied code later | Keep its copyright notice in copied files and in NOTICES | No code copied yet |
| whisper.cpp and Whisper models (step 3) | MIT (code and OpenAI's Whisper weights) | Windows CPU speech runtime and explicit public-model first-use download | Notices bundled in assets/licenses and registered on the app licence page; check every fine-tuned model separately | Checked 2026-10-06: pinned upstream v1.9.4 source and converted base weights, exact size/SHA-256 verification. No recording/script upload; see word-timing.md |
| Video encoding (step 4, render core) | Installed Windows Media Foundation H.264/AAC | Local MP4 export | No bundled codec/package; see below | First Windows exporter checked 2026-10-06; launch legal review remains open |

### Video codecs and the render core

- **Patents:** H.264, HEVC and AAC are covered by patent pools. The operating systems'
  own encoders generally come with the OS vendor's licence:
  - Media Foundation on Windows;
  - MediaCodec on Android;
  - AVFoundation on iOS.
- **Recommendation:** encode through the platform encoders, not a bundled encoder. This
  also favours platform encoders for the render core (see [roadmap.md](roadmap.md)).
- Local take playback uses Windows MediaPlayer with file-only StorageFile sources,
  bounded preview frames and generic errors. No extra player package or codec pack;
  network shares, URLs, alternate streams and reparse points are rejected.
- Local export uses the same guarded file-only paths and installed D3D11/Media
  Foundation. Complete-picture compositing, cuts and AAC resampling stay on the
  device. Fresh output files, recovery journals and captions never overwrite
  originals; failures never log scripts, media paths or OS exception messages.
  Optional sound-join fades transform only bounded decoded PCM at internal
  cut boundaries; they never amplify, upload, overlap words or change clocks.
  Original sound and earlier exports remain intact. No extra DSP library,
  copied code, model or noise/loudness claim is introduced.
- Optional screen zooms use only existing local anonymous click, shortcut and
  typing timing/position data. No typed characters or key identities are read.
  Bounded parsing rejects unknown payloads and malformed/misplaced activity;
  a generic notice retains the full picture. Export decisions contain only
  normalized targets/times/source dimensions, never source/activity paths.
  They stay on the device and can be disabled per export. Installed D3D11
  source rectangles and existing spring tokens need no new dependency/model.
  Spoken pointing targets use the frozen Script and existing saved local words,
  with exact reliable/corrected alignment and whole-phrase cut provenance.
  Notes and uncertain/unsaid speech supply no bonus; no transcript text is
  added to portable zoom metadata or diagnostics. No new collection or upload.
  Optional click highlights read only retained visible click position/timing
  from the same existing local sidecar. Their bounded immutable pulse track
  contains no text/key identity/path. Installed Direct2D draws the fixed amber
  spring ring/halo, excluding the camera and margins. The separate on/off
  choice and saved count need no package, model, upload or copied code.
- Optional shortcut badges use only the existing disclosed 14-item Ctrl /
  Ctrl+Shift enum. Plain typing never becomes display text. Bounded immutable
  label/timing tracks remain local, exclude private paths and reject every
  unapproved label in Dart and native rendering. The separate export switch
  and history count use installed DirectWrite/Direct2D and already bundled
  OFL Martian Mono through a private font collection. No font installation,
  download, new package/model, copied code, upload or private diagnostic.
- Optional screen frames fit the original picture inside a fixed inset, with
  rounded corners, a locally generated dark gradient and the existing shadow
  tokens. Installed Direct2D/Gaussian blur draws only the decorative shadow,
  never a downloaded wallpaper or a face model. Camera placement and caption
  clocks stay independent. The switch/legacy-compatible history remains local;
  original media is read-only. No new package, asset, copied code or upload.
- Optional captions on video use installed DirectWrite/Direct2D and the already
  bundled OFL Anybody/Reem Kufi fonts through a private local font collection.
  No font installation/download, new package, copied code or network service.
  Caption wording follows saved actual speech/corrections and stays local.
  Karaoke uses saved word intervals on the cut clock and stable shaping;
  style choices stay in local immutable export history. No extra model or data
  collection is needed for word highlighting. Cue/Punch and accepted cue
  typography use only the frozen Script, reliable saved-word alignment and
  existing spring/type tokens. Decorative Arabic stretching never changes
  recognized words or subtitle spelling. Still is local; no performance score
  is implied by the visual emphasis.
- **If FFmpeg is used at all:**
  - use an **LGPL build** without `--enable-gpl` or `--enable-nonfree`, which means no
    x264 or x265;
  - link it dynamically;
  - ship its licence and say where its source is.
- **Confirm with counsel** before the first release that exports video.

## Privacy

| Data | Where it lives | Leaves the device? | Notes |
|---|---|---|---|
| Speaker-note decks and take snapshots | App documents folder | No automatic transmission | Private topic cards are excluded from screen capture. Any later cloud action must be explicitly selected and named; captions follow actual speech |
| Spoken words, alignment and subtitle exports | Beside takes and in the local exports folder | No | Local recognition uses frozen aids. Notes and explicit computer-sound-only takes have no script adherence scoring. Copy/export are explicit local actions |
| Automatic review after Stop | Local words/cuts and the existing model folder | No | Default-enabled, reversible and switchable in Settings. Automatic checks use installed weights only; missing setup offers an explicit disclosed download. Live recording previews and microphone meters close during review; originals remain intact |
| Reversible cut plans and measured quiet ranges | Local cuts/words folders | No | Original media never changes; source intervals and switches are personal data. No transcription gaps treated as proof of silence; all words, marked gaps/breaths and uncertainty margins are protected |
| Public offline speech model | Local models folder | A public GET downloads model weights from Hugging Face; no owner media/text is sent | Exact pinned revision, size/SHA-256 verification and first-use UI disclosure. Download host receives ordinary connection metadata |
| Scripts and marks | App documents folder | Only when the user runs markup with an online provider. Then the script text goes to that provider (Anthropic, OpenAI, Google, Mistral, or the user's own server) | The editor names the provider on the button. The privacy policy must list providers |
| API keys | Platform secure storage | Only to the provider they belong to | Never logged |
| Recordings (video, audio: face and voice) | App documents folder | No, for now. Future online transcription must be opt-in | Personal data. Face reframing runs on the device and must never identify people, so it doesn't become biometric processing under GDPR Art. 9 |
| Screen telemetry (step 2) | Beside the take | No | Cursor, clicks, key timing and window rectangles. No typed characters |
| Accounts and billing (subscription backend, later) | Our backend and the payment provider | Yes | Needs a lawful basis, retention periods, data processing agreements with the AI provider and the payment provider, and account deletion inside the app (an Apple requirement) |

What the laws require, in short:
- **EU and France: GDPR.**
  - a privacy policy;
  - a lawful basis for each processing;
  - access, export and erasure rights;
  - data processing agreements with processors;
  - safeguards for transfers outside the EU (for example, standard contractual clauses
    with US AI providers).
- **Morocco: Law 09-08 and the CNDP.** If the business is established in Morocco,
  processing personal data needs a declaration to, or authorisation from, the CNDP before
  it starts, and transfers abroad have their own rules. Counsel should handle the filing.
- **US.** A privacy policy is needed for the stores and by several state laws (for
  example, California's CalOPPA). The CCPA and CPRA apply above their size thresholds.
- **Children.** The app is not directed at children. Set the store age ratings to match,
  and don't knowingly collect data from under-13s (COPPA), or under-16s where EU member
  states set that age.

## App stores and distribution

- **Permission strings** are present and specific: camera, microphone and local network
  on iOS; camera, microphone and internet on Android.
  - Screen recording will add a foreground service of type `mediaProjection` on Android,
    with its permission and the Play Console declaration.
  - A prompter overlay on Android needs the overlay permission, and Play's policy
    reviewed.
- **Export compliance (iOS):** the app only uses standard HTTPS, so
  `ITSAppUsesNonExemptEncryption` is `false`. Revisit this if we add our own encryption.
- **Store disclosures:** Apple's privacy details and Google Play's Data safety form must
  match the privacy table above. Both stores need a privacy policy URL.
- **Subscriptions:**
  - Inside the iOS and Android apps, digital subscriptions generally have to go through
    Apple In-App Purchase and Google Play Billing. Exceptions depend on country and change
    over time, so check the current rules when billing is built.
  - The Microsoft Store allows non-game apps to use their own payments.
  - A Windows build sold outside the Store needs a code-signing certificate, and a
    merchant of record or our own VAT and sales-tax registration.
- **Accounts:** if users can create an account in the app, they must be able to delete it
  from inside the app (Apple).

## Consumer and subscription law

- **Pricing:** show prices with VAT where required (EU).
- **Before purchase:** state the renewal terms, the price and how to cancel.
- **Cancelling** must be as easy as subscribing: EU rules, and US automatic-renewal laws
  such as California's.
- **EU right of withdrawal** (14 days) for digital content and services. It can be waived
  for immediate access only with the consumer's explicit consent and acknowledgement at
  purchase. The stores handle this for in-app purchases. We handle it for direct sales.
- **Honest claims:**
  - Marketing claims must be accurate. For example, "most takes need no editing" needs
    real data first.
  - Don't use competitors' trademarks in ways that suggest affiliation.

## Accessibility

- The **European Accessibility Act** has applied since 28 June 2025 to consumer e-commerce
  services, which includes selling subscriptions. Micro-enterprises are exempt for
  services.
- Design to WCAG 2.1 AA regardless, as the design language already requires: contrast,
  no colour-only signals, keyboard access, reduced motion and screen-reader labels.

## AI

- **Provider terms:**
  - With a user's own key, the user's contract with the provider governs the use.
  - For the paid subscription, where we call the provider for the user, we need that
    provider's commercial terms and a data processing agreement, and we must follow its
    usage policies.
  - Check each provider's data-use terms (training, retention) and state them in the
    privacy policy.
- **Scope:** the markup (cue suggestions) and captions are low-risk uses under the EU AI
  Act. The Act's transparency duties would apply if we ever generate synthetic voices,
  faces or other realistic media. Label such output, and check the Act first.
- **Transparency:** AI proposals are always shown as proposals, and the user accepts them.
  The app never rewrites the script silently.

## Recording other people

The app records camera, microphone and screen. The terms of service must make the user
responsible for consent when others are recorded. Recording laws differ: some places need
the consent of everyone recorded. While recording, the tally is always visible to the
person using the app.

## Our own code and name

- **The repository `HarDvolT/SpawnAlpha` is public on GitHub.** With no licence file, the
  code stays "all rights reserved", but anyone can read and copy the ideas.
  - **Decision needed:** make the repository private, or add a proprietary licence notice.
  - Don't add an open-source licence by accident.
- **Name:** "SpawnAlpha" is a placeholder. Before launch, run a trademark search for the
  real name (EUIPO, USPTO, and OMPIC in Morocco), then register it.
- **Company:** sell through a registered legal entity. The terms of service, EULA and
  privacy policy should name it.

## Checklist

| Item | Status |
|---|---|
| Offline speech prototype and EN/FR/AR alignment foundation | Checked 2026-10-06 with generated SAPI/WAV/AAC media only, no owner's microphone/recordings. Pure alignment preserves spoken text and all attempts, bounds work and rejects malformed estimates without private errors. Native decoder refuses remote/network/reparse paths; upstream logging suppressed before load; active/pre-start cancellation passes. Prototype inputs on E:, notices retained. Model setup/licence UI, durable take processing and real language quality trials remain pending |
| Windows render-core risk spike and portable EDL | Checked 2026-10-06 in Debug/Release with generated colour/tone files only. Uses installed D3D11/Media Foundation; no dependency, bundled codec, copied code, model or owner media/input. EDL has no paths/platform IDs. Full exporter/captions/mobile pipeline and launch legal review remain pending; see render-core-spike.md |
| Optional Windows recording activity: explicit local-only choice, anonymous typing, source scoping, safe recovery | Implemented 2026-10-06. Initially off; setup explains what is saved and never typed text. Fixed Ctrl shortcut allowlist, no AltGr text translation, scan codes, titles, handles or device IDs. Raw-input receiver does not consume owner input and stops with capture. Bounded queue/streaming inspection, no private logs/network/dependency/copied code. Pure privacy/common-clock, in-memory own-window exclusion and generated full-take checks pass. Owner trials deferred |
| Font licences bundled and shown | Done |
| Automatic after-stop processing and live-input release | Checked 2026-10-06 with generated speech only. EN/FR/AR Script/Notes, missing setup without HTTP, pre-start cancellation, reuse/reload and recorder input lifetime pass. Cached public model copied after size/SHA-256 verification. No owner recordings processed, dependency added or private errors logged. Hardware/language trials remain deferred |
| Local transcript wording corrections | Checked 2026-10-06 with pure EN/FR/AR fixtures and generated native Script/Notes speech. Original recognized text, confidence and times are retained locally; correction/restore creates immutable revisions, rebuilds cuts and preserves earlier exports. No model/network/owner input required. Failed attachment rollback, stale/concurrent rejection and retry pass. Notes/computer-only stay unscored; time editing, filler/retake policy and real-language quality trials remain pending |
| Windows first video exporter and local history | Checked 2026-10-06 with generated colors/tones only: all four formats, exact video clock, selected/reordered audio, mono/stereo resampling, silent source, camera inset/end, Unicode paths, paused playback, cancellation, damaged input, overwrite rejection and caption/library failure recovery. No owner media/input, new dependency, copied code, network or bundled codec. Full Cut polish/mobile implementation and launch counsel review remain pending |
| Readable captions on Windows exports | Checked 2026-10-06 with generated EN/FR/AR phrases, two lines, Arabic diacritics/mixed text, safe portrait pixels, all four formats, caption on/off, corrected-word/cut clocks, old history and cancellation. Uses installed DirectWrite/Direct2D and existing OFL bundled fonts privately, without installation, download or new dependency. Original media and earlier exports stay intact. Caption motion, real-language speech quality, mobile and launch legal review remain pending |
| Karaoke video captions and saved style | Checked 2026-10-06 with exact EN/FR/AR word ranges/gaps, immutable request copies, Unicode/UTF-16 validation, style history compatibility, quiet/retake cut timing and generated native decoded pixels. Word fill, progressive LTR/RTL underlines, no underline in gaps, safe output margins and Arabic diacritics/mixed text pass at actual export sizes. The real app-channel generates nine keep/select/restore exports across EN/FR/AR, retaining style, SRT/VTT, history and original bytes. No owner media/input, model, dependency, upload or private logs. Cue/Punch cue motion, real speech quality, mobile and launch legal work remain pending |
| Cue/Punch and accepted cue caption typography | Checked 2026-10-06 with pure EN/FR/AR frozen Script/source-word fixtures, reliable/corrected versus changed/uncertain speech, Notes protection, discarded/reordered attempts, Arabic display-only elongation, UTF-16 timing guards and additive style/Still history. Generated native decoded pixels pass reveal, stress, spring/Still, neighboring-word spacing and safe margins; actual Windows app-channel Cue/Punch/Karaoke retake exports pass exact clocks, subtitle/history/reload and original bytes. Uses existing privately loaded OFL fonts, installed DirectWrite/Direct2D and existing spring tokens. No owner media/input, dependency, upload, model or private logging. Real speech/hardware quality, sound/screen polish, mobile and launch legal work remain pending |
| Reversible filler review | Checked 2026-10-06 with pure EN/FR/AR and generated silent/tone/video fixtures. Proposals start kept; only explicit switches remove complete confirmed words from exported captions/media. Measured quiet, confidence, frozen Script/Notes policy and accepted pauses/breaths gate proposals; Screen context stays protected. Original recognition/media and older revisions remain intact. Native decoded audio/pixels and real app-channel keep/remove/restore/export/reload pass. No new dependency, owner media/input or network. Real-language quality, retakes and sound polish remain pending |
| Original filler phrase listening | Checked 2026-10-06 with generated video and EN/FR/AR widgets. Only the explicit Hear action starts sound; it plays a bounded original excerpt and pauses on the existing status poll. Scrolling cannot repeat the request; backgrounding, replacement and disposal cancel it. Cut decisions and original files remain unchanged. No owner media, new dependency, network or private logs |
| Repeated Script section comparison | Checked 2026-10-06 with generated EN/FR/AR word fixtures and full review widgets. Uses frozen scripts/actual wording in a bounded isolate; ordinary repetition, Notes and null alignment remain unscored. Partial coverage and uncertain wording are shown honestly. Explicit listening preserves every cut choice and original; no best-performance or recognition-quality claim, dependency, upload or private logs. Real language/hardware trials remain pending |
| Safe reversible retake selection | Checked 2026-10-06 with EN/FR/AR word/quiet fixtures, 800-attempt bounds, stale/forged-plan rejection, full review controls and generated native tone/picture exports. All attempts start kept; only explicit choices discard complete confident words at measured safe boundaries. Cues owned by retained words remain protected; Notes/Screen/computer-only stay unscored. Native app-channel selection/restore, exact cut clocks, burned captions/SRT, history/reload and original-byte checks pass. No owner media/input, dependency, upload or private logs. Automatic performance ranking, real-language/hardware trials and launch legal work remain pending |
| Optional Windows sound-join fades | Checked 2026-10-06 with generated mono/stereo packets, short ranges, packet boundaries, disabled/continuous joins, decoded AAC attenuation and unchanged distant tone levels/whole-versus-contiguous PCM. EN/FR/AR export controls, immutable history and cut/caption clocks pass. Only retained internal join edges are attenuated; no overlap, amplification, source modification or new DSP library. No owner media/input, dependency, copied code, upload, model or private logs. Room-tone crossfades, LUFS/noise/de-essing, hardware listening and launch legal work remain pending |
| Optional Windows activity zooms | Checked 2026-10-06 with EN/FR/AR pure targets, cut/reorder/source-resize clocks, fresh cursor/focus, bounded clusters/typing, malformed/private payload rejection, missing files and crash-truncated traces. Generated native wide/portrait decoded pixels pass clamped spring crops, pan/reset and full-picture return; actual app-channel EN/FR/AR wide/feed/portrait on/off exports preserve captions/history and source/activity bytes. Completed-job recovery preserves exact frozen targets after activity removal. No owner media/input, new dependency, copied code, model, upload or private logs. Pointing-word zooms, cursor/frame polish, hardware trials and launch legal work remain pending |
| In-app licence page (Settings, Privacy and licences) | Done |
| Spoken pointing zooms | Checked 2026-10-06 with normalized EN/FR/AR phrases, full frozen Script alignment, exact reliable/corrected wording, Notes/uncertain/unsaid protection and whole-phrase source-cut provenance. Ordinary click evidence survives loss of its phrase bonus. Real app-channel one-click exports preserve subtitles/history/target clocks and source/activity bytes. No owner input, model, dependency, upload or private logs; real speech quality and launch legal work remain |
| Optional Windows click highlights | Checked 2026-10-06 with pure EN/FR/AR retained/reordered/continuous ranges, hidden/key protection, clipped lifetimes, bounded malformed tracks, independent switches and frozen recovery after activity removal. Generated native wide/portrait decoded pixels pass onset/fade under zoom, and camera-covered pulses decode identically to the no-ring baseline. Actual app-channel independent zoom/click on/off exports preserve timing/history/original bytes. Uses installed Direct2D and existing palette/spring tokens; no owner media/input, package, model, copied code, upload or private logs. Cursor/frame/keycap polish and hardware/launch trials remain |
| Optional Windows shortcut badges | Checked 2026-10-07 with EN/FR/AR cut/reorder/continuous clocks, latest-wins badges, hidden plain typing, bounded allowlisted labels, independent switches, legacy count compatibility and frozen recovery after activity removal. Native decoded wide/portrait safe-edge/onset/rise/fade and private-label rejection pass; actual app-channel 12 independent choices preserve exact subtitle clocks/history/original bytes. Installed DirectWrite/Direct2D and already bundled private OFL Martian Mono only; no owner input/media, dependency, model, upload or private logs. Screen frame/cursor/sound and hardware/launch work remain |
| Optional Windows screen frame | Checked 2026-10-07 with EN/FR/AR Screen/Both on/off without activity, Camera protection, legacy compatibility and completed-job recovery. Native decoded wide/portrait corners/full picture/inset zoom/click and unchanged camera placement pass; actual app-channel 12 frame on/off exports retain exact captions/history/original bytes. Uses installed Direct2D Gaussian shadows and a locally generated gradient with existing tokens; no owner media/input, wallpaper, package, copied code, model, upload or private logs. Smooth cursor/blur/camera/sound and hardware/launch work remain |
| "What leaves your device" explained in Settings | Done |
| iOS export-compliance flag | Done |
| No secrets in the repository (scanned 2026-09-30) | Done |
| Windows source picker: names kept only in memory, no capture or title logging, no new dependency | Checked 2026-10-05; owner-confirmed. Recording and thumbnails remain pending; preview is separate below |
| Windows live preview: selected source only, frames in memory, no files/audio/network/private logs, capture closes on exit | Checked 2026-10-05; owner confirmed live updates. Uses installed Windows SDK APIs; no copied code or new package |
| Windows floating prompter: capture exclusion before visibility, in-process script transfer only, no new microphone/file/network access | Implemented 2026-10-05; native visibility/exclusion/close smoke passed, owner trial pending. No new dependency or copied code. Global shortcuts only, no input hooks or typed-character logging |
| Windows video/sound saver cores: operating-system H.264/AAC, GPU conversion, local fragmented MP4 only | Checked 2026-10-05 with generated colors/tones and abrupt-exit recovery. Shared microphone capture pins the chosen/default endpoint and never falls back from a missing choice. Connected to Screen mode. No bundled codec, new package, copied code or private logging |
| Windows capture/save pipeline: explicit selected source and microphone, common-clock local file, recoverable stop | Implemented 2026-10-05; native generated-window tests pass, including real default-microphone AAC and source loss. Fixtures stay under ignored app/build; no private content/title logging. Screen setup is enabled with protected windows, explicit silent choice, safe release and durable metadata |
| Durable take manifests and recovery: on-device script snapshot, source description, audio choice and file verification | Implemented/tested 2026-10-05 in EN/FR/AR and normal Screen setup. No keys or native handles persisted. Recovery rejects external paths/symlinks, preserves later edits/deletions and unreadable data, and never logs private content or errors. Empty pre-capture cancellations are marked locally; unreadable captured files remain for recovery |
| Windows recording HUD/countdown: verified exclusion before visibility, setup affinity restored on close, minimum state transfer | Implemented 2026-10-05; native full silent generated-window take and visibility/exclusion/restore checks pass, EN/FR/AR layout/control tests. No capture/file/microphone access in child. Click-through uses transient cursor coordinates only, no hooks or private logging. Native release joins capture before restoring affinity; owner placement/click-through trials deferred |
| Repository visibility or proprietary notice | **Owner decision** |
| Windows cursor companion: explicit camera-follow choice, excluded reader, transient pointer samples only | Checked 2026-10-06 with pure direction/edge/rest/monitor checks, protected generated paired take, EN/FR/AR UI and layouts, reduced motion and hide/show cleanup. Reuses the same reader/controller; no input hook, typed characters, persisted positions, new dependency/copied code or network. Only the camera-follow preference is saved. Camera warning remains inside the excluded HUD with Pause/Stop available. Owner comfort and multiple-monitor trials deferred |
| Windows camera self-view: exclusion before visibility, recorder-owned frames, no extra camera/file access | Checked 2026-10-06 with native lifetime/exclusion, full generated paired take and EN/FR/AR layout/control cases. Connected to Both; setup preview releases before native capture. Child gets display metadata and a memory texture only, no file paths/device IDs. Drag uses transient native cursor coordinates; no hooks, logs or telemetry. Recorder release precedes unprotecting setup; owner hardware trials deferred |
| Windows paired-camera core: exact chosen device, separate silent fragmented camera file, one clock with screen/audio | Checked 2026-10-06 with generated video, pause/resume, stop while paused, camera loss and repeated device lifetime. Both enabled; full protected generated take verifies separate files/common pause/durable save. Local recovery rejects external paths/links, preserves unreadable camera bytes plus useful Screen output and warns explicitly. No device IDs persisted. Installed Windows APIs only; no dependency, copied code, network or private logging. Test-only file camera input exists solely in an explicit non-shipping fixture binary |
| Privacy policy, terms of service and EULA drafted by counsel | Before paid launch |
| Windows computer sound: explicit per-visit opt-in, default playback endpoint pinned, bounded shared-clock stereo mix, no private logs | Checked 2026-10-06 with generated tones/window, stereo decoding, idle gaps, pause removal, start failure and device loss. Normal Screen/Both switch explains the whole default playback mix, including other apps, stays on device. No-microphone choice stays explicit; HUD and quiet/device warnings distinguish playback from microphone. Manifests preserve the sound choice/scope without endpoint IDs. Real format/lifetime check discards all samples in memory; the full protected UI take links generated endpoints only and requires a fixture handshake before capture. Uses installed Windows APIs only, no dependency/copied code/network. Owner actual playback/routing trials deferred |
| CNDP declaration (Morocco), if established there | Before processing personal data at scale |
| Store privacy labels and Data safety form | Before store submission |
| Billing through store billing where required; cancellation and withdrawal flows | When the subscription is built |
| Render core on platform encoders; LGPL-only if FFmpeg is used | Step 4 |
| Whisper and Darija model licences checked | Upstream code/converted base weights checked for step-3 prototype; any fine-tuned/Darija model remains unapproved |
| Trademark search for the final name | Before launch |

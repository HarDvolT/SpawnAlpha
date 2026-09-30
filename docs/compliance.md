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
| whisper.cpp and Whisper models (step 3) | MIT (code and OpenAI's Whisper weights) | On-device transcription | Notice. Check any fine-tuned model's own licence (for Darija), because many are non-commercial | To check at step 3 |
| Video encoding (step 4, render core) | see "Video codecs" below | Export | see below | Open decision |

### Video codecs and the render core

- **Patents:** H.264, HEVC and AAC are covered by patent pools. The operating systems'
  own encoders generally come with the OS vendor's licence:
  - Media Foundation on Windows;
  - MediaCodec on Android;
  - AVFoundation on iOS.
- **Recommendation:** encode through the platform encoders, not a bundled encoder. This
  also favours platform encoders for the render core (see [roadmap.md](roadmap.md)).
- **If FFmpeg is used at all:**
  - use an **LGPL build** without `--enable-gpl` or `--enable-nonfree`, which means no
    x264 or x265;
  - link it dynamically;
  - ship its licence and say where its source is.
- **Confirm with counsel** before the first release that exports video.

## Privacy

| Data | Where it lives | Leaves the device? | Notes |
|---|---|---|---|
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
| Font licences bundled and shown | Done |
| In-app licence page (Settings, Privacy and licences) | Done |
| "What leaves your device" explained in Settings | Done |
| iOS export-compliance flag | Done |
| No secrets in the repository (scanned 2026-09-30) | Done |
| Repository visibility or proprietary notice | **Owner decision** |
| Privacy policy, terms of service and EULA drafted by counsel | Before paid launch |
| CNDP declaration (Morocco), if established there | Before processing personal data at scale |
| Store privacy labels and Data safety form | Before store submission |
| Billing through store billing where required; cancellation and withdrawal flows | When the subscription is built |
| Render core on platform encoders; LGPL-only if FFmpeg is used | Step 4 |
| Whisper and Darija model licences checked | Step 3 |
| Trademark search for the final name | Before launch |

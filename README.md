# SpawnAlpha

A teleprompter that coaches your delivery: the AI directs, you perform, the AI checks.
"SpawnAlpha" is a working name.

- **Product brief:** [docs/product-brief.md](docs/product-brief.md)
- **Progress and next steps:** [docs/status.md](docs/status.md)
- **How the code works:** [docs/architecture.md](docs/architecture.md)
- **Design language:** [docs/design-language.md](docs/design-language.md)
- **Guide for contributors and agents:** [AGENTS.md](AGENTS.md)

The app is Flutter (Windows, Android, iOS) and lives in [`app/`](app/):

```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d windows   # or an Android or iOS device
```

## Try a test build (no Flutter needed)

Every push that touches `app/` runs the **Build** workflow
([.github/workflows/build.yml](.github/workflows/build.yml)). It analyzes and tests the app,
then builds:

- **Windows:** a zip of the app folder. Unzip it anywhere and run `spawnalpha.exe`. The
  build is unsigned, so Windows SmartScreen will warn: choose *More info*, then *Run anyway*.
- **Android:** an APK signed with a debug key. Copy it to the phone and open it, allowing
  installs from that source when Android asks.

To download: open the repository's **Actions** tab on GitHub, pick the latest green
**Build** run for your branch, and download from **Artifacts** at the bottom. You must be
signed in to GitHub. Artifacts are kept for 14 days.

These are test builds for the team, not releases: they are not signed for distribution
and must not be given to customers (see [docs/compliance.md](docs/compliance.md)). iOS
builds need a Mac and an Apple developer account, so they are not built yet.

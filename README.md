# SpawnAlpha

A teleprompter that coaches your delivery: the AI directs, you perform, the AI checks.
"SpawnAlpha" is a working name.

- **Product brief:** [docs/product-brief.md](docs/product-brief.md)
- **Progress and next steps:** [docs/status.md](docs/status.md)
- **How the code works:** [docs/architecture.md](docs/architecture.md)
- **Guide for contributors and agents:** [AGENTS.md](AGENTS.md)

The app is Flutter (Windows, Android, iOS) and lives in [`app/`](app/):

```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d windows   # or an Android or iOS device
```

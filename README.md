# insaat_yonetim

A new Flutter project.

## Platform Support

Supported platforms:
- Web
- iOS
- macOS

Android support has been removed from this repository.

## Firebase API Key Security

The web, iOS, and macOS Firebase API keys are no longer stored directly in source.
Use a local file one time, then run with scripts without typing keys again.

### One-time local setup

1. Copy the template file:

```bash
cp firebase_keys.example.json firebase_keys.local.json
```

2. Open firebase_keys.local.json and paste your rotated keys.

3. (macOS) Make scripts executable once:

```bash
chmod +x scripts/run_ios.sh scripts/run_macos.sh scripts/run_web.sh
```

### Web Run

```bash
./scripts/run_web.sh
```

### iOS Simulator Run

```bash
./scripts/run_ios.sh
```

### macOS Run

```bash
./scripts/run_macos.sh
```

All scripts use:

```bash
--dart-define-from-file=firebase_keys.local.json
```

### Website restrictions for web API key

In Google Cloud Console for the web key, set Application restrictions to Websites and allow:

- https://insaat-yonetim-takip.web.app/*
- https://theplaybook7.github.io/*
- http://localhost/*

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

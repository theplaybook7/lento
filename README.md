# insaat_yonetim

A new Flutter project.

## Platform Support

Supported platforms:
- Web
- iOS
- macOS

Android support has been removed from this repository.

## Firebase API Key Security

The iOS and macOS Firebase API keys are no longer stored directly in source.
Provide them at run/build time after rotating keys in Google Cloud Console.

### iOS Simulator Run

```bash
flutter run -d "iPhone 15 Pro Max" \
	--dart-define=FIREBASE_IOS_API_KEY=YOUR_ROTATED_IOS_KEY \
	--dart-define=FIREBASE_MACOS_API_KEY=YOUR_ROTATED_MACOS_KEY
```

### macOS Run

```bash
flutter run -d macos \
	--dart-define=FIREBASE_IOS_API_KEY=YOUR_ROTATED_IOS_KEY \
	--dart-define=FIREBASE_MACOS_API_KEY=YOUR_ROTATED_MACOS_KEY
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

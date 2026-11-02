# LocalDrop — Flutter UI prototype

A UI-only, cross-platform Flutter project for the LocalDrop local-network photo/video sharing concept.

## Stack
- Flutter / Dart
- Material 3
- Google Fonts (Plus Jakarta Sans)
- Targets: Android and iOS

## Included screens
- Home / landing
- Create session
- Starting session
- Host session lobby / QR
- Join session scanner
- Join session details
- Shared gallery
- Full-screen media viewer
- Upload manager
- Session dashboard
- Session settings / host controls
- Multi-select download

## Run
1. Install Flutter: https://docs.flutter.dev/get-started/install
2. From this directory run:
   ```bash
   flutter pub get
   flutter run
   ```

For iOS, build on macOS with Xcode installed:
```bash
flutter build ios
```

For Android:
```bash
flutter build apk
```

## Notes
This is intentionally a visual prototype. Buttons, upload controls, QR scanning, networking,
hotspot detection, authentication, media access, persistence and transfers are not implemented.
The screens use local mock content and placeholder imagery from `images.unsplash.com`.
Replace placeholder assets with bundled/licensed assets before production.

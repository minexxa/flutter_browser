# Flutter Android Browser

A simple, clean multi-tab web browser for Android built with Flutter and the official `webview_flutter` package.

## Features

- **Multi-tab browsing** — switch and manage tabs easily
- **Address bar** — supports both URL and Google search
- **Navigation controls** — Back / Forward / Reload / Stop / Home
- **Loading progress** indicator
- **Desktop mode** toggle (change User-Agent)
- **Copy URL** to clipboard
- Material 3 UI with system light/dark theme support
- Support for opening http/https links from other apps

## Requirements

- Flutter 3.22 or higher
- Android `minSdk 24`

## Getting Started

```bash
git clone https://github.com/aasszz77d/flutter_android_browser.git
cd flutter_android_browser

# Generate missing platform files (icons, gradle wrapper, etc.)
flutter create . --platforms android

flutter pub get
flutter run
```

> **Important**: Always run `flutter create . --platforms android` once after cloning.  
> This fills in the default launcher icons and Gradle wrapper binaries that are not committed in the repository.

## Build Release APK

```bash
flutter build apk --release
```

The APK will be located at:

```
build/app/outputs/flutter-apk/app-release.apk
```

## GitHub Actions

A workflow (`.github/workflows/build.yml`) is included:

- Triggers on push / PR to `main` and manual dispatch
- Sets up Flutter stable + Java 17
- Runs `flutter analyze` and `flutter build apk --release`
- Uploads the release APK as an artifact (kept for 14 days)

You can download the built APK from the Actions tab after a successful run.

## Project Structure

```
lib/
  main.dart              # Complete browser UI + multi-tab logic
android/
  app/src/main/
    AndroidManifest.xml  # INTERNET permission + link handling
    kotlin/.../MainActivity.kt
.github/workflows/
  build.yml              # CI build for APK
```

## Tech Stack

- Flutter
- [webview_flutter](https://pub.dev/packages/webview_flutter) (official)
- Material 3

## License

MIT — feel free to use and modify.

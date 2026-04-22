# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

This is a freshly scaffolded Flutter project intended to become a face liveness demo. As of now, `lib/main.dart` and `test/widget_test.dart` are still the default `flutter create` counter-app template — no liveness/camera/ML logic has been added yet. Treat the current contents as a starting point to be replaced, not as load-bearing code.

Note: `lib/main.dart` contains two dangling-member references (`.fromSeed(...)` and `.center`) that are missing their enclosing class names (`ColorScheme.fromSeed`, `MainAxisAlignment.center`). These will fail `flutter analyze` / build until fixed.

## Environment

- Dart SDK constraint: `^3.10.4` (from `pubspec.yaml`)
- Targets configured: Android, iOS, macOS, Linux, Windows, Web (all six platform folders exist from `flutter create`)
- Only runtime dependency beyond `flutter`: `cupertino_icons`
- Lints: `package:flutter_lints/flutter.yaml` via `analysis_options.yaml`

## Common commands

```bash
flutter pub get                      # install dependencies
flutter analyze                      # static analysis / lint
flutter test                         # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter test --name "Counter increments smoke test"  # run a single test by name
flutter run                          # run on the default attached device
flutter run -d chrome                # run on web
flutter run -d macos                 # run on macOS desktop
flutter build apk | ios | web | macos | linux | windows
```

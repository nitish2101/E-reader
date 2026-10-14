# Repository Guidelines

## Project Structure & Module Organization

This Flutter app targets Android tablets and supports PDF/EPUB books. `lib/main.dart` initializes the app. Shared themes, constants, and cache settings live in `lib/core/`. Models, Hive persistence, catalog providers, and downloads live in `lib/data/`. Screens, widgets, and BLoCs are grouped by feature under `lib/presentation/` (library, store, reader, settings).

Tests mirror these areas in `test/data/`, `test/store/`, and `test/reader/`; reusable fixtures live in `test/support/`. Android configuration is in `android/`, icon assets in `assets/icon/`, and verification notes in `docs/`. Existing `web/` assets do not establish browser support.

## Build, Test, and Development Commands

Use Flutter 3.41+ and Dart 3.10+, with Android SDK API 36 and an API 26+ device/emulator.

- `flutter pub get`: install locked dependencies.
- `flutter run`: launch on a connected device/emulator.
- `dart format lib test`: format Dart sources.
- `flutter analyze`: run static analysis and configured lints.
- `flutter test`: run the default offline suite.
- `flutter build apk --debug`: build a debug Android APK.
- `dart run build_runner build --delete-conflicting-outputs`: regenerate the checked-in Hive adapter after changing `BookModel`.

## Coding Style & Naming Conventions

Use two-space indentation and Dart formatting. Name files `snake_case.dart`, classes `UpperCamelCase`, and members `lowerCamelCase`; prefix private members with `_`. Follow `analysis_options.yaml`, which includes `flutter_lints` and prefers const constructors and collections. Keep networking and persistence in services/repositories and coordinate screen state through existing BLoCs/Cubits. Regenerate `book_model.g.dart` rather than editing it manually.

## Testing Guidelines

Use `flutter_test` for unit and widget tests. Name files `<component>_test.dart` and describe observable behavior in test names. Use fake HTTP responses and temporary directories; clean up resources. Cover relevant parsing, cancellation, download validation, and reader-position regressions. No numeric coverage threshold is configured.

Run focused tests with `flutter test test/data/book_download_service_test.dart`. Public-catalog checks are opt-in: `flutter test test/live_books_test.dart --dart-define=RUN_LIVE_BOOK_TESTS=true`. Verify native reader changes on Android and record device details and limitations in `docs/`.

## Commit & Pull Request Guidelines

History mixes concise descriptions and `feat:` messages. Write clear, imperative subjects; use `feat:` for additions or `fix:` for corrections where appropriate. Keep commits focused. PRs should explain behavior changes, link relevant issues, report checks performed, and include screenshots for UI changes.

## Data & Configuration Safeguards

Preserve Hive field identifiers and saved libraries/positions. Keep the store books-only. Validate downloads before publication and surface source failures. Configure catalog endpoints through `--dart-define`; retain TLS verification and exclude credentials, local books, and build artifacts from commits.

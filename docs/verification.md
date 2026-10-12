# Books reliability verification

Checked locally on 2026-10-12 using Flutter 3.47.7 / Dart 3.13.5.

## Automated checks

- Static analysis: no issues.
- Latest offline suite: 68 passing tests; three opt-in network tests skipped. See [catalog repair verification](catalog-reliability-verification.md) for the latest source fixes, live checks, and Android build.
- Tests cover overlapping and cleared searches, source outages and partial results, pagination recovery, book-only parsing, bounded retries, alternate links, relative download controls, compressed responses, active cancellation and cleanup, actual PDF readability, EPUB structure and escaped chapter paths, successful library publication, distinct editions, filename collisions, Unicode metadata, old Hive schema compatibility, and reading progress.
- Widget checks cover offline app startup, recoverable store errors, and phone/tablet store layouts.
- Generated Hive adapter is included and the dependency lockfile is tracked.

## Live catalogs

The opt-in Gutenberg test searched for *Pride and Prejudice* and successfully downloaded and validated a 24,836,548-byte EPUB in earlier runs during this work. Later runs encountered HTTP 504 and HTML responses rather than book files, including after retries and alternate EPUB links were added. The latest Gutenberg download test failed with a connection error. Anna's Archive requests returned HTTP 403 on this network. The repaired LibGen `.li` search now passed live, returning 16 supported book files. Standard Ebooks search and a validated 831,959-byte EPUB download passed. LibGen file downloads were not verified. See [the latest catalog report](catalog-reliability-verification.md).

These are external availability limits; deterministic tests verify recovery behavior rather than asserting that every public catalog is reachable. Successful results appear as sources finish. Unavailable sources are shown explicitly, and incomplete/invalid files are removed.

## Android tablet verification

The Android SDK is now installed for this workspace. The combined app built,
installed, and ran on an Android 16 / API 36 arm64 Pixel Tablet emulator at
2560 x 1600. The normal catalog build has been restored after controlled server
checks. See [the combined emulator report](emulator-verification.md) for native
checks, live catalog results, and remaining reader defects. Captured screenshots
and logs are retained locally and excluded from the repository.

## Reproduce

```sh
flutter pub get
flutter analyze
flutter test
flutter test test/live_books_test.dart --dart-define=RUN_LIVE_BOOK_TESTS=true
flutter build apk --debug
```

All repository changes remain local; no remote branch or pull request was created.

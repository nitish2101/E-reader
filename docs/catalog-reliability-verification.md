# Catalog repair verification — 2026-10-12

Verified using Flutter 3.47.7 / Dart 3.13.5 on the development host.

## Findings and changes

| Source | Live finding | Change / verification |
| --- | --- | --- |
| Anna's Archive | `.gl`, `.pk`, and `.gd` search requests returned HTTP 403 with a DDoS-Guard page. | Detect challenge pages and unreadable row layouts as outages. Report HTTP/access failures; pause failed mirrors for two minutes. Automatic search remains blocked on this host. |
| LibGen | Legacy `.is`, `.rs`, and `.st` endpoints timed out. `.li` returned a modern catalog. | Default to `.li/index.php`, submit only book topics, parse its nine-column table, remove edition footnote markers, and read JavaScript pagination. Live app-provider search returned 16 supported book files with pagination. |
| Standard Ebooks | Public HTML search works; OPDS returned HTTP 401. EPUB URLs initially returned a download-start page. | Add a selectable source enabled by default, with EPUB filtering, metadata, covers, pagination, and transient retry. Resolve its immediate same-origin book redirect. Live search and download validated an **831,959-byte** EPUB of *Pride and Prejudice*. |
| Gutenberg / Gutendex | Gutendex search returned a valid JSON catalog. EPUB download failed with `connectionError` after alternate links/retries in the latest live run. | Retain existing retries and validation. Popular browsing now queries Standard Ebooks alongside Gutenberg, including subsequent pages. Gutenberg download availability is not established in this run. |

Archive searches prefer the last successful mirror. Failed mirrors cool down for two minutes; the store's Retry action clears that cooldown immediately. A new query does not repeatedly contact known failed mirrors during the cooldown. Successful catalogs continue to produce partial results independently.

The download resolver follows immediate HTML refreshes only to same-origin HTTP(S) PDF/EPUB files, within the existing depth, URL-count, timeout, and validation limits. It does not execute scripts, follow donation/navigation refreshes, or solve anti-bot challenges.

## Automated checks

- `flutter analyze`: **no issues**.
- `flutter test`: **68 passed**, three opt-in live tests skipped.
- Opt-in live suite: **two passed, one failed**. Standard Ebooks search/download and LibGen search passed; Gutenberg EPUB download failed as described above.
- `flutter build apk --debug`: **passed**. Output: `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: passed.

New regression coverage includes modern LibGen parsing/routing/pagination and zero-file responses, challenge/layout detection, repeated Anna query filters, working-mirror preference, immediate Retry after cooldown, Standard Ebooks metadata and format filtering, and same-origin download-start redirects. Existing library, reader, cancellation, publication, and responsive store tests also passed.

The Android build emitted compatibility advisories for the existing Gradle/AGP/Kotlin versions. It completed successfully. This run did not install the APK or perform new emulator/device UI checks.

## Reproduce

```sh
flutter analyze
flutter test
flutter test test/live_books_test.dart --dart-define=RUN_LIVE_BOOK_TESTS=true
flutter build apk --debug
```

To check a source independently:

```sh
flutter test test/live_books_test.dart --dart-define=RUN_LIVE_BOOK_TESTS=true --plain-name 'live Standard Ebooks'
flutter test test/live_books_test.dart --dart-define=RUN_LIVE_BOOK_TESTS=true --plain-name 'live LibGen'
```

Only public-domain book downloads were attempted. LibGen's catalog was tested without downloading its files. Availability is specific to this host/network at verification time; Standard Ebooks and Gutenberg principally supply classics and are not replacements for every modern title. Changes and the APK remain local.

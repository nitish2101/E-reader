# E-Reader

A books-only Android tablet reader for PDF and EPUB, with an offline library, saved reading positions, and online book discovery.

## Book features

- Import PDF/EPUB files without overwriting books that share a filename.
- Read EPUB title/author metadata, including Unicode, and extract local covers.
- Search titles and authors across Anna's Archive, LibGen's book catalog, Project Gutenberg via Gutendex, and Standard Ebooks.
- Browse popular classics from Gutenberg and Standard Ebooks. These sources mainly offer EPUB classics; they do not cover every modern title.
- Select sources and PDF/EPUB formats explicitly. Your preferred download format sorts matches first without hiding other formats.
- Show results as responsive sources finish; explain unavailable sources separately from genuine empty results.
- Cancel superseded searches and downloads, retry failures, cache successful searches for 15 minutes, and deduplicate files across pages.
- Retry temporary server failures once, try alternate download links and Gutenberg EPUB editions, resolve ordinary download landing pages, and validate books before adding them to the library.
- Prefer the last working archive mirror and pause failed mirrors for two minutes. Retry immediately rechecks paused mirrors. LibGen defaults to its modern `.li` book catalog, with legacy mirrors as fallbacks.
- Resolve immediate same-site PDF/EPUB redirects used by Standard Ebooks' download-start page.
- Keep search results, filters, and pagination while downloads run.
- Preserve existing Hive libraries and reading positions. Optional catalog IDs keep distinct editions separate.
- Use local system fonts so opening the app does not require downloading fonts.

Comics, manga, manhwa, magazines, musical scores, and unsupported formats such as CBZ/CBR are excluded from the store. The cloned main branch had no separate comics/manga reader or navigation feature to remove. Existing library entries are preserved.

## Setup and run

Requirements: Flutter **3.41+**, Dart **3.10+**, an Android SDK with API 36, and an Android device/emulator on API 26+. The checked-in dependency lockfile was verified with Flutter 3.47.7 / Dart 3.13.5.

```sh
flutter pub get
flutter run
```

The Hive adapter is included, so a clean checkout does not require code generation. If changing `BookModel`, regenerate it:

```sh
dart run build_runner build --delete-conflicting-outputs
```

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug
```

The default tests use deterministic local fixtures and fake HTTP responses; they do not require the public catalogs to be online. PDF tests load the real PDFium library installed by the dependency's native build hook.

See [verification notes](docs/verification.md) for the checks performed and their limitations.

Opt-in live search and download check:

```sh
flutter test test/live_books_test.dart --dart-define=RUN_LIVE_BOOK_TESTS=true
```

This checks LibGen's modern catalog and searches Gutenberg and Standard Ebooks for *Pride and Prejudice*. Both EPUB checks download into temporary directories, validate the actual files, and remove them. Source availability can vary by network and country. See [catalog repair verification](docs/catalog-reliability-verification.md) for current results.

## Source configuration

Catalog domains can move or be blocked. Override the first Anna/LibGen mirror, use your own Gutendex server, or configure the Standard Ebooks catalog endpoint at build time:

```sh
flutter run \
  --dart-define=ANNA_MIRROR=https://your-anna-mirror.example \
  --dart-define=LIBGEN_MIRROR=https://your-libgen-mirror.example \
  --dart-define=GUTENDEX_URL=https://your-gutendex.example/books/ \
  --dart-define=STANDARD_EBOOKS_URL=https://standardebooks.org/ebooks
```

Use a trusted mirror that exposes the expected catalog layout. The app retains normal TLS verification. It reports access challenges, changed layouts, and timeouts rather than presenting them as “no books found.” It cannot automate login, CAPTCHA, or paid/waiting download screens.

On 2026-10-12, the configured Anna's Archive mirrors returned DDoS-Guard HTTP 403 challenges on this host, and the legacy LibGen `.is`, `.rs`, and `.st` endpoints timed out. The repaired `.li` catalog returned real book results. Standard Ebooks search and an 831,959-byte EPUB download passed validation. Enabling Standard Ebooks in the source controls provides independent EPUB discovery when the archive sites are unavailable. Its authenticated OPDS feed is not used.

Searches have a 25-second deadline per source. Downloads have a 3-minute overall deadline, 25-second idle timeout, and 300 MB size limit. Interrupted/invalid files are removed; successful files are published atomically. Downloads restart from a clean temporary file rather than using the previous corrupting range/resume behavior. PDF validation checks document readability; EPUB validation checks its package, manifest, and chapter references. Password-protected PDFs require an unprotected copy for import.

## Main components

- `lib/data/services/book_search_providers.dart`: catalog parsing and provider HTTP requests.
- `lib/data/services/book_download_service.dart`: link resolution, transfer, cancellation, and publication.
- `lib/data/services/book_file_validator.dart`: PDF/EPUB validation.
- `lib/data/repositories/store_repository.dart`: source aggregation, deadlines, search cache, and deduplication.
- `lib/presentation/store/bloc/`: independent search/download state and concurrency handling.
- `lib/data/repositories/book_repository.dart`: local library, imports, covers, and reading progress.

This is an Android app. Existing web assets do not establish support for browser-based file storage or reading. Download and use books you are entitled to access.

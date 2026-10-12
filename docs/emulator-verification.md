# Combined Android tablet verification

Checked on 2026-10-12 against the current combined working tree, including the
changes from the linked **Improve reader scrolling and bar** chat. These checks
found two remaining reader defects; this is not an all-bugs-fixed claim.

## Environment and build

- Pixel Tablet emulator, Android 16 / API 36, arm64, 2560 x 1600 at density 320.
- Flutter 3.47.7 / Dart 3.13.5; debug APK targets android-arm64.
- Fresh `flutter analyze`: no issues. Fresh offline tests: **56 passed**, one
  explicitly opt-in live network test skipped.
- Normal APK built and installed successfully. Installation updated the existing
  app without clearing its library. Original books and saved positions survived.
- Controlled-server APK used only temporary compile-time catalog URLs. The final
  APK restores the normal public catalogs; the controlled server was stopped.
- Final installable APK: `build/app/outputs/flutter-apk/app-tablet-debug.apk`.

## Automated regressions

The 56 passing tests cover the earlier store/import/download work and all twelve
reader regressions from the linked chat:

| Area | Covered regressions |
| --- | --- |
| Search | Older/cleared requests cannot replace newer state; debounce cancellation; source deadlines/outages; partial results; unknown layouts; bounded retries; cache behavior. |
| Results | Book-only parsing, nested metadata, EPUB/PDF filtering, unsupported neighboring records, source errors distinct from no matches, tablet layout. |
| Pagination | Existing results/page preserved on failure; retry; filtered empty pages retain navigation. |
| Download | Alternate and relative links, invalid HTML responses, bounded server retries, compressed responses, cancellation/cleanup, library publication exactly once, independent query state. |
| Library | Valid PDF and EPUB structure, readable chapters and escaped paths, invalid imports, filename collisions, Unicode metadata, distinct editions, old Hive compatibility, clamped progress. |
| Reader | Readiness before seeking; drag preview isolation; actual location saved during drag/backgrounding; progress animation does not rebuild reader; centre-ending gestures; initial styles; seek completion/failure/disposal; stale and reordered native locations. |

Widget reader tests replace the native WebView. They do not exercise every timer
inside the third-party viewer; the selection-disposal defect below was therefore
visible only in the native checks.

## Native store and download checks

Used controlled HTTP responses through the actual Android app, download service,
native PDF validator, filesystem, and Hive library. The responses supplied valid
EPUB/PDF books, comic/unsupported entries, HTML masquerading as book files, delayed
transfers, and HTTP 503 failures.

| Case | Observed result |
| --- | --- |
| Book-only catalogs | EPUB/PDF records displayed; comic and AZW3 records excluded. |
| Successful PDF | Get changed to Library; book appeared in the library and rendered readable text in the native PDF viewer. |
| Cancel active EPUB | At 1%, Cancel restored Get and displayed Download cancelled; no `.part` file remained and no Cancellation check 2 library entry appeared. |
| Transient download failure | First file GET returned 503; second GET succeeded. Retry download check appeared in the library. |
| Total catalog outage | Search unavailable plus Retry search; HTTP 503 source explanation shown instead of no-matches copy. |
| Next-page failure | Existing book stayed visible; Retry loading more appeared. Retry appended Second page EPUB. |
| Filtered empty page | EPUB-only search on a PDF-only page showed Check the next page; it reached Next page check EPUB. |
| Invalid first link | Both EPUB and PDF landing pages offered HTML binary responses first. Those were rejected; valid alternate links downloaded successfully and both books entered the library. |

Controlled requests are retained locally in
`docs/emulator-evidence/controlled-requests.jsonl`. Captured logs and screenshots
are excluded from the repository.
The first Cancellation check fixture completed before the harness located the
correct Cancel control; it is a test book, not evidence of a cancellation failure.

## Native EPUB checks

Used the downloaded six-chapter fixture, 80 paragraphs per chapter. Gestures were
native Android taps/swipes; WebView inspection read actual CFI, location, styles,
selection, and scroll offset.

| Case | Observed result |
| --- | --- |
| Continuous scrolling | Offset advanced from 0 to 278.5 and then 550.5 CSS pixels. Location and visible progress advanced from 0.0% to 1.1%. |
| Progress drag | Native slider drag displayed chapter 4 at 59.6%, CFI `epubcfi(/6/8!/4/90/1:134)`. |
| Close and reopen | Library showed 59.6%; reopening restored the same CFI and visible chapter 4 paragraph 44. |
| Font/theme controls | Applied 18-to-20px font and dark-to-light text colors; text remained scrollable. Position preservation on typography reflow is defective, as detailed below. |
| Centre-ending swipe | Controls remained hidden; subsequent centre tap revealed them. |
| Text selection | Native long press selected the word progress, confirmed through the WebView selection state. |
| Normal build resume | After restoring the normal APK, the fixture reopened at its newly saved CFI and 58.4% position. |

Screenshots of the rendered PDF, reopened EPUB, and native selection are
retained locally in the ignored `docs/emulator-evidence/` directory.

## Public catalog check

The restored normal build searched for **Pride and Prejudice**. Gutenberg returned
three book files even while Anna's Archive and LibGen were unavailable/blocked.
The app displayed both source errors while keeping the Gutenberg results usable.
The live search screenshot is retained locally in `docs/emulator-evidence/`.

The first real download attempt was canceled when the verification switched away
from Store. `StoreBloc.close()` cancels active transfers when leaving that route;
downloads currently require Store to stay open. On repeating with Gutenberg
selected, the search timed out before a second download could begin. Retry search then recovered
and returned the three book files. Keeping Store open, the subsequent real EPUB
download **succeeded** (24,836,548 bytes): Get changed to Library and the app
displayed Added Pride and Prejudice to your library. The valid book was published
to Hive; no `.part` file remained. It opened in the native EPUB reader, rendered
its illustrated cover, and reported CFI `epubcfi(/6/2!/4/1:0)`. The normal app and
emulator were left running with this book open.
Screenshots of the completed download and opened book are retained locally in
`docs/emulator-evidence/`.

## Remaining defects and limits

1. Changing font size and theme together moved the visible reading paragraph
   instead of preserving its CFI. The 18-to-20px/light-theme change moved chapter 4 paragraph 44
   back to paragraph 35, with progress changing from 59.6% to 58.4%. Typography
   application works; exact position preservation across reflow is not fixed.
   Font and theme were changed together, so the individual cause was not isolated.
2. Closing soon after a native text-selection long press triggers repeated
   disposed-WebView exceptions for several seconds. In `flutter_epub_viewer`
   1.2.8, the long-press callback starts a periodic selection-check timer which
   continues after the WebView is disposed. The app stayed running, but this is
   a real dependency lifecycle defect. A representative native stack trace is
   saved locally in `docs/emulator-evidence/selection-disposal-error.txt`.

These are emulator behavior checks, not a physical-tablet scrolling-feel or
frame-time benchmark. Public catalog availability is external and varies;
successful controlled responses establish the app's recovery and validation
behavior, not universal access to every provider or title.

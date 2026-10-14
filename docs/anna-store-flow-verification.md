# Anna Store handoff verification

Checked on 2026-10-14.

## Behavior

- A readable Anna search page returns its books to Store automatically after
  user verification, including pages whose content updates after loading.
- Store Get starts the app downloader for Anna books. It resolves free partner
  links, validates the EPUB/PDF, and publishes it to the library automatically.
- Search and download requests reuse the verified browser user agent and native
  cookies, with cookies scoped to each destination. The verified mirror becomes
  preferred and is removed from the failed-mirror cooldown.
- A blocked Anna download requests its exact verification page. Once a download
  link becomes available, the app returns to Store and resumes. A failed resume
  shows an error instead of reopening verification indefinitely.
- Verified search results retain pagination and warnings from other sources.

## Automated checks

- Flutter 3.47.7 / Dart 3.13.5.
- The initial regressions reproduced the manual-result handoff, unconditional
  browser download route, unused search session, and missing free partner link
  resolution before implementation.
- Final `flutter analyze --no-pub`: no issues.
- Final `flutter test --no-pub`: 143 passed, three skipped opt-in live checks.
- Normal public-catalog arm64 debug APK built successfully at
  `build/app/outputs/flutter-apk/app-debug.apk`.
- Checked cookie isolation across search redirects, exact blocked-download URL,
  single verification consumption, bounded blocked resume, and file cleanup.

## Native Android checks

- Emulator `emulator-5576`, Android 16 / API 36, arm64, 2560 x 1600.
- Used the separate application ID `com.ereader.annaverification` and temporary
  compile-time catalog endpoints pointing to a local controlled server. The
  normal application library was untouched.
- The fixture verification page explicitly identified itself as a local test,
  not a real CAPTCHA. No real anti-bot challenge was automated.
- Completing the fixture search step returned to Store without pressing
  “Use search results”; both EPUB result cards appeared with pagination.
- Get on “Smooth Store Book” requested the detail page, free partner page,
  and EPUB file using the verified session. Store displayed the Library action
  and the book appeared in the library without a manual import.
- Get on “Verified Download Book” encountered a separate download check. After
  completing the fixture step, a JavaScript-delayed link appeared. The app
  returned automatically, downloaded the EPUB, and added the second book.
- The library contained both titles. The downloaded EPUB opened and rendered
  its chapter in the native reader. The books directory contained two final
  EPUB files and no `.part` files.
- A subsequent search for “second” stayed in Store and returned both results.
  Server requests carried the verified session; verification was not reopened.
- Rebuilt the normal APK after native verification to restore public endpoints.

## Limits

These checks prove the app handoff and native download/import behavior against
controlled pages. They do not prove successful session reuse against Anna's live
anti-bot deployment or every partner server. Anna documents separate browser
verification and waitlists for free downloads in its
[FAQ](https://annas-archive.gl/faq#slow). Those checks still require the user;
the app takes over when the source makes the download available.

Session registrations last for the current repository lifetime. An app restart
may require opening verification again even when the native browser retains
cookies.

## Integration with the tablet redesign

On 2026-10-14, combined the Store fixes in `ffa4408` with tablet redesign
`3d04522` on local `main`. The overlapping Store screen keeps the redesigned
cards, filters, scroll handling, retained tabs, and deferred notices. Get uses
the app downloader for Anna books; only a blocked transfer requests verification.
Queued verification opens when Store is active, so a background download cannot
interrupt another tab. A verified resume retains its download metadata and the
existing limit on reopening verification.

Reviewed the Store callbacks, active-tab visibility, browser-result handling,
download metadata/progress/cancellation, library refresh subscription, filters,
pagination, EPUB controls, and saved-position boundaries. The redesign does not
change the Store repositories, download services, BLoC, or library persistence.

Combined-code checks: 143 existing Flutter tests passed, three opt-in live tests
skipped, all three existing JavaScript reader bridge checks passed, and static
analysis found no issues. The combined Android release APK built successfully.
No new tests or dependencies were added for this merge.
The native evidence above belongs to the earlier Store build; the combined UI
was reviewed in source and checked with the existing tests, without repeating
the native/live provider journeys.

## Live Anna download check — 2026-10-15

Tested the user's reported EPUB, **Project Hail Mary : a novel** by Weir, Andy,
against the real Anna deployment on the same Android 16 / API 36 tablet emulator.
The user completed the source's search and download verification checks manually.
No CAPTCHA was automated, and no certificate check was disabled.

The live check exposed and reproduced these failures before fixes:

- Partner redirects exhausted the resolver's URL budget without asking for the
  actual slow-download page's browser check.
- Empty and fragment-only Save/Read more anchors were mistaken for downloads on
  slow-download pages, causing the browser to return before the timer finished.
- Another partner supplied its file URL as copyable text beside a clipboard
  button, which the link resolver did not recognize.
- A failed verified partner could not continue to another partner. The flow now
  remembers verified page paths, selects an untried page, and permits at most
  three verified pages. A repeated page cannot reopen merely by changing query
  parameters. A readable detail page follows its slow-download link inside the
  verification view rather than prematurely returning that page as a file.

On this test network, the first generated HTTPS file host failed certificate
hostname verification. Anna's alternate partner supplied a reachable file URL.
The app downloaded it and added the original title/author to Library without
copying a URL, using an external browser, or manually importing a file.

The final private book file contains **9,810,807 bytes**, and its MD5 is
`53739932cb4ff9d635edd98f886818a4`, matching the catalog file exactly. The library
increased from four to five books and retained the existing books/positions.
There were no `.part` files left after completion. The downloaded book remained
available after restarting the emulator and installing the final release APK.

Native reader check: the release APK rendered the cover and Chapter 1, and its
location bridge reported a valid chapter CFI and progress. The software-rendered
emulator initially loaded slowly and timed out during a chapter jump. Repeating
with `-gpu host` on the same emulator data and unchanged APK rendered the chapter
without a recovery overlay or reader errors. This is emulator evidence, not a
physical-device performance claim. No reader implementation was changed.
After scrolling, closing normally, and reopening, the reader restored the same
chapter CFI, progress, and 45.765625-pixel viewport offset. Library showed 0.4%
for the downloaded book while the existing Pride and Prejudice position stayed
at 47.6%.

Final checks: 149 Flutter tests passed, three opt-in live tests skipped; static
analysis reported no issues; the normal release APK built successfully. Six
focused regressions cover the live resolver failures and bounded verification
fallback. Diagnostic tracing and browser auto-return pauses were removed.

The release APK uses the repository's existing debug signing configuration; a
dedicated production signing key is not configured. Signed URLs, cookies, the
downloaded EPUB, and screenshots containing book text are excluded from commits.

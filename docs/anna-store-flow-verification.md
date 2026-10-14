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

# Reading statistics

Branch: `codex/reading-statistics`, based on main `a07ad93`.

## Design and data boundaries

The Library app bar has a labelled Stats button. The dashboard shows total recorded time, today, the current Monday-based week, a seven-day chart, and expandable book rows with cover, saved progress, last recorded read, average session duration, and session history. Totals retain time for deleted books, with an explanation when applicable.

All statistics use a separate local Hive `readingStatistics` box. Existing BookModel adapter field IDs, library data, and progress are unchanged. No account, server, or tablet synchronization is involved. Tracking begins with this feature; existing last-read timestamps do not create historical reading durations.

A session stores an ID, book ID, and counted intervals with UTC start/end timestamps and the local calendar-day key at recording time. Intervals split at local midnight and consecutive checkpoints on the same day coalesce. Calendar-day keys retain the recorded day if the device later changes time zone. Duration uses a monotonic stopwatch; wall-clock edits cannot inflate elapsed time. UTC boundaries are anchored when each active session begins; a clock/time-zone edit during that session is reflected when the next session begins.

Only one reader lease can own timing. Opening another reader closes the previous lease; late callbacks from old readers cannot restart it. Loaded state, application lifecycle, current route, drawer/modal visibility, and explicit navigation gate recording. Inactive, hidden, paused, detached, reader disposal, and loading all pause timing. Only genuine input resets inactivity; automatic relocations, progress restoration, and font reflows do not reset it.

The default idle cutoff is five minutes, adjustable to 2, 5, 10, or 15 minutes on Stats. Expired idle time is never filled in on the next interaction. Timing is an estimate: a stationary reader may still be reading, and an active reader may be skimming. Navigation and inactivity exclusion do not prove comprehension.

Full immutable session snapshots replace the same session ID. A 15-second checkpoint and pause/close saves limit typical interruption loss to the most recent checkpoint interval, plus filesystem latency. Writes are serialized; failed snapshots remain pending for retry without adding time twice. Recovery reloads stored history and preserves newer pending snapshots. Statistics storage errors are shown with Retry and do not prevent library access. Abrupt process termination during an unsuccessful disk write can lose unsaved data.

## WPM feasibility

No numeric WPM is implemented. The installed flutter_epub_viewer 1.2.8 exposes `extractText(startCfi, endCfi)`, but its JavaScript `makeRangeCfi` uses the starting CFI's spine base for the whole range. This cannot reliably represent traversed text across chapter boundaries. Text extraction also uses one shared asynchronous completer and cannot establish that displayed text was actually traversed through ordinary reading rather than a seek, reflow, or skimming. Percentage indexing supplies no reliable word count. PDF page callbacks likewise do not establish words traversed; scanned PDFs lack extractable text.

Book rows therefore show **Estimated WPM: Unavailable** with a format-specific reason. There is no supported pace-measurement path collecting samples, so “Collecting data” would be misleading in this implementation. A future supported path should show that state until it has sufficient validated text/duration evidence, exclude seeks/chapter jumps/rapid skims, and only then display an estimated WPM.

## Automated verification

- Flutter analysis: no issues.
- Full offline Flutter suite: 98 passed, 3 opt-in live-catalog tests skipped.
- Debug Android APK built successfully from the final production entrypoint. Existing Gradle/AGP/Kotlin and Java source-level deprecation warnings remain; no toolchain upgrades were made.
- Timing regressions cover readiness, idle cutoff/resumption, adjustable threshold, system clock edits, midnight and Monday allocation, overlapping lifecycle events, lease revocation/reopening, periodic snapshots, overlapping flushes, persistent reload, failed writes/flush recovery, unavailable startup, restored history, and pending overrides.
- Widget regressions cover background/screen-lock lifecycle transitions, covered pages and popups, pointer wakeup, Stats navigation without progress mutation, chapter loading despite drawer-close callbacks, chapter errors, and cancelled/superseded PDF animation futures.
- Existing EPUB scrolling, slider seek, restoration, progress ordering, and cached-reader rebuild checks continue to pass.

## Android verification scope

Native checks use **emulator-5554**, Android 16, ARM64, 2560×1600. A separate review package `com.ereader.app.statisticsreview` contains two temporary local EPUB/PDF fixtures; production retains `com.ereader.app`. No other package was cleared, uninstalled, or replaced. The fixture entrypoint and package-ID change were temporary and are not in the committed app.

Production APK: `build/app/outputs/flutter-apk/app-debug.apk`.
Review APK: `/private/tmp/ereader-statistics-review-debug.apk`.
Production SHA-256: `810c672485b945dd423a598315a05689bad26264e27e81efb510f842837e9e41`.
Review SHA-256: `23508cde160291a9346fa9476984135471d1d57edcaba719eba7fdc77dbcbd26`.

Native results:

- Library shows the labelled Stats button; dashboard and idle-threshold menu render on the tablet display. The review setting was changed to two minutes without changing any other package.
- The local EPUB fixture loaded in the existing continuous reader. A periodic saved session recorded **16.112 seconds** before backgrounding.
- Exported review-package snapshots retained exactly **16.112 seconds** while backgrounded. Resume began a separate session after an excluded **58.529-second** gap.
- A second session recorded **80.039 seconds**. When another chat brought `com.ereader.reliability` to the foreground, the review app paused and its saved total stayed at **96.151 seconds**. Its process log confirms the visibility transition. No time from the other build was attributed to this check.
- The shared emulator switched packages before the uninterrupted two-minute idle trial completed. Therefore the full native idle cutoff/wakeup and native PDF slider checks are **not verified**. Their logic is covered by automated regressions. No further foreground interaction was performed after detecting concurrent use.
- No native numeric WPM claim is made.

The review APK was built before the final installation-metadata Retry refinement; its dashboard, lifecycle, timing, and seek code match the final production code. That last storage-error refinement is covered by automated regression and the final production APK build.

Screenshots and raw captures remain ignored in `docs/emulator-evidence/` and `/private/tmp/ereader-statistics-*`.

No physical Android tablet was connected. Physical screen-lock behavior, OEM power management, and long-running everyday use remain unverified on real hardware. Screen lock is covered by simulated lifecycle regression checks; the shared emulator is not locked for this task.

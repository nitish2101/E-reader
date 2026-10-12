# EPUB chapter loading and reusable preparation

Status: revised after constructive/adversarial agent review and judge review.
Architecture recommendation, not a measured fastest implementation.

## Goal and agreed scope

Make EPUB books open promptly at their saved reading position and remain smooth
while scrolling. The user approved these four improvements:

1. Extract and cache EPUB files during import/download using background processing.
2. Open metadata and the saved chapter first; fetch chapter text and images on demand.
3. Preload the next chapter and release distant chapter views.
4. Generate reading-position data separately and cache it for subsequent opens.

Preserve chapter navigation, the progress slider, CFI resume, themes, fonts,
selection, dictionary lookup, and the existing library. PDF loading is outside
this change. Existing uncommitted reader/catalog changes must be preserved.

## Current implementation and evidence

`EpubReaderScreen` uses `EpubSource.fromFile` and the continuous epub.js manager.
The installed `flutter_epub_viewer` version is 1.2.8. Its file loader reads the
whole EPUB; `loadBook()` uses `data.join(',')` to embed every byte in JavaScript.
The WebView constructs another byte array and opens the ZIP in epub.js.

Archived epub.js loading also waits for resource replacement: every non-HTML
asset is inflated and converted to a blob URL before `book.opened` resolves.
Removing the decimal byte string alone would leave this eager work in place.

The continuous manager already creates neighboring chapter views and destroys
offscreen views. This behavior should be retained. However, destroying an iframe
does not unload the corresponding Section's document and serialized output;
section-cache retention must also be measured and controlled.

The viewer calls `book.locations.generate(1600)` on every open. This queues all
linear spine sections, loads/parses their text, and unloads each section after
processing. It is separate from first display, but its result controls percentage
seeking and the reader's acceptance of progress events.

The current emulator library contains a 24,836,548-byte Pride and Prejudice EPUB.
A diagnostic reopen remained on the loading overlay for over 50 seconds. This
establishes the observed problem; it does not establish a complete timing
breakdown or prove the transfer accounts for all of that delay.

## Options considered

- **Recommended first candidate: extracted package plus native resource serving.** Removes whole-ZIP
  transfer and JavaScript ZIP processing, while retaining epub.js, its CFI format,
  continuous chapter views, and the existing controller callbacks. Android's
  WebViewAssetLoader can serve the files without a loopback socket server.
- **Cold-open challenger: file-backed ZIP plus worker resource server.** Open
  the archive directory and OPF, inflate requested entries into a file cache,
  then stream them to the WebView. It avoids awaiting full extraction for
  immediate/migrated opens, at the cost of request scheduling, cache coordination,
  and server lifecycle. Compare this if full extraction dominates cold latency.
- **Direct ZIP URL loading.** Removes the decimal byte string, but the installed
  engine still requests the entire ZIP and opens it in JavaScript. This does not
  achieve chapter-by-chapter resource loading.
- **Replace the EPUB engine.** Broadens scope to selection, styling, navigation,
  and saved-position compatibility. It is unnecessary for this change.

## Extraction cache

Add an EPUB preparation service using the existing archive/XML dependencies.
Consolidate EPUB validation, OPF metadata, cover extraction, and cache preparation
into one worker-owned archive operation. Do not add a fourth import ZIP pass
or preserve redundant EPUB validation in download and library publication.
Retain validation before accepting a book and leave PDF validation unchanged.
Use file-based input, without sending archive bytes through the UI isolate.

Store extracted files in application cache storage. Keep the original managed
EPUB as the authoritative copy. Each cache entry records its source path, size,
modification timestamp, preparation revision, and resolved OPF relative path.
Managed copies are immutable in ordinary app operation; changed source stats or
a preparation revision invalidate the cache. A cache directory disappearing
because Android reclaimed it is handled as a cache miss.

Use a staging directory and publish only a fully prepared entry. Deduplicate
simultaneous preparations of the same source. Reject paths outside the cache
root, symlinks, duplicate normalized paths, and inconsistent package references.
Bound entry count, aggregate extracted bytes actually written, and entry sizes.
Use a global reclaimable cache budget, with active-reader leases so eviction
does not remove files during a read. Failed/interrupted preparation removes
staging files and does not mark the cache as valid. Deletion/invalidation fences
late preparation publication so a removed book cannot recreate its cache.

Audit imports/downloads after their managed file is complete. Publish the valid
library entry when metadata/cover audit is complete, while remaining extraction
prewarms in the worker. Deduplicate this prewarming with an immediate reader open.
An immediate tap must not queue behind unrelated background book preparations.
Track absent, preparing, ready, and failed preparation states and permit retry.

Existing library books prepare on their first open. Warm opens validate the small
cache manifest and source stats, then reuse the cache. Deleting a book removes
its preparation and position cache after any active-reader lease is released.
Full extraction remains a cold-open cost in the native-files candidate, even
with nonblocking library publication; measure this explicitly. If it dominates
cold-open latency, select demand extraction/resource serving instead.

## Resource loading and viewer adapter

Use a repository-owned, narrowly patched copy of `flutter_epub_viewer` 1.2.8,
preserving its license and recording the upstream version and patch changes.
Do not edit the temporary pub cache as the shipped implementation.

Add a package source that supplies an OPF URL, rather than EPUB bytes. For the
prepared-files candidate, use Android WebViewAssetLoader to mount viewer assets
and only the active prepared book on the reserved appassets HTTPS origin.
The URLs look web-based but resources are served by native Android file handlers.
Keep resources off the Dart method channel, including images/fonts.

The installed flutter_inappwebview_android 1.1.3 internal-storage handler's
`toMap()` recursively calls itself. A temporary Flutter probe reproduced the
StackOverflowError and verified an app-local serialization-only subclass can
emit the native handler map. This avoids assuming the unmodified handler works
or requiring a second dependency fork. Actual native requests, MIME handling,
and lifecycle still require Android verification before selection.

For demand extraction, a worker-isolate loopback server is a viable challenger:
keep a file-backed archive stream alive for the reader session, find entries by
normalized path, inflate only requested resources into atomic cache files, then
stream them. Request duplicates share one extraction; foreground resources take
priority over optional prewarming. Bound memory and close source streams on
session disposal. Generic Dart CustomPathHandler sends resource bytes across the
method channel and is not equivalent to native streaming.

The adapter passes a small configuration object to JavaScript. epub.js opens the
OPF directly with explicit `replacements: 'none'` and requests XHTML, CSS, images,
and fonts through resolved URLs. Do not run global asset replacements or enable
epub.js offline storage substitutions on this path. The source must bypass
`epubData` and whole-book `Uint8Array` creation.
Original EPUB spine ordering, resource paths, and CFI construction are retained.

Start the resource session only when its required package metadata is valid and
its transport can serve requested resources. Release it when the reader is
disposed, and suppress late native/JavaScript callbacks after closure.
Errors preparing/opening a book and renderer termination must produce a retryable
reader error instead of leaving the loading overlay indefinitely.

## First display and chapter lifecycle

Display the saved CFI immediately after package metadata is available; use the
first readable spine item when no saved CFI exists. First display hides the
opening overlay without waiting for the full-book position index.

Retain the continuous manager's adjacent-chapter loading and view trimming.
Verify that the next chapter is fetched as the reader approaches the boundary,
and distant displayed chapter views are destroyed. Also unload retained Section
documents/serialized output only when that section has no active rendering,
selection/search, or indexing work. Do not keep all chapter DOMs alive or unload
sections that another operation is using. A single unusually large chapter can
still be costly; splitting chapter
HTML is outside this iteration because it could change saved CFI semantics.

## Position indexing and persistence

On a warm open, fetch and validate the small cached locations array. Restore it
with `book.locations.load` before enabling percentage seeking. Associate it with
the exact preparation entry, engine revision, and the 1600-character interval.

On a cache miss, let first display and a paint opportunity finish before starting
index generation. Use the engine's existing sequential section queue, which
already yields between chapters. Prioritize active reading over full-book work;
one huge chapter can still cause synchronous DOM traversal contention.
Persist the completed index atomically through the Dart bridge. Failed/partial
indexes are ignored and regenerated; they do not prevent reading.

Until indexing finishes, disable percentage seeking and retain the previously
saved percentage. Persist new visible CFIs without replacing that percentage
with an invalid or placeholder zero. Once the index is ready, refresh the visible
location and resume the existing ordered progress bridge. Exiting or pausing
must save the confirmed CFI even if indexing is incomplete.

Prewarming starts during import/download. Index generation uses DOM text and CFI
semantics, not page-layout measurements. It runs after first display and is reused
on subsequent opens; a second hidden WebView during every download is not needed.

## Expected touched areas

- Add preparation/resource-session services under `lib/data/services/`.
- Integrate preparation and cache deletion with `BookRepository`.
- Update EPUB reader readiness, lifecycle, and error handling.
- Add the narrow local viewer patch and wire it through `pubspec.yaml`/lockfile.
- Extend data/reader tests and add native performance verification notes.

## Verification and acceptance

1. Test real ZIP fixtures: nested OPF paths, Unicode/escaped resources, invalid
   paths, bounds, staging cleanup, concurrent preparation, cache reuse,
   source invalidation, and deletion.
2. Verify OPF loading bypasses whole-EPUB byte serialization and global asset
   replacements. Record requests before first paint: unrelated chapters/images
   must not be fetched merely to open a prepared book. Exercise native requests,
   escaped/Unicode resource names, CSS imports/fonts, and nonstandard extensions
   whose MIME handling may need explicit manifest-based support.
3. Exercise first display before indexing, cache restore/regeneration, saved CFI
   during indexing, percentage-slider readiness, retries, and disposed callbacks.
4. Run the repository analyzer and complete offline test suite. Preserve the
   opt-in boundary for network-dependent tests.
5. Build/install the Android app without clearing the library. Measure worker audit,
   extraction, byte serialization, engine opening/asset replacement, first display,
   first paint/interaction readiness, index readiness, and warm reopen separately.
6. Use the existing illustrated 24.8 MB EPUB and a multi-chapter fixture. Verify
   saved-position resume, chapter-boundary scrolling, bounded displayed views,
   image/font loading, slider seeks, selection/dictionary, and controls.

Record timing samples with build mode, emulator/device, and book size. Compare
the same book on the same setup using current binary loading, ZIP URL diagnostic,
and OPF native-file loading. Use at least five samples per measured case and
report median and slowest observed sample, without claiming a statistical p95.
Include first chapter, saved middle chapter, warm reopen, cache-missing migration,
and immediate tap after import/download separately.

Select the production transport using correct behavior plus first-paint and
interaction results, not assumptions that native or localhost must be faster.
If full extraction is the dominant cold phase, compare the worker demand-server
challenger before final selection. Do not claim a physical-tablet guarantee from
emulator evidence. Shipping success requires measured improvement and bounded
resource retention, not only passing widget tests.

## Tradeoff

Extracted assets require additional disk space. Reclaimable cache storage and a
global budget make them rebuildable from the original EPUB. Worker processing
keeps synchronous ZIP/XML work away from the UI isolate. Full prewarming must
not extend library publication solely to process unrelated resources, and its
remaining cold-read cost must be compared with demand extraction.

## Review evidence

Two agents reviewed and debated this design: one improved/defended it and one
challenged eager extraction, repeated processing, and unsupported speed claims.
The main thread checked their conclusions against installed source and ran two
temporary Flutter serialization probes, both passing. No native resource-serving
or speed benchmark for the revised architecture has been performed.

See [judge decision and debate](2026-10-12-epub-loading-review.md).

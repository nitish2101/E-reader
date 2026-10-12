# EPUB performance review: debate and judge decision

## Question

What is the best practical loading architecture for this Android tablet app,
including immediate reading after import, opening existing books, and reopening
at a saved position? The original full-extraction/local-server plan is optional.

## Constructive review

The constructive agent defended extracted OPF loading because it keeps epub.js
and the current CFIs/controller/selection behavior while removing ZIP processing
from JavaScript. It found the plan needs explicit `replacements: 'none'`, section
cache management, consolidated worker processing, and independent CFI saves.

Its initial preference was full preparation before publication for predictable
warm opens. After challenge, it agreed this can penalize immediate cold reading
and that merely moving full extraction after publication creates a tap-vs-prewarm
race. It accepted demand extraction as a credible challenger, not only a native
ZIP plugin requiring another dependency fork.

## Adversarial review

The skeptical agent challenged the assumption that byte-string transfer is the
only bottleneck. It found epub.js eagerly replaces every non-HTML resource before
archived opening resolves, and the app's current spinner already clears on first
display independently of index generation.

It also found repeated ZIP work during import and download, retained Section
documents despite iframe destruction, and CFI progress callbacks rejected until
index readiness. It argued full extraction before reading wastes cold startup
on unrelated assets. Its strongest alternate was a file-backed archive resource
server in a worker isolate that demand-extracts entries into a persistent cache.

## Cross-examination and agreement

Both agents debated native ZipFile serving versus the installed Dart archive's
file-backed entries. They agreed that generic Dart CustomPathHandler is not a
native stream: Java receives complete byte arrays over the method channel.
The existing archive dependency makes a worker loopback demand server credible
without adding a second native ZIP dependency fork.

Both supported testing Android WebViewAssetLoader as a simpler prepared-files
transport. They traced an installed serialization defect rather than assuming
the documented API works unchanged. Both agreed to retain epub.js/continuous
rendering, bypass archived asset replacement, cache indexes, and save CFIs before
the index is ready. They disagreed about choosing full extraction without a cold
benchmark; that disagreement is resolved by an explicit measured selection gate.

## Judge decision

Keep the existing EPUB engine and continuous renderer. Changing engines would
create saved-position and feature risk without evidence it is necessary.

Revise the preferred first candidate to **cached OPF loading through Android's
native WebViewAssetLoader**, with `replacements: 'none'`. This removes the original
plan's always-on loopback-server requirement for prepared books and avoids
copying book/resource data through JavaScript literals or Dart platform channels.
Use a narrowly maintained viewer adapter and an app-local serialization workaround.

Reject mandatory full extraction before library publication. Consolidate audit,
metadata, cover work, and prewarming in a worker; publish valid books independently
of unrelated asset extraction. Warm-cache opens reuse preparation/index data.

Full extraction still affects first opens while preparation is incomplete. Do
not call this solved by background prewarming. Compare immediate taps and cache
misses. If extraction dominates their latency, prefer the **worker-isolate
file-backed archive demand server** instead of forcing full preparation or adding
a native ZIP fork. Keep one production loading strategy after comparison; do not
ship two transports merely to avoid making the choice.

The best implementation is selected by controlled first-paint/interaction,
resource requests, and retained-memory evidence. Neither reviewer nor the judge
has measured which new transport is fastest yet.

## Changes required regardless of transport

1. File-based worker input and consolidated EPUB audit/metadata/cover preparation.
2. OPF URL loading, explicit no replacements, saved CFI first, resource demand.
3. Existing adjacent-chapter rendering plus safe Section-document/output eviction.
4. Independent CFI saves before indexing; retained previous percentage while
   index is unavailable; atomic validated locations cache.
5. First paint before indexing, yielding and foreground-resource priority.
6. Bounded cache/storage, single-flight work, reader leases, and disposal fencing.
7. Retryable loading errors and renderer-failure handling.

## Decisive verification

Compare the same illustrated 24.8 MB book, same device and build mode:

| Candidate | What it establishes |
| --- | --- |
| Current byte literal + archived book | Controlled baseline and phase breakdown |
| Direct ZIP URL | How much decimal transfer costs while retaining eager archived assets |
| OPF + native extracted files | Warm demand loading and actual cold preparation cost |
| OPF + worker demand extraction, if needed | Whether avoiding upfront extraction improves cold reading |

Five samples per case; median and slowest observed sample. Separate first-chapter,
saved-middle, warm reopen, cache-missing migration, and immediate post-import taps.
Measure displayed callback and first paint/interaction separately. Check chapter
boundaries, CFI restoration, styles/images/fonts, slider, selection, and dictionary.
Record resource counts/bytes before first paint and retained sections after moving
through the book. No unchanged-widget test can establish native loading speed.

## Evidence checked by the main thread

- Installed viewer `lib/src/epub_viewer.dart:571-602`: full bytes and `data.join`.
- Bundled epub.js source map `src/book.js:499-513`: archived opening waits on
  replacements; `src/resources.js:137-159`: all non-HTML assets replaced together.
- Current reader `onEpubLoaded` already clears the overlay at first display;
  locations readiness separately gates progress acceptance.
- Installed archive decoder creates file-backed entries; ZIP content can be
  inflated on demand. This is source evidence, not a server benchmark.
- Installed WebView plugin serializes path handlers through `toMap()`, and its
  Android internal-storage handler recursively calls `toMap()`.

Temporary diagnostic file `/private/tmp/ereader-asset-loader-probe-test.dart`
contained two Flutter tests, run on 2026-10-12: the original handler throws
StackOverflowError; a serialization-only subclass produces the expected native
configuration. **Both tests passed.** This does not validate actual Android
resource serving, MIME compatibility, or performance.

Official platform guidance:
- https://inappwebview.dev/docs/webview/webview-asset-loader/
- https://developer.android.com/reference/androidx/webkit/WebViewAssetLoader.InternalStoragePathHandler

Only design/review documents were edited. No production loading changes have
been implemented and no speed improvement is claimed.

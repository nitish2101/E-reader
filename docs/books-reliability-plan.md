# Books-only reliability work

The requested outcome is a PDF/EPUB reader with dependable book discovery and downloads. Preserve existing Hive books and reading positions. No separate manga/comics module exists on the cloned main branch; restrict catalog content to books and supported formats.

1. Replace opaque scraper calls with cancellable, bounded HTTP providers for Anna's Archive, LibGen books, and Project Gutenberg (Gutendex). Keep source failures separate from genuine empty results, expose partial-source warnings, deduplicate files, cache successful searches, and track pagination using provider responses.
2. Make search latest-request-wins, cancel on clear/filter/dispose, and retain pagination/filter state across downloads. Separate download state from search so a transfer cannot overwrite a newer query. Add source/format controls and useful retry/error/empty states.
3. Resolve landing pages to download links, attempt alternate links, download to isolated temporary files, verify PDF/EPUB contents, and atomically publish only valid books. Support cancellation and prevent duplicate transfers/library entries. Keep normal TLS verification.
4. Improve local import collision handling, validate imports, extract EPUB metadata/covers, and bound optional cover lookup. Preserve data compatibility.
5. Add offline repository, concurrency, download, library, and widget regression tests plus an opt-in public-domain live smoke check. Run formatting, analysis, tests, and a build when the host toolchain permits. Document provider and platform limits explicitly.

Implementation proceeds in this chat using the user's authorization to clone, remove non-book functionality, and improve book reliability. Changes remain local for review.

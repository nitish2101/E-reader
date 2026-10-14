# Paper & Ink tablet redesign — design specification

**Status:** the user approved the visual direction and requested planning on 2026-10-13. This document records the selected design and implementation decisions; no application implementation is authorized by the planning request alone.

**Workspace:** /Users/nitish/.codex/worktrees/8439/E-reader
**Branch:** codex/tablet-ui-redesign
**Inspected baseline:** a07ad93 (local main at worktree creation).

## Approved references

- [Paper & Ink — Dark](../../design-proposals/tablet-ui/1-paper-ink-dark.png) is the primary visual reference.
- [Paper & Ink — Light](../../design-proposals/tablet-ui/1-paper-ink.png) supplies the companion light appearance.
- [Design provenance and limitations](../../design-proposals/tablet-ui/README.md).

Implement the calm editorial typography, warm charcoal/paper surfaces, olive/sage accents, fine rules, generous gutters, Library shelf, horizontal Store catalogue and immersive reader. Mockup board labels, device borders and illustrative book art are not application assets. Keep real imported/downloaded covers. The mockup's adjacent reader settings panel represents an open sheet, not a permanently visible sidebar.

## Execution amendment — 2026-10-14

Implementation and native evidence are recorded in [Paper & Ink verification](../../paper-and-ink-verification.md). One necessary exception to the engine exclusion preserves the existing custom CSS argument during EPUB initialization; it fixes the reproduced unreadable dark reopen without changing checkpoint/seek/bridge behavior.

The user authorized implementation and removed the light app theme from scope. Build the dark-only app; remove app appearance switching controls while leaving persisted legacy theme keys untouched. EPUB retains existing reading-color choices and defaults to Dark for a new reader preference. The existing light app mockup is historical context, not an implementation deliverable.

Before implementation, fetched and merged latest origin/main c35ad42 into this branch (merge 4ba67b5). Preserve its real reading-statistics feature, Stats entry point, ReaderActivityScope, root readingRouteObserver, checkpoint/retry/resize recovery, and vendored reader-engine overrides. No changes to statistics storage, time accounting, checkpoint semantics or third_party engines. Statistics receives the shared dark theme, with focused layout fixes only if necessary for text scaling.

The explicit no-new-tests instruction overrides skill TDD steps. Run existing checks and manual acceptance flows; no new cases or files. Existing visual selectors may be updated only for intentional changes. Keep current EPUB content geometry to avoid coupling this UI redesign to the newly integrated viewport-recovery behavior; redesign controls and palettes without a reading-measure or engine rewrite.

## Project-wide constraints

- Flutter 3.41+ and Dart 3.10+; Android compile SDK API 36; device/emulator API 26+.
- Keep PDF/EPUB books only.
- Use the existing BLoC/Cubit, Hive, GoRouter, Dio, cached covers and native readers; no new state-management framework or runtime package.
- Do not add tests. Run appropriate existing checks and record manual acceptance evidence.
- Preserve Hive field identifiers, settings keys, libraries, saved positions and existing catalog/download validation.
- Preserve imports, book info/delete, queries, filters, pagination, scroll position, active downloads, source warnings/retries and the Anna's Archive interactive browser.
- Use dark-only Paper & Ink app appearance, as explicitly requested on 2026-10-14; preserve independent Light/Sepia/Dark reader settings and saved reader preferences.
- Work only in this managed worktree; commit finished implementation on codex/tablet-ui-redesign; do not merge or push to main.
- Do not clear device data, uninstall shared builds, interrupt another chat's emulator, or treat another build's screenshots as verification.
- No decorative gradients, glass effects, ornamental animation, fabricated reading statistics, additional account/social features or Library search.

## Current behavior that matters

1. AppRouter uses ShellRoute; HomeScreen swaps Library/Store/Settings via context.go. StoreBloc belongs to StoreScreen, so leaving Store disposes it, cancels searches/transfers and loses session controls. Retained tab lifetimes are needed to meet the user's preservation requirement.
2. LibraryBloc already observes Hive changes. BookModel.lastReadTime is initialized when adding a book, so it alone cannot identify a genuinely started book. Continue reading must use hasStartedReading and choose the greatest lastReadTime.
3. Library's Recently Read / Title / Author / Date Added menu is currently a no-op. Make these already-exposed choices work by sorting a copy for display, without changing repository ordering or Hive records.
4. Store owns its search and scroll controllers; StoreState already contains query, formats, sources, page, hasMore, warnings, downloads and downloadedIds. Keep that state and its existing events.
5. EpubReaderScreen caches its viewer and isolates progress updates in a ValueNotifier. Resume uses CFI plus viewport offset. Keep this ownership, location bridge, save/seek guards and reader routes outside the shell.
6. PDF is supported and must still open/resume. Its engine and custom controls are outside this EPUB-focused redesign; verify readability under the global theme.

## Appearance and typography

Use Material ColorScheme for semantic colors, with one small ThemeExtension for cover/divider extras if necessary. Components read Theme.of(context), not raw per-screen hex constants.

| Semantic role | Light | Dark |
| --- | --- | --- |
| Canvas | #F8F5EE | #1F231D |
| Panel | #FAF8F2 | #282D25 |
| Primary text | #232720 | #EEECE5 |
| Secondary text | #595F55 | #B9C1B1 |
| Accent/action fill | #526343 | #AAB895 |
| Text on action fill | #FFFFFF | #1F231D |
| Meaningful control outline | #858A7D | #7B8575 |
| Decorative divider | #D6D7CD | #444B3F |
| Cover placeholder | #E4E5DA | #343B30 |

Normal text minimum contrast is 4.5:1; meaningful icons/control boundaries minimum is 3:1. Opaque proposed pairs were calculated: light primary 13.95:1, secondary 6.04:1, action label 6.51:1; dark primary 13.50:1, secondary 8.60:1, action label 7.60:1. Composed pressed/disabled/modal states still require implementation measurement. Decorative rules must not be used as the sole meaningful boundary.

Bundle Newsreader regular variable font for headings at assets/fonts/newsreader/Newsreader.ttf and its OFL.txt; use Android's default Roboto for UI/body. Declare the local asset in pubspec.yaml only during implementation, with no font-fetching package. Register the license so Flutter's license page exposes it. Headings use approximately 32sp, UI/body 16sp, metadata 14sp, progress labels at least 12sp; honor system text scaling. Newsreader is for app headings, not a forced replacement for publishers' EPUB fonts.

Font source verified during planning: [Google Fonts metadata](https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/METADATA.pb) lists Newsreader[opsz,wght].ttf; [OFL license](https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/OFL.txt) permits bundling with copyright/license included. Record the retrieved upstream revision/checksum at implementation.

Spacing: 4/8dp rhythm; content gutters 16dp compact, 24dp medium, 32dp wide; section gaps 24/32dp; cards/sheets 12dp corners. Android tap targets at least 48x48dp with 8dp separation. Keep all structural icons in Flutter Material's outlined family.

## Adaptive layout

Use actual LayoutBuilder constraints, including the width left after the navigation rail. Breakpoints are design decisions, not device-model checks.

| Available app width | Navigation | Content |
| --- | --- | --- |
| Below 720dp | Existing three-destination bottom navigation | Compact header; wrapping actions and filters |
| 720dp and above | 80dp labeled navigation rail | Library cover shelf; Store catalogue rows |
| Inner page width below 840dp | Same navigation rule | One Store result per row |
| Inner page width 840dp and above | Same navigation rule | Two Store results per row |

Library columns use a target cover/card width of at least 160dp and 24dp gaps, clamped to 1–6 columns; raise the minimum at larger text scales. Covers retain 2:3 proportion. Compute card height from cover geometry plus scaled title/author/progress allowances; never fit text into the old flex-ratio grid card. Store cover sizes are roughly 88x132dp compact and 112x168dp wide. Tile height expands for text scaling; action buttons wrap below metadata if needed.

Use the same scrollable/controller and stable book keys when width changes. Exact pixel offsets can be clamped after reflow; preserve the leading visible book and its relative offset when column count changes. No scroll reset to the first item. Header actions and source/format chip collections wrap without clipping. Long titles allow two lines with ellipsis, authors one line; full title/author remain available through book info/details on touch and keyboard. At large text scales, reduce columns and relax line limits.

## Navigation and state ownership

Replace ShellRoute with the existing dependency's StatefulShellRoute.indexedStack (confirmed in locked go_router 13.2.5). Three lazily created StatefulShellBranch routes retain the existing /, /store and /settings URLs. HomeScreen receives StatefulNavigationShell, uses currentIndex and goBranch(index), and never requests initialLocation on ordinary reselects.

Keep the shell widget tree stable while switching rail/bottom chrome: use one Row with a rail-or-zero-width slot and an Expanded navigation shell, plus Scaffold's conditional bottom navigation slot. StoreScreen owns one StoreBloc for its retained branch; do not move network state into widgets or recreate providers on appearance/width changes. Library and Store own stable scroll controllers/PageStorageKeys; Library's selected sort is retained in its screen state.

Store source preferences in Settings remain defaults for a new search. Track the last observed preference set and whether the current source filter was explicitly edited. On Store reactivation, adopt changed defaults only if the session is still following defaults; an explicit current filter stays intact. Defer any necessary refresh until a new user search/filter action so returning cannot reset results/page/offset or interfere with downloads. Preferred format changes can update display ordering while retaining the visible-book anchor. No persisted settings-key migration.

Store notices while the branch is inactive must not show a hidden-tab snackbar or later falsely report success. Gate notices by active branch and whether the root reader/browser overlay obscures it; on return present the latest unshown notice once without replaying already-shown notices. Download state/library insertion continue regardless of which tab is visible. In-session retention does not promise background transfers across process death.

Root-navigator EPUB/PDF routes keep their current URLs and book IDs. Push a reader; pop to the exact previous branch and retained state. Back-to-library from a library-opened book returns to that library. Keep Android back behavior and reader save-before-pop flow.

## Screen behavior

**Library:** left-aligned serif title, Sort and Import actions, optional Continue reading summary for an actually started book, All books shelf. Continue reading opens the same book route and saved position; skip when none qualify. Cards use shared cover rendering, title/author/format below cover, labeled progress, and an accessible ellipsis for the existing info/delete actions; retain long press. Sorting is stable using book ID as a tie-breaker: lastReadTime descending, title/author case-insensitive ascending, addedTime descending. Never mutate Bloc lists.

**Store:** left-aligned serif title, visible Search books label, existing search controller and debounce, clear/submit actions, EPUB/PDF and all four source filters. Full source names stay readable outside cover artwork; use Project Gutenberg's existing source label even though the illustrative board abbreviates it. Retain at-least-one selection safeguards, preferred-format ordering, warnings, retry, empty-but-has-more pagination and the Anna browser action. Catalog rows show cover, title, author, source, format and Get/Library. Active download shows Connecting… for unknown progress or percentage/linear bar plus Cancel; completed/cancelled/failed state derives from existing StoreState. If a downloading item is filtered out, preserve its transfer and expose a compact active-download row with Cancel so it remains controllable.

**EPUB:** solid top/bottom control surfaces match the independently selected reader appearance. Top shows Back, book title, Chapters, Text; compact layouts use labeled tooltips/semantics on icons. Bottom retains the real slider, readiness/drag/seek callbacks and percentage, with no estimated pages/time. Chapters remain the existing drawer. Reading settings stay a dismissible modal bottom sheet, constrained to 480dp at wide widths and full-width compact; retain font size 12–32 in steps of 2 and Light/Sepia/Dark values. Keep tap-to-toggle and selection/Define behavior. Apply palette changes through the current controller API without rebuilding the cached native viewer.

For wide reading measure, add a centered max-width of approximately 68ch to EPUB body styling only after verifying continuous-scroll, images and CFI/offset resume on native Android. Do not force Newsreader into publisher content. If the native engine cannot support the measure safely without location-bridge changes, keep current content geometry, record that limitation, and ship the control/palette redesign; do not broaden into a reader-engine rewrite.

**Settings:** same tokens/typography, grouped plain surface sections Appearance, Store & Search, Reading and About; Theme and preferred-format selectors stack below labels when narrow. Preserve all existing settings, cache-clear confirmation and About/license access. No new settings.

**Empty/loading/error:** Library empty state retains Import and explanatory copy; Store preserves meaningful distinctions among initial, no matches, source failures, partial results and pagination. Importing/errors remain visible and readable; don't replace catalog failures with generic empty artwork.

## Verification and delivery

Run formatting, Flutter analysis, focused existing app/store/reader checks, full default offline suite and Android debug build after implementation. No new tests. Existing assertions may be updated only where intentional labels/widget placement changes require it; preserve behavioral coverage.

Manual/native matrix: 360dp compact, 600dp split screen, 800x1280 portrait and 1280x800 landscape, both light/dark; larger text scale 2.0, reduced motion, TalkBack and keyboard focus. Include empty library, missing covers, long title/author, source failures and an active/cancelled/completed download.

Exercise search/filter -> page 2 -> scroll -> download -> Library -> Settings -> Store -> rotate/resize -> reader -> back. Check query, selected filters, loaded page/results, leading visible book, sort choice and transfer remain coherent. Seek while not ready/dragging, change text size/appearance, navigate chapters, background/resume and reopen EPUB. Verify PDF opens/resumes.

For native checks, record this worktree's APK absolute path, checksum, package ID, build revision, device serial/model/API and screenshot width/theme/state. Prefer a task-owned emulator. Do not install over another task's shared app without coordinating exclusive use; otherwise report native verification blocked and keep the built APK/screenshots from any safe checks. Build artifacts/Hive/books/local Android settings remain ignored.

Show actual implementation screenshots and commit the finished implementation on the task branch. No merge or push to main. Planning alone does not claim tests/build/native verification passed.

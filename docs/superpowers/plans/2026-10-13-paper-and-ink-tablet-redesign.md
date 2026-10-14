# Paper & Ink Tablet Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task in this managed worktree. Steps use checkbox syntax. The proposed execution method is implementation by the current agent; no subagents are authorized by this planning request.

**Goal:** Implement the approved Paper & Ink dark appearance across the existing reading app while retaining its state and book workflows.

**Architecture:** Keep existing repositories, Hive, BLoCs/Cubits and native reader ownership. Use a retained GoRouter tab shell, constraints-based layouts, a shared cover renderer and semantic Flutter themes; isolate EPUB control changes from its cached native viewer.

**Tech Stack:** Flutter 3.41+, Dart 3.10+, Material 3, flutter_bloc 8.x, locked go_router 13.2.5, Hive, cached_network_image, flutter_epub_viewer, pdfrx.

**Spec:** [Paper & Ink design specification](../specs/2026-10-13-paper-and-ink-tablet-redesign.md).

## Execution amendment — 2026-10-14

The user authorized implementation and removed the light app theme from scope. Build the dark-only app; remove app appearance switching controls while leaving persisted legacy theme keys untouched. EPUB retains existing reading-color choices and defaults to Dark for a new reader preference. The existing light app mockup is historical context, not an implementation deliverable.

Before implementation, fetched and merged latest origin/main c35ad42 into this branch (merge 4ba67b5). Preserve its real reading-statistics feature, Stats entry point, ReaderActivityScope, root readingRouteObserver, checkpoint/retry/resize recovery, and vendored reader-engine overrides. No changes to statistics storage, time accounting, checkpoint semantics or third_party engines. Statistics receives the shared dark theme, with focused layout fixes only if necessary for text scaling.

The explicit no-new-tests instruction overrides skill TDD steps. Run existing checks and manual acceptance flows; no new cases or files. Existing visual selectors may be updated only for intentional changes. Keep current EPUB content geometry to avoid coupling this UI redesign to the newly integrated viewport-recovery behavior; redesign controls and palettes without a reading-measure or engine rewrite.

## Execution status — 2026-10-14

Theme/primitives, retained navigation, Library, Store, EPUB controls and Settings are implemented and committed. Full existing offline checks passed (134 passed, 3 live skips), static analysis is clean, and the final Android build succeeded. Native verification found and corrected an initial EPUB stylesheet replacement and the white Android startup background.

See [implementation evidence](../../paper-and-ink-verification.md) for source/APK identity, native screenshots, review findings, decisions and unverified scenarios. The task checkboxes below preserve the original planned steps; their broad manual matrix must not be read as proof that every combination was exercised. The dark-only amendment above supersedes historical light-theme steps. The one-line vendored stylesheet initialization correction is an explicit exception to the original engine exclusion.

## Global Constraints

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

## Review Focus

1. Active download plus navigation/reflow: transfer must continue, remain cancellable and publish exactly one validated library entry. Tasks 2/4; manual flow plus existing StoreBloc checks.
2. EPUB font/theme/geometry changes: saved CFI/viewport offset and drag/seek guards must remain correct. Task 5; existing reader checks plus native reopen flow.
3. Long strings and 2.0 text scaling at 360/600dp: actions, source chips, title metadata and Settings controls must fit and remain operable. Tasks 3/4/6; existing responsive Store check plus manual matrix.
4. Source settings changes and tab re-entry: defaults update without replacing explicitly chosen session filters, query/results/page or hidden-tab notices. Tasks 2/4; manual re-entry flow.
5. Empty/partial-failure/pagination states: distinguish provider failure from no matches and retain retry/next page/Anna browser paths. Task 4; existing screen/provider checks plus manual error screenshots.

No additional test cases are planned because the user explicitly prohibited adding tests. Manual checks cover new layout/session behavior that the existing suite does not establish.

## File structure and responsibilities

| Create/modify | Responsibility |
| --- | --- |
| Modify lib/core/theme/app_theme.dart | ColorScheme, typography, component defaults, light/dark appearance |
| Create lib/core/theme/paper_ink_layout.dart | Pure breakpoint/gutter/column calculation |
| Create assets/fonts/newsreader/Newsreader.ttf and OFL.txt; modify pubspec.yaml and lib/main.dart | Offline heading font, declaration and license registration only |
| Modify lib/presentation/navigation/app_router.dart and home_screen.dart | Retained branches, adaptive rail/bottom navigation, active-branch scope |
| Create lib/presentation/shared/active_tab_scope.dart | Active branch signal for retained screens, not network state |
| Create lib/presentation/shared/book_cover.dart and book_progress.dart | Cover load/fallback with fixed proportion; labeled reading progress |
| Create lib/presentation/shared/page_header.dart | Wrapping serif page title/actions |
| Modify library_screen.dart, widgets/library_grid.dart and widgets/book_card.dart under lib/presentation/library | Continue reading, real existing sort choices, responsive shelf and actions |
| Modify store_screen.dart and widgets/store_book_card.dart under lib/presentation/store | Retained search/session view, horizontal catalogue, filters/notices/download actions |
| Modify lib/presentation/reader/epub_reader_screen.dart; create widgets/epub_reader_controls.dart | Reader palette/control presentation; existing screen retains native callbacks |
| Modify lib/presentation/settings/settings_screen.dart | Grouped adaptive settings |
| Modify existing test/app_test.dart, test/store/store_screen_test.dart only if visual selectors change | Adjust existing assertions without adding/removing behavioral cases |
| Create docs/paper-and-ink-verification.md and review screenshots | Actual checks, APK/device evidence, limitations |

Do not modify BookModel/its generated adapter, providers, download/file-validation services, epub_location_bridge.dart or reader persistence. main.dart changes only for font license registration. No reader or state-management package upgrades.

### Task 1: Theme and common presentation primitives

**Files:** theme files and font assets above; shared/book_cover.dart, book_progress.dart, page_header.dart; pubspec.yaml; lib/main.dart.

**Interfaces:**
- Keep AppTheme.lightTheme and AppTheme.darkTheme as ThemeData getters.
- PaperInkLayout.forWidth(double width, {required double textScale}) exposes bool useNavigationRail, double gutter, int libraryColumns, int storeColumns; callers pass their actual available width.
- BookCover({Key? key, String? localPath, String? url, required String title, required String format}) renders a 2:3 cover using existing cache manager and a neutral fallback.
- BookProgress({Key? key, required double progress, required String label}) presents a clamped bar and explicit label.
- PageHeader({Key? key, required String title, List<Widget> actions = const []}) wraps actions without changing the page's scroll owner.

- [ ] Verify branch/worktree and reread applicable AGENTS/spec; confirm tool availability, record flutter --version and locked dependencies. Install locked dependencies only when execution is authorized.
- [ ] Fetch the verified upstream Newsreader regular variable TTF/OFL, retain copyright and record revision/checksum; declare local font and register its license. No runtime font fetching.
- [ ] Apply the exact semantic palettes/spacing/type sizes in the spec; keep existing themeMode settings. Define light/dark component themes for buttons, chips, inputs, dialogs, navigation and sliders.
- [ ] Implement the pure layout helper and shared widgets. Cover loading reserves space; local failure falls back to remote when available, then placeholder. Decorative cover glyph is excluded from duplicate semantics.
- [ ] Run analysis and existing app/Store screen checks; manually inspect primitive typography/fallback in both themes before changing screens. Record meaningful control and text contrast including composed states.
- [ ] Commit the theme/primitives deliverable after checks pass.

### Task 2: Retain tabs and adapt navigation

**Files:** app_router.dart, home_screen.dart, shared/active_tab_scope.dart; Store screen only for active-state handling.

**Interfaces:**
- HomeScreen({Key? key, required StatefulNavigationShell navigationShell}).
- ActiveTabScope({Key? key, required bool isActive, required Widget child}) and static bool isActiveOf(BuildContext context).
- Existing Library/Store/Settings route paths and root reader paths remain unchanged.

- [ ] Configure three lazy StatefulShellBranch routes inside StatefulShellRoute.indexedStack; root navigator owns reader routes. Keep one stable shell child and one StoreBloc per retained Store branch.
- [ ] Derive selection from navigationShell.currentIndex; navigate with goBranch(index) without resetting the branch. Keep the same Row/Expanded shell child while the rail-or-zero-width slot and Scaffold bottom slot change at 720dp; retain controllers/screen elements.
- [ ] Expose branch-active/foreground state to retained screens without introducing a business-state framework. Include root reader/browser overlay visibility in notice gating; hidden Store must not present snackbars. Retain a latest unshown notice for return.
- [ ] Keep source-preference snapshots and explicit-session-filter tracking in Store presentation. Changed defaults apply to the next user query only when following defaults; do not fire a reset search on re-entry.
- [ ] Run existing app test and StoreBloc tests. Manually search -> paginate -> scroll -> start transfer -> change tabs/theme -> return -> resize; record unchanged query/filter/page and transfer continuity.
- [ ] Commit retained navigation after checks pass. Do not proceed if StoreBloc closes on ordinary tab switches.

### Task 3: Library shelf and Continue reading

**Files:** library_screen.dart, library_grid.dart, book_card.dart under lib/presentation/library; shared widgets from Task 1.

**Interfaces:**
- enum LibrarySort { recentlyRead, title, author, dateAdded } stays in Library presentation.
- Existing LibraryGrid(books, onBookTap, onBookLongPress) and BookCard(book, onTap, onLongPress) remain usable; add optional onOptions to BookCard for accessible ellipsis.
- Screen-owned ScrollController and stable PageStorageKey; selectContinueReading(List<BookModel> books) returns BookModel? from hasStartedReading books only.

- [ ] Make LibraryScreen stateful only for selected sort and scroll/anchor; retain existing LibraryBloc import/delete/watch flows. Keep a copied list for stable sorting and book-ID tie-breaking.
- [ ] Replace centered toolbar/FAB presentation with PageHeader and Import/Sort controls; retain existing theme toggle through an accessible secondary control and Settings.
- [ ] Add a compact Continue reading card when a started book exists, choosing latest lastReadTime independently of selected shelf sort. Open through the existing PDF/EPUB routes.
- [ ] Build the shelf with one CustomScrollView/sliver grid, stable book-ID keys, 2:3 cover bounds and card height accounting for scaled metadata. Preserve first visible book/relative offset across column changes and clamp when a book is deleted.
- [ ] Keep long-press and add visible ellipsis for full existing Book Info/Delete flows. Use wrapping labeled rows in Book Info so long values do not overflow. Retain import overlay, empty Library and import result/error feedback.
- [ ] Run existing app/book repository checks. Manually inspect four sort orders, no-started-books summary absence, import cancellation/failure, long title/author, missing cover and delete at 360/600/800/1280dp, both themes, 2.0 text scale.
- [ ] Commit Library changes after checks pass.

### Task 4: Store catalogue, filters and active transfers

**Files:** store_screen.dart and widgets/store_book_card.dart; shared widgets from Task 1 and branch-active scope from Task 2.

**Interfaces:**
- Keep StoreBookCard's UnifiedBook, onDownload, onCancel, isDownloading, isDownloaded, downloadProgress inputs; it now renders a horizontal row.
- Keep StoreBloc/StoreState/events unchanged; screen's controllers live for the retained branch.
- Source preference reconciliation and active notice handling use Task 2's scope.

- [ ] Replace Store toolbar/search/filter presentation with the approved header and visible Search books label; preserve clear/search/debounce events and query controller contents.
- [ ] Render a single lazy catalogue scrollable with one/two columns based on inner width 840dp, natural-height text/action areas and stable book IDs. Keep preferred-format ordering, scroll/leading-book anchor and current loaded results.
- [ ] Move source/format metadata out of covers; keep full meaningful source labels and access to full truncated title/author through an operable detail sheet. Get/Library/Cancel call existing callbacks.
- [ ] Render Connecting… versus percentage bar appropriately; expose compact active-transfer rows with Cancel when those books disappear under a filter. Resolve transfer titles from retained UnifiedBook snapshots without changing download service ownership.
- [ ] Preserve warnings, retry, partial success, initial/no-results/empty-has-more states, load-more errors and the Anna interactive browser. Consume download notices only on the active branch and once on return.
- [ ] Run existing Store screen/Bloc/provider/download tests. Only update existing visual text selectors if intentional copy changes require it; preserve cases and behavior assertions.
- [ ] Manually check source-default changes versus explicit filters, page 2 re-entry, filter-hidden downloads, cancellation/completion, source failure with results, and narrow/large-text catalogue rows. Commit after checks pass.

### Task 5: EPUB control and palette redesign

**Files:** epub_reader_screen.dart and reader/widgets/epub_reader_controls.dart. Leave epub_location_bridge.dart and its save/seek logic untouched.

**Interfaces:**
- EpubTopControls({required String title, required VoidCallback onBack, required VoidCallback onChapters, required VoidCallback onTextSettings}).
- EpubProgressControls({required double progress, required bool isSeeking, ValueChanged<double>? onChangeStart, ValueChanged<double>? onChanged, ValueChanged<double>? onChangeEnd}).
- Existing screen keeps _progressView, _cachedEpubViewer, _closeReader, _seekToProgress and chapter/settings callbacks. Control widgets inherit a locally selected reader ThemeData.

- [ ] Replace gradient top/bottom overlays with solid reader-theme surfaces and SafeArea. Adapt title/actions at narrow widths; preserve Back/Chapters/Text and actual percentage slider.
- [ ] Keep ValueListenableBuilder around progress controls only and forward the existing slider callbacks unchanged. No setState-driven native viewer recreation on progress or appearance updates.
- [ ] Restyle chapter drawer and constrained scrollable settings sheet; preserve readerTheme/readerFontSize keys, 12–32 size in steps of 2, Light/Sepia/Dark choices and controller calls.
- [ ] Apply the approved warm paper/charcoal palette through existing EpubTheme CSS and controller updates. Attempt centered 68ch content only as the spec's guarded native measure change; preserve publisher font families, images and continuous scroll.
- [ ] Run existing epub_reader_screen_test.dart checks. Manually verify center tap/selection/Define, chapter navigation, seek readiness and in-flight seeks, text/theme changes, close/resume/background and long-title controls.
- [ ] Perform the native saved-CFI/offset reopen check before keeping geometry changes. If this cannot pass without bridge changes, keep current geometry and document the limit. Commit the reader controls after checks pass.

### Task 6: Settings and full-state presentation pass

**Files:** settings_screen.dart; only focused presentation corrections in earlier task files.

**Interfaces:** preserve SettingsRepository and ThemeCubit public APIs/settings keys. Existing _ThemeSettingTile, _SearchSourcesTile, _PreferredFormatTile, _AutoSaveProgressTile, _AboutTile and _ClearCacheTile keep their actions.

- [ ] Use PageHeader and grouped flat sections in a bounded readable content column. Stack segmented selectors below labels when width/text scale cannot fit.
- [ ] Preserve at-least-one-source safeguards, preferred format, auto-save, theme persistence, About/license page and cache-clear confirmation.
- [ ] Inspect loading/error/import/empty states in all affected screens, disabled/pressed/focus states, and the unchanged PDF reader under both themes.
- [ ] Run analysis and focused existing checks. Manually verify appearance toggle/restart, settings-source reconciliation, cache cancellation/confirmation, reduced motion, keyboard traversal and TalkBack labels/selected states.
- [ ] Commit Settings and final presentation fixes after checks pass.

### Task 7: Full verification, evidence and review handoff

**Files:** docs/paper-and-ink-verification.md; actual screenshots saved with descriptive names in docs/design-proposals/tablet-ui/implementation/ (avoid ignored screenshot_* names). No test additions.

- [ ] Format only touched Dart files; run static analysis, focused existing checks then the full default offline suite once the final code is stable. Resolve failures; broaden/repeat only after relevant fixes.
- [ ] Build this worktree's Android debug APK with its own ignored android/local.properties. Record exact absolute APK path/checksum/revision; do not use another chat's artifact.
- [ ] Use a task-owned emulator if safely available; otherwise avoid shared-app replacement and record the native limitation. Never clear data/uninstall. Identify serial/model/API and screen dimensions with each native capture.
- [ ] Capture actual Library/Store/EPUB/Settings in light/dark at 800x1280 and 1280x800, plus 360/600dp edge cases and 2.0 text scaling. Include missing covers, long text, empty Library, failures and active download. Fixture-only screenshots must be labeled; source/download liveness is a separate check.
- [ ] Complete the state-retention and reader-resume journeys in the spec, and confirm imported/downloaded PDF still opens/resumes. Record failures/limits honestly; no passed claim from mockups or another build.
- [ ] Review diff against spec: no Hive changes, unrelated service/bridge edits, new framework/packages, new tests, generated books/databases/APKs or main modifications. Obtain a whole-branch review by a supported read-only review mechanism; any agent delegation requires the user's selected execution approach or an applicable review skill.
- [ ] Commit final implementation/evidence on codex/tablet-ui-redesign; show actual screenshots and concise checks/limitations. Do not merge or push to main.

## Verification commands for execution

Use the local paths only after rechecking availability. SDK setup and dependency retrieval belong to implementation, not this planning phase.

```sh
export PUB_CACHE=/private/tmp/ereader-pub-cache
export ANDROID_HOME=/private/tmp/ereader-android-sdk
/private/tmp/ereader-flutter-sdk/bin/flutter --version
/private/tmp/ereader-flutter-sdk/bin/flutter pub get
/private/tmp/ereader-flutter-sdk/bin/flutter analyze
/private/tmp/ereader-flutter-sdk/bin/flutter test test/app_test.dart test/store/store_screen_test.dart test/store/store_bloc_test.dart test/reader/epub_reader_screen_test.dart
/private/tmp/ereader-flutter-sdk/bin/flutter test
/private/tmp/ereader-flutter-sdk/bin/flutter build apk --debug
```

Expected evidence: dependency resolution without unintended lockfile upgrades; analysis has no issues; existing checks exit zero; build reports a real APK from this worktree. APK naming must be read from build output (Gradle customizes it); do not assume the default filename. Network catalog liveness is optional/explicit and is not established by offline checks. Verification may require approved external SDK/cache writes; continue independent checks and document actual limitations.

## Plan self-review

- Spec mapped to Tasks 1–7, with retained tab lifetime resolved before visual screen work.
- Theme/layout/shared widget signatures are consistent across tasks.
- Five review-focus risks have existing checks and/or explicit manual journeys; no new tests are prescribed.
- Font bundle is the only proposed asset/config addition; no runtime package or state-framework change.
- EPUB bridge/persistence and Hive schema are excluded; guarded reading-measure limitation is explicit.
- Planning produces documentation only; implementation waits for the user's review/authorization.

## Execution handoff

Recommended: the current agent implements this plan sequentially in this worktree because the theme, shell and screen tasks share interfaces and do not benefit from parallel mutations. The original task already identifies this workspace/branch; do not create another worktree or use the shared original checkout. This recommendation does not authorize execution or delegation. Ask the user to review the plan before beginning implementation.

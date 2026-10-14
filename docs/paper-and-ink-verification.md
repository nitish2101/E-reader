# Paper & Ink dark redesign — implementation evidence

Verified on 2026-10-14 in `/Users/nitish/.codex/worktrees/8439/E-reader`, branch `codex/tablet-ui-redesign`. Latest fetched main `c35ad42` was merged without conflicts in `4ba67b5` before implementation. Application source through `4d4bd32` is the final built source; the following documentation commit adds evidence only.

## Delivered

Dark-only charcoal/olive app theme, bundled Newsreader headings, adaptive rail/bottom navigation, retained tab sessions, Continue reading, Library sorting and visible book actions, horizontal Store cards, grouped Settings, opaque EPUB controls and reading settings. Existing statistics, imports, catalog safeguards, download validation and reading checkpoints remain. No runtime package upgrades, Hive schema changes or new tests.

EPUB keeps independent Light/Sepia/Dark reading colors and defaults to Dark when no preference exists. The app has no light/system appearance switch. PDF pages keep their original document appearance.

## Automated verification

| Check | Result |
| --- | --- |
| Flutter static analysis, final Dart source | No issues |
| Existing offline Flutter suite after review fixes and EPUB initialization fix | 134 passed, 3 skipped |
| Existing JavaScript location/activity bridge checks | 3 passed |
| Final Android debug build, including startup resources | Successful |
| Whitespace check | Clean |

The three skipped cases in `test/live_books_test.dart` require `RUN_LIVE_BOOK_TESTS`; the default suite does not establish provider availability. Focused existing app, Store/catalog/download, reader/activity and statistics checks also ran during implementation. Two existing visual selectors changed for Library/Store titles and tablet navigation; no behavioral cases were added or removed.

Commands used: `flutter analyze --no-pub`, `flutter test --no-pub`, bundled Node `--test test/reader/epub_location_bridge_test.js`, and `flutter build apk --debug --no-pub`.

Flutter 3.47.7, Dart 3.13.5. Android build used API 36 and Microsoft JDK 21. Existing Gradle/Kotlin support and Java/deprecation warnings remain; no build tooling upgrades were included.

Final APK: `/Users/nitish/.codex/worktrees/8439/E-reader/build/app/outputs/flutter-apk/app-debug.apk`.

SHA-256: `3d552ccceee24216c531c706caa560ef2f5c332869ed9a1b043634d0a1028399`.

## Native evidence

Task-owned AVD `ereader_tablet_redesign`, serial `emulator-5576`, `sdk_gphone64_arm64`, Android 16/API 36, density 320. Landscape physical 2560×1600 = 1280×800dp; portrait 1600×2560 = 800×1280dp. Window-size overrides also exercised 360×800dp and 600×800dp with system text scale 2.0 and animation scales zero. Data was preserved across replacement installs and cold app restarts. No shared build was uninstalled and no app data was cleared.

Screenshots are actual native captures in [implementation/](design-proposals/tablet-ui/implementation/), rather than generated mockups. Captures span the final presentation commits: empty Library precedes the review fixes; main layout captures follow the review fixes; dark EPUB reopen follows `515d7bb`; the final populated Library and platform startup use the complete source `4d4bd32`.

| Journey | Observed result / evidence |
| --- | --- |
| Empty Library | Import action and explanation visible; [capture](design-proposals/tablet-ui/implementation/library-empty-landscape.png) |
| Real Gutenberg download | Pride and Prejudice downloaded, inserted in Library, rendered and saved reading progress |
| Real Standard Ebooks download | Frankenstein showed Connecting/Cancel, survived Library → Store, completed with one Library entry; [transfer](design-proposals/tablet-ui/implementation/store-transfer-landscape.png) |
| Retained Store state | Catalog scroll remained at the same books after tab return; entered query `herlock` and its two results survived Settings → Store; [query](design-proposals/tablet-ui/implementation/store-search-retained-landscape.png) |
| Partial provider failure | A subsequent Gutenberg request timed out while Standard Ebooks results remained, with an explicit warning and Retry search; [capture](design-proposals/tablet-ui/implementation/store-landscape.png) |
| Native file import | Android Downloads picker imported the missing-cover EPUB fixture and PDF fixture; their metadata and fallback/thumbnail appeared in Library |
| Populated Library | Real downloaded books plus clearly named `Tablet Reader Check` / `Tablet Pdf Check` manual fixtures; [landscape](design-proposals/tablet-ui/implementation/library-populated-landscape.png), [portrait](design-proposals/tablet-ui/implementation/library-portrait.png) |
| Library sorting | All four choices were available; Title sorted the four entries alphabetically and remained selected after Settings → Library |
| EPUB chapters, font and colors | Chapter I navigation, size 18 → 20, Sepia → Dark controls worked; [settings](design-proposals/tablet-ui/implementation/epub-settings-landscape.png) |
| EPUB cold reopen | Saved Chapter I passage reopened at 4.3% with dark body styles intact after app restart; [capture](design-proposals/tablet-ui/implementation/epub-reopened-landscape.png) |
| EPUB seek and resize | Slider moved 4.3% → 47.6%; resize to portrait recovered readable prose and matching progress; [portrait](design-proposals/tablet-ui/implementation/epub-portrait.png) |
| Compact reader | Back, truncated title, chapter/text icons and stacked progress control fit at 360dp / 2× text; [capture](design-proposals/tablet-ui/implementation/epub-360-large-text.png) |
| Large text app screens | Library actions wrap, source chips wrap, Store cards/actions scroll, Settings labels/format selector fit at 360/600dp; corresponding captures have `large-text` filenames |
| PDF smoke check | Imported one-page PDF rendered, its completed position appeared in Library, and reopening restored Page 1 of 1 / 100%; [capture](design-proposals/tablet-ui/implementation/pdf-fixture-open-landscape.png) |
| Cold startup | Platform splash uses charcoal with existing launcher icon; [capture](design-proposals/tablet-ui/implementation/startup-dark.png) |

Native runtime log inspection during these journeys found no Flutter RenderFlex overflow, uncaught Flutter exception or Android fatal exception. One later host emulator graphics failure stopped the device; its log reported EGL/Vulkan context preemption. This is separate from app crash evidence. The task AVD was restarted with Vulkan disabled and existing data preserved.

## Review and corrections

A fresh read-only whole-branch review examined `c35ad42..11508ae`. No critical findings. Both actionable findings were corrected in `1bb6b7e`: hidden Library operation notices are retained until visible, and the shared shelf compensates when header height changes without book IDs/columns changing. Header movement was regraded Important because it affects reading the scrolled catalog. No deferred minor findings.

Native verification additionally reproduced pale EPUB text on a white background after reopen. `loadBook` registered custom CSS, then replaced the named theme with a color-only call. `515d7bb` forwards the existing `customCss` argument at that second call. This preserves the intended initial styling without changing the location bridge, checkpoint or seek algorithms. Native dark reopen passed on the corrected APK. `4d4bd32` also replaces the white Android launch background with the dark canvas.

## Decisions and limits

- Dark-only supersedes the historical light companion and system toggle, following the user's instruction. A later light theme would require additional work.
- No new tests were added, following the user's instruction. Existing checks and manual journeys do not establish every new state combination.
- Preserve main's statistics/recovery and existing EPUB content geometry; do not add the proposed 68ch reading width. Wide prose therefore retains the current engine/publisher geometry.
- Source review cannot establish device behavior. Native captures cover the listed journeys on this task's emulator; physical tablets, every orientation/text-size combination and full TalkBack/keyboard traversal remain unverified. TalkBack was installed but a complete spoken-navigation audit was not performed.
- Allow the one-line vendored initialization correction despite the original engine exclusion: the reproduced dark reopen was unreadable otherwise. This local line must be considered when upgrading the reader package.
- Provider availability varies: both direct EPUB providers succeeded during this session, while later Gutenberg search timed out. Anna's Archive/LibGen interactive and full live page-two journeys were not verified natively in this pass; existing offline coverage remains green.
- A quick start/cancel interaction returned its card to Get, but cancellation was not independently confirmed by a fresh notice, so it is not counted as a native cancellation pass. Filter-hidden transfer completion/header anchoring and delayed hidden Library failure were source-reviewed and corrected, with existing checks green; they were not independently reproduced end-to-end on the emulator.
- PDF verification used a one-page fixture. Multi-page PDF resume and PDF downloads were not established by this pass. PDF engine/source was unchanged.

The branch is intended to remain committed in this managed worktree. It has not been pushed or merged into main.

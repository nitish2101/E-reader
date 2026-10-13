# Reader checkpoint and recovery verification

Verified 2026-10-13 on `codex/reader-reliability`, starting from
`a07ad938c8425e409acc1c58a7f43b2a2fc77fc9`. The continuous EPUB.js reader
engine remains unchanged.

## Implementation

- EPUB saves sample the actual visible text every five seconds, after scrolling
  stops, on backgrounding, and before awaited navigation out of the reader.
  Overlapping captures share an active operation. Loading, seeking, reflow, and
  failed viewer states cannot overwrite a confirmed position.
- Optional Hive field 16 stores checkpoint version 1: revision, CFI, progress,
  line offset, and layout metadata. Existing field IDs 0–15 are unchanged.
  A per-box queue serializes writes across repository instances; each checkpoint
  is one book record update followed by a flush. The adapter was regenerated.
  Legacy CFI/progress and matching legacy viewport records remain readable.
- Layout metadata covers viewport dimensions, font size, line height, pixel
  ratio, and bridge engine version. Font changes and native resize retain the
  text anchor; incompatible pixel offsets are discarded. Resize interception is
  at EPUB.js's manager, which owns its native resize path.
- Opening still proceeds behind the 15-second watchdog's Retry/Return controls.
  Failed file opening, EPUB parsing/display, and bridge restoration expose
  recovery controls. Retrying creates a fresh viewer from saved state.
- Android renderer exit removes the failed platform view before persistence.
  Two automatic retries are allowed per screen; subsequent exits require manual
  Retry or Return. Generation guards reject callbacks from replaced viewers.
- The pinned EPUB package cancels long-press/selection timers and guards late
  native callbacks. A pinned Android WebView disposal patch destroys dead views
  directly and handles renderer exit during ordinary disposal. Upstream sources,
  versions, licenses, and patch rationale are recorded in the two vendored
  package READMEs. Generated upstream Dart models are included.
- PDF native page callbacks confirm position synchronously; periodic,
  background, and awaited-close saves use the ready controller's actual page.
  PDF opening also has retry/error/watchdog controls.

## Automated checks

The regression suite covers concurrent coherent persistence after reopening the
Hive box, periodic viewport sampling with hidden controls, stalled-load recovery,
replaced-view callbacks, bounded renderer retries, failed initial restoration,
transient reflow suppression, selection disposal, and immediate PDF page/close
persistence. Existing reader seeking and slider regressions remain included.

Before the selection patch, the close-after-long-press regression observed 68
selection calls after disposal; the patched behavior makes zero such calls.
The malformed-book native check initially reached only watchdog recovery;
catching the promise returned by `book.open` now reports its actual parsing error.

Final `flutter analyze`: no issues. Final `flutter test`: 83 passed, three
opt-in network tests skipped. The standalone actual-bridge regression also
passes: `node --test test/reader/epub_location_bridge_test.js`.
It executes the shipped JavaScript through a minimal EPUB.js surface, exercises
resize during active reflow followed by reading a later passage and another
resize, and fails against the pre-fix resize wrapper (expected later anchor B,
restored stale A). Flutter overlap regressions verify close/background sample
again after an older in-flight capture instead of merely joining it.
Final normal-entry-point `flutter build apk --debug --no-pub`: successful;
APK metadata confirms `com.ereader.app`, version 1.2.0 (3). SHA-256:
`9a68a2d79eb15087860ae46aa7c474c36dd45949efabe7449ba86d0aaba1b19a`.
Artifact: `build/app/outputs/flutter-apk/app-debug.apk` (ignored).
Existing Gradle/AGP/Kotlin future-support warnings remain; no toolchain upgrade
is included in this reader change. This normal APK was built, not installed on
the shared emulator.
Unmodified vendored Android-plugin Dart sources are excluded from app analysis;
its patched Java implementation is compiled in the Android APK build. Vendored
EPUB Dart sources are analyzed. Three live network tests require explicit opt-in.

## Native Android verification

All final native scenarios used a dedicated temporary Android 16 / API 36 arm64
emulator, serial `emulator-5562`, 2560×1600 pixels at density 320. The isolated
verification application ID was `com.ereader.reliability`. A separate entry point
seeded a six-chapter scrolling EPUB, a five-page PDF, and opening-error fixtures.
The normal app's entry point does not contain these fixtures or logging hooks.

Verification APK SHA-256:
`2825094adcd180c6b3f58d99e759b26e12e4a63d981ba5726a93c35703c7e486`
for the opening-error and progressed renderer checks; final reviewed build
`8fb683ea038190bf53d73f75f9b36900fbb8ccc87de2dd39942f3c075b1a0aac`
adds the resize/overlap fixes.
Raw scripts, snapshots, screenshots, APK, and logs are local ignored artifacts in
`docs/emulator-evidence`; they are not shipped source or committed test fixtures.

| Scenario | Observed result |
| --- | --- |
| Interrupt scrolling, immediately close, reopen | Visible CFI `/6/2!/4/12/1:133` and 3.734375 CSS-pixel offset restored exactly. |
| Background/resume; lock/unlock | CFI `/6/2!/4/22/1:0`, progress 0.02247191011235955 and −44.265625 CSS-pixel offset unchanged. |
| Force-stop and relaunch app process | PID changed 4363→5611; opening the saved book restored the same CFI, progress, and offset. |
| Font 18→20 px | Same text CFI retained; old incompatible offset discarded, anchor settled at 0.09375 CSS pixels. |
| Portrait, landscape, resized viewport, reset | Same text CFI retained at 0.09375 CSS pixels through CSS viewports 800×1280, 1280×800 and 1100×700. |
| Three deliberate WebView renderer crashes | Host PID 4363 survived all three. First two recreated the viewer at the saved anchor; third exposed manual recovery. Manual Retry restored the anchor. |
| Renderer crash at a progressed checkpoint, latest APK | Host PID 6477 survived; `/6/2!/4/22/1:0`, 0.02247191011235955 progress and 0.09375 offset matched before/after. |
| Native selection and immediate close | Long press selected the actual word “continuous”; immediate Back returned to My Library. Collected app logs contained no disposed-controller/Unhandled Exception/MissingPluginException matches. |
| PDF background and close/reopen | Actual native page 4 of 5 and 80% restored. |
| Malformed EPUB | Real ZIP parsing error plus Retry/Return visible after two seconds; Return worked. |
| Slow EPUB with a 25-second delayed image | Watchdog controls visible at 18.57 seconds; viewer finished loading without retry by 31.83 seconds and produced a valid visible snapshot. |
| Final build: resize during active reflow, read later, resize again | Later passage `/6/2!/4/30/1:242` remained at 0.09375 CSS pixels; it did not rewind to the earlier `/22` passage. The resized line begins at character 199, so strict equality of the first-visible-character CFI is inappropriate when text wraps. |
| Final build: close/reopen after resetting viewport | `/6/2!/4/30/1:121`, progress 0.033707865168539325 and 0.09375 CSS-pixel offset matched exactly. |

Renderer death and app-process death were exercised separately. The native
renderer test uses DevTools `Page.crash`; it is not a reproduction of OS memory
pressure. Earlier native reproduction exposed the upstream disposal bug: first
renderer exit recovered, but the second killed host PID 5263 with Chromium's
“crash wasn't handled by all associated webviews”. The scoped Java patch was
then verified by the repeated-exit scenarios above.

## Boundaries and verification incident

An early fixture APK was accidentally installed with the normal application ID
on the pre-existing shared emulator because Flutter rewrote the attempted local
properties override. No app data was cleared or uninstalled. The incident was
reported during execution; subsequent testing used a dedicated emulator and an
environment-selected ID, checked in APK metadata before installation. The
original checkout and other branches were not modified. The production ID
defaults to `com.ereader.app` when the verification environment override is unset.

These measurements establish the tested fixture behavior, not an exhaustive
guarantee across physical devices, complex EPUBs, external fonts, or OS kills.
An abrupt process exit may lose reading since the last completed checkpoint
(normally up to the five-second sampling interval plus asynchronous write time).
Layout changes preserve the passage near the viewport top, rather than reusing
incompatible pixels. PDF checkpoints are page-granular. Dictionary selection and
Define code paths are preserved, but external dictionary responses were not
verified by this work. No deployment, push, or merge into main is part of this task.

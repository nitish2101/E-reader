# EPUB scrolling and progress verification

Verified locally on 2026-10-12 with `flutter_epub_viewer` 1.2.8.

## Changes

- Disable the package's Android custom page-swipe handler. It unconditionally
  prevents `touchmove` events without a selection, blocking native vertical
  scrolling. In this package version, `useSnapAnimationAndroid: true` disables
  that handler; `snap: false` keeps page snapping disabled.
- Register chapter CSS through the rendition theme before content is measured,
  rather than injecting styles after display through an iframe observer.
- Rebuild and animate only the progress controls during location updates.
- Sample visible progress at most ten times a second during scrolling, using a
  passive listener; stop this extra sampling while controls are hidden or seeking.
- Keep drag previews separate from the confirmed location saved to the library.
  Await actual seek completion, reject stale location events using ordered
  snapshots, and retain newer snapshots arriving before the seek response.
- Treat centre touches as control taps only when movement and duration are small.

## Automated checks

- `flutter analyze`: no issues.
- `flutter test`: 56 passed, one opt-in live network test skipped.
- Twelve reader widget regressions exercise readiness, dragging during incoming
  events, actual-position persistence during a drag, isolated progress animation,
  centre-ending swipes, initial styling/native scroll settings, seek completion,
  failure recovery, disposal, and out-of-order location updates.
- The JavaScript bridge was also evaluated against a simulated rendition and
  scroller: ordered snapshots, passive registration, idempotent installation,
  one timer for a burst of scroll events, and no extra reports while hidden or
  while a selection is active.
- `flutter build apk --debug`: succeeded.

## Android emulator

Used a local six-chapter EPUB fixture with 80 paragraphs per chapter on a
2560-by-1600 Android tablet emulator. Before disabling the package's custom
swipe handler, native gestures left the scroll offset at zero despite a
scrollable container and no active text selection.

With the final configuration:

- Native vertical swipes advanced the visible text and progress from 0.0% to
  1.1%, then 2.2% with controls visible.
- A swipe finishing in the centre left controls hidden; a subsequent centre tap
  opened them.
- Dragging the progress thumb from 2.2% to 59.6% displayed chapter 4,
  paragraph 44, without a seek failure message.
- Returning to the library displayed 59.6% complete.
- Reopening restored chapter 4, paragraph 44, with 59.6% displayed; the text
  position was confirmed in a screenshot.
- Switching to dark theme applied the expected background/text colors. Native
  scrolling continued and the reported position advanced to 61.8%.
- Native long presses still selected words, confirmed through the WebView's
  selection state.

This verifies behavior in an emulator, not a frame-time benchmark or a physical
device assessment of scrolling feel. Selection handles and font-size changes
have not been checked on a physical device.

## Combined follow-up verification

The combined emulator run also found typography-position reflow and third-party
selection-timer disposal defects. See [the combined report](emulator-verification.md)
for fresh native evidence and the limits of the widget tests.

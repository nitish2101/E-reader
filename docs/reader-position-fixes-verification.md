# Reader scrolling, resume, and Anna’s Archive verification

Verified on 2026-10-12. The user reported fast loading in the previous release
on their physical tablet, so the proposed EPUB extraction redesign was deferred.
These changes keep the existing reader engine.

## Fixes

- Disable Chromium scroll anchoring on the EPUB scroll container. EPUB.js
  already compensates for chapter height changes when prepending content.
- Save CFI before the percentage index finishes; preserve the previous
  percentage until an indexed value is available.
- Sample the visible CFI synchronously before leaving/backgrounding, save its
  line offset, and restore the CFI and offset with anchoring disabled. Closing
  waits for the snapshot/write, with a 750 ms fallback to the latest event.
- Add an interactive Anna’s Archive browser for the site's own verification,
  manual search-result import, mirror selection, and download selection.
  Native cookie lookup and the browser user agent are reused for selected
  downloads. Redirects are handled explicitly, looking up session headers for
  each destination rather than forwarding cookies across hosts.

## Evidence

- Before the scroll fix, previous-chapter resizing by 2,937 px moved the
  viewport from 4,384 to 7,321 through browser anchoring; EPUB.js then added
  another 2,937 px and moved it to 10,258. With anchoring disabled, the same
  resize moved the viewport once, from 4,384 to 7,321.
- In the updated Android debug app, scrolling backward across chapter 4 to
  chapter 3 changed the visible CFI from `epubcfi(/6/8!/4/2/1:0)` to
  `epubcfi(/6/6!/4/156/1:242)` and progress from 50.56% to 49.44%.
- Scrolling and immediately closing before the three-second save debounce
  saved `epubcfi(/6/4!/4/10/1:0)` with an offset of -67.40625 CSS px. Once
  reopening completed, both CFI and offset matched exactly.
- `flutter test --no-pub`: 73 passed; three opt-in live network tests skipped.
- `flutter analyze --no-pub`: no issues.
- `flutter build apk --release --no-pub`: successful, 80,428,361 bytes.
- Desktop copy SHA-256:
  `bc795e8d6c8a9523a71a4cfc20a27ea7a8d2db31b742ecf09803c8b1bb156e89`.
  APK signature verified and matches the earlier Desktop release APK.

## Limits

Real-device confirmation of the reader fixes remains with the user. A real
Anna’s Archive CAPTCHA was not solved during verification. The app exposes
the site's actual page; it cannot guarantee the source accepts embedded
browsers or subsequent download requests. Tests cover the browser entry
point, existing store behavior, and redirect/session-header isolation.

APK: `/Users/nitish/Desktop/E-Reader-v1.2.0-reader-fixes.apk`.
It contains the working-tree changes, including uncommitted files used by
the app. It remains signed with the project's existing Android test key.

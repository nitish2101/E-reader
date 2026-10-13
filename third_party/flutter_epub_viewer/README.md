# Scoped lifecycle patch of flutter_epub_viewer 1.2.8

Source: pub.dev archive flutter_epub_viewer 1.2.8 (locked SHA-256
39d8ff469700fea41f103ae1ec01e06c805c3602eef0fecb1c5b325688dcb5b2),
https://github.com/fayis672/epub_viewer. Original MIT license retained.

The EPUB.js/JSZip engine and continuous scrolling implementation are unchanged.
Local changes expose load errors and Android renderer termination; cancel all
long-press and selection monitoring timers on disposal/renderer failure; guard
late callbacks and file reads; catch selection calls racing platform disposal;
and report failed book opening/display. Small Dart Color API updates retain the
same ARGB conversions under the project's Flutter version.

App-owned location/reflow tracking remains in lib/presentation/reader. This local
path dependency prevents mutable shared pub-cache edits and makes the patch
reviewable. Rebase these changes explicitly when upgrading the upstream package.

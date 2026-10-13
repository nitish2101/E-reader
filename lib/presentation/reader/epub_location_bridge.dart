/// Read CFI snapshots synchronously, before the package's asynchronous XPath
/// conversions can reorder them. The sequence also fences off pre-seek events.
const epubLocationBridgeScript = r'''
(function() {
  if (!rendition || !rendition.manager) return false;
  if (window._ereaderLocationBridge) return true;
  window._ereaderLocationSequence = 0;
  window._ereaderProgressVisible = false;
  // EPUB.js compensates when it inserts/removes chapters above the viewport.
  // Chromium's anchoring would apply the same height change a second time.
  var manager = rendition.manager;
  manager.container.style.overflowAnchor = 'none';
  document.documentElement.style.overflowAnchor = 'none';

  function snapshot(location) {
    if (!location) location = rendition.located(manager.currentLocation());
    if (!location || !location.start || !location.end) return null;
    var offset = null;
    try {
      var view = manager.visible().find(function(v) {
        return v.index === location.start.index;
      });
      var range = rendition.getRange(location.start.cfi);
      if (view && range) {
        var top = manager.settings.fullsize ? 0 : manager.container.getBoundingClientRect().top;
        offset = view.iframe.getBoundingClientRect().top + range.getBoundingClientRect().top - top;
      }
    } catch (_) {}
    return {
      startCfi: location.start.cfi,
      endCfi: location.end.cfi,
      progress: Number.isFinite(location.start.percentage) ? location.start.percentage : 0,
      offset: offset,
      sequence: ++window._ereaderLocationSequence
    };
  }
  window._ereaderSnapshot = snapshot;
  window._ereaderRestoreOffset = function(cfi, offset) {
    var range = rendition.getRange(cfi);
    var view = manager.visible().find(function(v) {
      return range && v.contents.document === range.startContainer.ownerDocument;
    });
    if (!view || !Number.isFinite(offset)) return false;
    var top = manager.settings.fullsize ? 0 : manager.container.getBoundingClientRect().top;
    var currentOffset = view.iframe.getBoundingClientRect().top + range.getBoundingClientRect().top - top;
    manager.scrollBy(0, currentOffset - offset, true);
    rendition.reportLocation();
    return true;
  };
  rendition.on('relocated', function(location) {
    var data = snapshot(location);
    if (data) window.flutter_inappwebview.callHandler('ereaderRelocated', data);
  });

  // Passive listeners preserve the engine's touch/scroll behavior. Only
  // trusted input wakes an idle clock; automatic relocations never do.
  var lastActivity = 0;
  function activity(event) {
    if (!event.isTrusted) return;
    var instant = performance.now();
    if (instant - lastActivity < 1000) return;
    lastActivity = instant;
    window.flutter_inappwebview.callHandler('ereaderActivity');
  }
  function observeInput(contents) {
    ['touchstart', 'touchmove', 'pointerdown', 'pointermove', 'wheel', 'keydown'].forEach(function(name) {
      contents.document.addEventListener(name, activity, {passive: true});
    });
  }
  rendition.getContents().forEach(observeInput);
  rendition.hooks.content.register(observeInput);

  // The continuous manager debounces normal location reports until scrolling
  // pauses. Refresh at most ten times a second while progress is visible,
  // leaving native scrolling and the manager's final report intact.
  var scroller = manager.settings.fullsize ? window : manager.container;
  var timer = null;
  scroller.addEventListener('scroll', function() {
    if (!window._ereaderProgressVisible || timer !== null) return;
    timer = setTimeout(function() {
      timer = null;
      if (!window._ereaderProgressVisible) return;
      if (typeof hasActiveSelection === 'function' && hasActiveSelection()) return;
      rendition.reportLocation();
    }, 100);
  }, {passive: true});
  window._ereaderLocationBridge = true;
  return true;
})();
''';

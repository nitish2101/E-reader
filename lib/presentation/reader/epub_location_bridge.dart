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

  window._ereaderBusy = false;
  window._ereaderLastConfirmed = null;
  function layout() {
    var view = manager.visible()[0];
    var body = view && view.contents && view.contents.document.body;
    var style = body ? view.contents.window.getComputedStyle(body) : null;
    return {width: manager.container.clientWidth, height: manager.container.clientHeight,
      fontSize: style && style.fontSize, lineHeight: style && style.lineHeight,
      devicePixelRatio: window.devicePixelRatio, engine: 'epubjs-continuous-1'};
  }
  window._ereaderLayoutMatches = function(saved) {
    if (!saved) return false;
    var current = layout();
    return Object.keys(current).every(function(key) { return current[key] === saved[key]; });
  };
  function snapshot(location) {
    if (window._ereaderBusy) return null;
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
    var result = {
      layout: layout(),
      startCfi: location.start.cfi,
      endCfi: location.end.cfi,
      progress: Number.isFinite(location.start.percentage) ? location.start.percentage : 0,
      offset: offset,
      sequence: ++window._ereaderLocationSequence
    };
    window._ereaderLastConfirmed = result;
    return result;
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

  function frames() { return new Promise(function(resolve) {
    requestAnimationFrame(function() { requestAnimationFrame(resolve); });
  }); }
  window._ereaderReflow = async function(change, anchor) {
    if (window._ereaderBusy) return false;
    anchor = anchor || snapshot();
    if (!anchor) throw new Error('No confirmed passage to restore');
    window._ereaderBusy = true;
    window.flutter_inappwebview.callHandler('ereaderReflow', true);
    var succeeded = false;
    try {
      change();
      await new Promise(function(resolve) { setTimeout(resolve, 150); });
      await frames();
      await rendition.display(anchor.startCfi);
      await frames();
      var restored = window._ereaderRestoreOffset(anchor.startCfi,
        window._ereaderLayoutMatches(anchor.layout) && Number.isFinite(anchor.offset) ? anchor.offset : 0);
      if (!restored) throw new Error('Passage unavailable after reflow');
      succeeded = true;
      return true;
    } finally {
      // Keep snapshots blocked if reflow fails. Retry recreates the viewer from
      // the confirmed checkpoint; intermediate layout must never be persisted.
      if (succeeded) {
        window._ereaderBusy = false;
        window.flutter_inappwebview.callHandler('ereaderReflow', false);
        rendition.reportLocation();
      }
    }
  };
  // Hold the last confirmed passage before EPUB.js resizes its stage. Relocation
  // callbacks emitted by its intermediate layout are suppressed until restored.
  var originalResize = manager.resize.bind(manager);
  var resizeTimer = null;
  var resizeAnchor = null;
  function scheduleResizeRestore() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function() {
      resizeTimer = null;
      var anchor = resizeAnchor;
      resizeAnchor = null;
      window._ereaderBusy = false;
      window._ereaderReflow(function() {}, anchor).catch(function(error) {
        window.flutter_inappwebview.callHandler('ereaderReflowError', String(error));
      });
    }, 200);
  }
  manager.resize = function(width, height, cfi) {
    // An active typography/restore operation already owns its anchor. Never
    // seed another anchor here: it could survive and rewind a later resize.
    if (window._ereaderBusy) {
      var result = originalResize(width, height, cfi);
      if (resizeTimer !== null) scheduleResizeRestore();
      return result;
    }
    resizeAnchor = window._ereaderLastConfirmed || snapshot();
    if (!resizeAnchor) return originalResize(width, height, cfi);
    window._ereaderBusy = true;
    window.flutter_inappwebview.callHandler('ereaderReflow', true);
    var result = originalResize(width, height, cfi);
    scheduleResizeRestore();
    return result;
  };

  // The continuous manager debounces normal location reports until scrolling
  // pauses. Refresh at most ten times a second while progress is visible,
  // leaving native scrolling and the manager's final report intact.
  var scroller = manager.settings.fullsize ? window : manager.container;
  var timer = null;
  scroller.addEventListener('scroll', function() {
    if (window._ereaderBusy || timer !== null) return;
    timer = setTimeout(function() {
      timer = null;
      if (window._ereaderBusy) return;
      snapshot();
      if (!window._ereaderProgressVisible) return;
      if (typeof hasActiveSelection === 'function' && hasActiveSelection()) return;
      rendition.reportLocation();
    }, 100);
  }, {passive: true});
  window._ereaderLocationBridge = true;
  return true;
})();
''';

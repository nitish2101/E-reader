// Run with Node.js: node --test test/reader/epub_location_bridge_test.js
// Execute the shipped bridge, rather than copying its resize state machine.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const dartSource = fs.readFileSync(
  path.join(__dirname, '../../lib/presentation/reader/epub_location_bridge.dart'),
  'utf8',
);
const script = dartSource.match(/const epubLocationBridgeScript = r'''([\s\S]*?)''';/)[1];

function createViewer() {
  let currentCfi = 'epubcfi(A)';
  const displays = [];
  const chapterDocument = { body: {} };
  const view = {
    index: 0,
    contents: {
      document: chapterDocument,
      window: { getComputedStyle: () => ({ fontSize: '18px', lineHeight: '27px' }) },
    },
    iframe: { getBoundingClientRect: () => ({ top: 0 }) },
  };
  const manager = {
    container: {
      style: {},
      clientWidth: 400,
      clientHeight: 800,
      getBoundingClientRect: () => ({ top: 0 }),
      addEventListener: () => {},
    },
    settings: { fullsize: false },
    visible: () => [view],
    currentLocation: () => ({
      start: { cfi: currentCfi, index: 0, percentage: 0.4 },
      end: { cfi: currentCfi },
    }),
    resize: () => {},
    scrollBy: () => {},
  };
  const context = {
    window: { devicePixelRatio: 1, flutter_inappwebview: { callHandler: () => {} } },
    document: { documentElement: { style: {} } },
    setTimeout,
    clearTimeout,
    requestAnimationFrame: (callback) => queueMicrotask(callback),
    rendition: {
      manager,
      located: (location) => location,
      getRange: () => ({
        startContainer: { ownerDocument: chapterDocument },
        getBoundingClientRect: () => ({ top: 0 }),
      }),
      on: () => {},
      display: async (cfi) => { displays.push(cfi); },
      reportLocation: () => {},
    },
  };
  vm.runInNewContext(script, context);
  return {
    bridge: context.window,
    manager,
    displays,
    read: (cfi) => {
      currentCfi = cfi;
      context.window._ereaderSnapshot();
    },
  };
}

test('resize during reflow cannot retain a stale anchor for a later resize', async () => {
  const viewer = createViewer();
  viewer.read('epubcfi(A)');
  const reflow = viewer.bridge._ereaderReflow(() => {});
  // A window resize races a font change or an earlier resize restoration.
  viewer.manager.resize();
  await reflow;

  viewer.read('epubcfi(B)');
  viewer.manager.resize();
  await new Promise((resolve) => setTimeout(resolve, 500));

  assert.equal(viewer.bridge._ereaderLastConfirmed.startCfi, 'epubcfi(B)');
  assert.equal(viewer.displays.at(-1), 'epubcfi(B)');
  assert.equal(viewer.bridge._ereaderBusy, false);
});

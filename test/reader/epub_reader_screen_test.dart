import 'dart:async';
import 'dart:io';

import 'package:ereader/data/models/book_model.dart';
import 'package:ereader/data/repositories/book_repository.dart';
import 'package:ereader/presentation/reader/epub_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show InAppWebViewController;
// The native surface is replaced, while the reader and its callbacks stay real.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _TestWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _TestWebView(params);
}

class _TestWebView extends PlatformInAppWebViewWidget {
  _TestWebView(super.params) : super.implementation() {
    latest = params;
  }
  static PlatformInAppWebViewWidgetCreationParams? latest;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

class _SeekWebViewController extends PlatformInAppWebViewController {
  _SeekWebViewController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'test'),
      );

  final completed = Completer<CallAsyncJavaScriptResult?>();
  Map<String, dynamic>? seekArguments;
  Map<String, dynamic>? snapshot;
  Completer<dynamic>? pendingSnapshot;
  int snapshotCalls = 0;
  Map<String, dynamic>? restoreArguments;
  int selectionCalls = 0;
  bool restoreSucceeds = true;
  final handlers = <String, JavaScriptHandlerCallback>{};

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains('checkSelection')) selectionCalls++;
    if (source.startsWith('window._ereaderSnapshot ?')) {
      snapshotCalls++;
      final pending = pendingSnapshot;
      pendingSnapshot = null;
      return pending == null ? snapshot : pending.future;
    }
    return true;
  }

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) {
    if (functionBody.contains("_ereaderRestoreOffset")) {
      restoreArguments = arguments;
      return Future.value(CallAsyncJavaScriptResult(value: restoreSucceeds));
    }
    if (functionBody.contains("_ereaderSnapshot")) {
      return Future.value(CallAsyncJavaScriptResult(value: snapshot));
    }
    seekArguments = arguments;
    return completed.future;
  }

  @override
  void dispose({bool isKeepAlive = false}) {}
}

void main() {
  late Directory temp;
  late Box<BookModel> books;
  late BookRepository repository;

  setUpAll(() {
    Hive.registerAdapter(BookModelAdapter());
    InAppWebViewPlatform.instance = _TestWebViewPlatform();
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('epub-reader-test-');
    Hive.init(temp.path);
    books = await Hive.openBox<BookModel>('books');
    await Hive.openBox('settings');
    await File('${temp.path}/book.epub').writeAsBytes([80, 75]);
    await books.put(
      'book',
      BookModel(
        id: 'book',
        title: 'Test book',
        author: 'Author',
        localPath: '${temp.path}/book.epub',
        format: 'epub',
        lastReadProgress: 0.2,
        lastReadCfi: 'epubcfi(/6/2!/4/2/1:0)',
      ),
    );
    repository = BookRepository(booksBox: books);
  });
  tearDown(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  Future<EpubViewer> open(
    WidgetTester tester, {
    bool ready = true,
    bool showControls = true,
    _SeekWebViewController? native,
  }) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: repository,
          child: const MaterialApp(home: EpubReaderScreen(bookId: 'book')),
        ),
      );
      await tester
          .widget<EpubViewer>(find.byType(EpubViewer))
          .epubSource
          .epubData;
    });
    final viewer = tester.widget<EpubViewer>(find.byType(EpubViewer));
    if (native != null) {
      viewer.epubController.setWebViewController(
        InAppWebViewController.fromPlatform(platform: native),
      );
    }
    viewer.onEpubLoaded!();
    await tester.pump();
    if (ready) {
      viewer.onLocationLoaded?.call();
      await tester.pump();
    }
    if (!showControls) return viewer;
    await tester.tapAt(const Offset(400, 300));
    // Older reader gets its tap notification from the native WebView.
    if (find.byType(Slider).evaluate().isEmpty) {
      viewer.onTouchUp?.call(0.5, 0.5);
    }
    await tester.pump();
    return viewer;
  }

  EpubLocation location(double progress) => EpubLocation(
    startCfi: 'epubcfi(/6/4!/4/2/1:0)',
    endCfi: 'epubcfi(/6/4!/4/2/1:30)',
    progress: progress,
  );

  Future<void> close(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await books.flush();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('percentage seeking waits for the location index', (
    tester,
  ) async {
    try {
      final viewer = await open(tester, ready: false);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      viewer.onLocationLoaded!.call();
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    } finally {
      await close(tester);
    }
  });

  testWidgets('incoming positions cannot move the thumb during dragging', (
    tester,
  ) async {
    try {
      final viewer = await open(tester);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.2);
      slider.onChanged!(0.8);
      await tester.pump();
      viewer.onRelocated!(location(0.25));
      viewer.onChaptersLoaded!([]);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.8);
      expect(find.text('80.0%'), findsOneWidget);
    } finally {
      await close(tester);
    }
  });

  testWidgets('backgrounding during dragging saves the actual position', (
    tester,
  ) async {
    try {
      final viewer = await open(tester);
      viewer.onRelocated!(location(0.25));
      await tester.pump(const Duration(milliseconds: 200));
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.25);
      slider.onChanged!(0.8);
      await tester.pump();
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await books.flush();
      });
      await tester.pump();
      expect(books.get('book')!.lastReadProgress, 0.25);
      expect(books.get('book')!.lastReadCfi, 'epubcfi(/6/4!/4/2/1:0)');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'progress updates animate without rebuilding the reader scaffold',
    (tester) async {
      try {
        final viewer = await open(tester);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        viewer.onRelocated!(location(0.6));
        await tester.pump();
        expect(
          identical(
            scaffold,
            tester.widget<Scaffold>(find.byType(Scaffold).first),
          ),
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 60));
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          allOf(greaterThan(0.2), lessThan(0.6)),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          closeTo(0.6, 0.001),
        );
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets('a scroll finishing in the centre does not open controls', (
    tester,
  ) async {
    try {
      await open(tester);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      await tester.dragFrom(const Offset(400, 450), const Offset(0, -150));
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
    } finally {
      await close(tester);
    }
  });

  testWidgets('chapter styles are registered before content is displayed', (
    tester,
  ) async {
    try {
      final viewer = await open(tester);
      expect(viewer.displaySettings!.theme!.customCss, isNotNull);
      // The Android custom page-swipe handler prevents native touch scrolling.
      // Keep it disabled even though this reader does not use page snapping.
      expect(viewer.displaySettings!.useSnapAnimationAndroid, isTrue);
      expect(viewer.displaySettings!.snap, isFalse);
      expect(
        viewer.displaySettings!.theme!.customCss?['body'],
        containsPair('line-height', '1.5 !important'),
      );
      expect(
        viewer.displaySettings!.theme!.customCss?['img'],
        containsPair('max-width', '100% !important'),
      );
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'seeking holds the preview until the actual position is confirmed',
    (tester) async {
      try {
        final viewer = await open(tester);
        final native = _SeekWebViewController();
        viewer.epubController.setWebViewController(
          InAppWebViewController.fromPlatform(platform: native),
        );
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChangeStart!(0.2);
        slider.onChanged!(0.8);
        slider.onChangeEnd!(0.8);
        await tester.pump();
        viewer.onRelocated!(location(0.25));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.widget<Slider>(find.byType(Slider)).value, 0.8);
        expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
        expect(native.seekArguments, {'progress': 0.8});
        expect(books.get('book')!.lastReadProgress, 0.2);
        native.completed.complete(
          CallAsyncJavaScriptResult(
            value: {
              'startCfi': 'epubcfi(/6/10!/4/2/1:0)',
              'endCfi': 'epubcfi(/6/10!/4/2/1:30)',
              'progress': 0.79,
            },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          closeTo(0.79, 0.001),
        );
        expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
        await tester.runAsync(() async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await books.flush();
        });
        expect(books.get('book')!.lastReadProgress, 0.79);
        expect(books.get('book')!.lastReadCfi, 'epubcfi(/6/10!/4/2/1:0)');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets('failed seeking restores progress and allows another attempt', (
    tester,
  ) async {
    try {
      final viewer = await open(tester);
      final native = _SeekWebViewController();
      viewer.epubController.setWebViewController(
        InAppWebViewController.fromPlatform(platform: native),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.2);
      slider.onChanged!(0.8);
      slider.onChangeEnd!(0.8);
      native.completed.complete(
        CallAsyncJavaScriptResult(error: 'Chapter failed to load'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        closeTo(0.2, 0.001),
      );
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
      expect(
        find.text('Could not jump to that position. Try again.'),
        findsOneWidget,
      );
      expect(books.get('book')!.lastReadProgress, 0.2);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'late seek completion after closing does not update the disposed reader',
    (tester) async {
      final viewer = await open(tester);
      final native = _SeekWebViewController();
      viewer.epubController.setWebViewController(
        InAppWebViewController.fromPlatform(platform: native),
      );
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(0.8);
      await close(tester);
      native.completed.complete(
        CallAsyncJavaScriptResult(
          value: {
            'startCfi': 'epubcfi(/6/10!/4/2/1:0)',
            'endCfi': 'epubcfi(/6/10!/4/2/1:30)',
            'progress': 0.79,
          },
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(books.get('book')!.lastReadProgress, 0.2);
    },
  );

  testWidgets('late native positions cannot overwrite a confirmed seek', (
    tester,
  ) async {
    try {
      final native = _SeekWebViewController();
      final viewer = await open(tester, native: native);
      expect(native.handlers.containsKey('ereaderRelocated'), isTrue);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.2);
      slider.onChanged!(0.8);
      slider.onChangeEnd!(0.8);
      native.completed.complete(
        CallAsyncJavaScriptResult(
          value: {
            'startCfi': 'epubcfi(/6/10!/4/2/1:0)',
            'endCfi': 'epubcfi(/6/10!/4/2/1:30)',
            'progress': 0.79,
            'sequence': 5,
          },
        ),
      );
      await tester.pump();
      // This native message was emitted before the seek but delivered late.
      native.handlers['ereaderRelocated']!([
        {...location(0.25).toJson(), 'sequence': 4},
      ]);
      // The dependency also sends its slower XPath-based callback.
      viewer.onRelocated!(location(0.25));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        closeTo(0.79, 0.001),
      );
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await books.flush();
      });
      expect(books.get('book')!.lastReadProgress, 0.79);
      expect(books.get('book')!.lastReadCfi, 'epubcfi(/6/10!/4/2/1:0)');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'native progress ignores out-of-order delivery and accepts newer scrolling',
    (tester) async {
      try {
        final native = _SeekWebViewController();
        await open(tester, native: native);
        expect(native.handlers.containsKey('ereaderRelocated'), isTrue);
        native.handlers['ereaderRelocated']!([
          {...location(0.6).toJson(), 'sequence': 2},
        ]);
        native.handlers['ereaderRelocated']!([
          {...location(0.3).toJson(), 'sequence': 1},
        ]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          closeTo(0.6, 0.001),
        );
        native.handlers['ereaderRelocated']!([
          {...location(0.4).toJson(), 'sequence': 3},
        ]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          closeTo(0.4, 0.001),
        );
      } finally {
        await close(tester);
      }
    },
  );
  testWidgets('newer native position wins over a delayed seek response', (
    tester,
  ) async {
    try {
      final native = _SeekWebViewController();
      await open(tester, native: native);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.2);
      slider.onChanged!(0.8);
      slider.onChangeEnd!(0.8);
      native.handlers['ereaderRelocated']!([
        {...location(0.81).toJson(), 'sequence': 6},
      ]);
      native.completed.complete(
        CallAsyncJavaScriptResult(
          value: {
            'startCfi': 'epubcfi(/6/10!/4/2/1:0)',
            'endCfi': 'epubcfi(/6/10!/4/2/1:30)',
            'progress': 0.79,
            'sequence': 5,
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        closeTo(0.81, 0.001),
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await books.flush();
      });
      expect(books.get('book')!.lastReadProgress, 0.81);
      expect(books.get('book')!.lastReadCfi, 'epubcfi(/6/4!/4/2/1:0)');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    } finally {
      await close(tester);
    }
  });
  testWidgets('reading before percentage indexing completes is saved', (
    tester,
  ) async {
    final viewer = await open(tester, ready: false);
    viewer.onRelocated!(location(0));
    await close(tester);
    expect(books.get('book')!.lastReadCfi, 'epubcfi(/6/4!/4/2/1:0)');
    expect(books.get('book')!.lastReadProgress, 0.2);
  });

  testWidgets(
    'backgrounding captures the visible position before a late event',
    (tester) async {
      try {
        final native = _SeekWebViewController();
        await open(tester, native: native);
        native.snapshot = {
          ...location(0.63).toJson(),
          'sequence': 4,
          'offset': -9.5,
        };
        await tester.runAsync(() async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await books.flush();
        });
        expect(books.get('book')!.lastReadProgress, 0.63);
        expect(books.get('book')!.lastReadCfi, location(0.63).startCfi);
        expect(books.get('book')!.epubCheckpoint!['offset'], -9.5);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } finally {
        await close(tester);
      }
    },
  );
  testWidgets(
    'reopening restores the saved line offset with its matching CFI',
    (tester) async {
      try {
        await tester.runAsync(() async {
          await Hive.box('settings').put('epubViewport:book', {
            'cfi': books.get('book')!.lastReadCfi,
            'offset': -9.5,
          });
        });
        final native = _SeekWebViewController();
        await open(tester, native: native);
        expect(native.restoreArguments, {
          'cfi': books.get('book')!.lastReadCfi,
          'offset': -9.5,
          'layout': null,
        });
      } finally {
        await close(tester);
      }
    },
  );
  testWidgets('periodic checkpoint samples scrolling with controls hidden', (
    tester,
  ) async {
    try {
      final native = _SeekWebViewController();
      await open(tester, native: native);
      await tester.tapAt(const Offset(400, 300));
      native.snapshot = {
        ...location(0.67).toJson(),
        'sequence': 8,
        'offset': -12.0,
      };
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 6));
        await books.flush();
      });
      expect(books.get('book')!.lastReadProgress, 0.67);
    } finally {
      await close(tester);
    }
  });

  for (final closing in [true, false]) {
    testWidgets(
      '${closing ? 'close' : 'background'} resamples after an overlapping older capture',
      (tester) async {
        try {
          final native = _SeekWebViewController();
          await open(tester, native: native);
          final pending = Completer<dynamic>();
          native.pendingSnapshot = pending;
          await tester.runAsync(() async {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            expect(native.snapshotCalls, 1);
            if (closing) {
              tester
                  .widget<IconButton>(
                    find.widgetWithIcon(IconButton, Icons.arrow_back),
                  )
                  .onPressed!();
            } else {
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
            }
            native.snapshot = {
              ...location(0.72).toJson(),
              'sequence': 3,
              'offset': -7.0,
            };
            pending.complete({
              ...location(0.3).toJson(),
              'sequence': 2,
              'offset': -3.0,
            });
            await Future<void>.delayed(const Duration(milliseconds: 30));
            await books.flush();
          });
          expect(native.snapshotCalls, 2);
          expect(books.get('book')!.lastReadProgress, 0.72);
          expect(books.get('book')!.epubCheckpoint!['offset'], -7.0);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } finally {
          await close(tester);
        }
      },
    );
  }

  testWidgets('stalled opening offers recovery without removing viewer', (
    tester,
  ) async {
    try {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          RepositoryProvider.value(
            value: repository,
            child: const MaterialApp(home: EpubReaderScreen(bookId: 'book')),
          ),
        );
        await tester
            .widget<EpubViewer>(find.byType(EpubViewer))
            .epubSource
            .epubData;
        await Future<void>.delayed(const Duration(seconds: 16));
      });
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Return to library'), findsOneWidget);
      expect(find.byType(EpubViewer), findsOneWidget);
      final first = tester.widget<EpubViewer>(find.byType(EpubViewer));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(
        identical(
          first.epubController,
          tester.widget<EpubViewer>(find.byType(EpubViewer)).epubController,
        ),
        isFalse,
      );
      first.onRelocated!(location(0.9));
      await close(tester);
      expect(books.get('book')!.lastReadProgress, 0.2);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'closing immediately after long press cancels delayed selection work',
    (tester) async {
      final native = _SeekWebViewController();
      await open(tester, native: native);
      _TestWebView.latest!.onWebViewCreated!(
        InAppWebViewController.fromPlatform(platform: native),
      );
      _TestWebView.latest!.onLongPressHitTestResult!(
        InAppWebViewController.fromPlatform(platform: native),
        InAppWebViewHitTestResult(
          type: InAppWebViewHitTestResultType.UNKNOWN_TYPE,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
      expect(native.selectionCalls, 0);
    },
  );
  testWidgets('reflow events cannot replace the confirmed passage', (
    tester,
  ) async {
    try {
      final native = _SeekWebViewController();
      await open(tester, native: native);
      native.handlers['ereaderRelocated']!([
        {...location(0.4).toJson(), 'sequence': 1, 'offset': -6.0},
      ]);
      native.handlers['ereaderReflow']!([true]);
      native.handlers['ereaderRelocated']!([
        {...location(0.9).toJson(), 'sequence': 2, 'offset': 200.0},
      ]);
      native.snapshot = {...location(0.9).toJson(), 'sequence': 3};
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await books.flush();
      });
      expect(books.get('book')!.lastReadProgress, 0.4);
      expect(books.get('book')!.epubCheckpoint!['offset'], -6.0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      native.handlers['ereaderReflow']!([false]);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'renderer recovery creates fresh viewers and stops after two attempts',
    (tester) async {
      try {
        var viewer = await open(tester);
        final original = viewer;
        for (var attempt = 0; attempt < 2; attempt++) {
          viewer.onRendererTerminated!();
          await tester.pump();
          await tester.pump();
          final next = tester.widget<EpubViewer>(find.byType(EpubViewer));
          expect(
            identical(next.epubController, viewer.epubController),
            isFalse,
          );
          viewer = next;
        }
        original.onRelocated!(location(0.99));
        viewer.onRendererTerminated!();
        await tester.pump();
        await tester.pump();
        expect(find.byType(EpubViewer), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
        expect(books.get('book')!.lastReadProgress, 0.2);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(find.byType(EpubViewer), findsOneWidget);
      } finally {
        await close(tester);
      }
    },
  );
  testWidgets(
    'failed initial restoration retains the saved checkpoint and exposes retry',
    (tester) async {
      try {
        final native = _SeekWebViewController()..restoreSucceeds = false;
        final viewer = await open(tester, native: native, showControls: false);
        viewer.onRelocated!(location(0.95));
        native.snapshot = {...location(0.95).toJson(), 'sequence': 9};
        expect(find.text('Retry'), findsOneWidget);
        await close(tester);
        expect(books.get('book')!.lastReadProgress, 0.2);
        expect(books.get('book')!.lastReadCfi, 'epubcfi(/6/2!/4/2/1:0)');
      } finally {
        await close(tester);
      }
    },
  );
}

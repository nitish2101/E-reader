import 'dart:async';
import 'dart:io';
import 'package:ereader/data/models/book_model.dart';
import 'package:ereader/data/repositories/book_repository.dart';
import 'package:ereader/data/statistics/reading_statistics_repository.dart';
import 'package:ereader/data/statistics/reading_tracker.dart';
import 'package:ereader/presentation/reader/pdf_reader_screen.dart';
import 'package:ereader/presentation/statistics/reader_activity_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pdfrx/pdfrx.dart';
import '../support/pdfium_test_setup.dart';

// Keep PDF loading, the real screen and its callbacks; control only page
// animation completion to reproduce pdfrx's cancelled/in-flight futures.
class _PageNavigation extends PdfViewerController {
  final PdfDocument _document;
  _PageNavigation(this._document);
  @override
  PdfDocument get document => _document;
  final pending = <Completer<void>>[];
  @override
  int? get pageNumber => 1;
  @override
  Future<void> goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    final completed = Completer<void>();
    pending.add(completed);
    return completed.future;
  }
}

String _twoPagePdf() {
  var output = '%PDF-1.4\n';
  final offsets = <int>[0];
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents 5 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents 5 0 R >>',
    '<< /Length 0 >>\nstream\n\nendstream',
  ];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(output.length);
    output += '${index + 1} 0 obj\n${objects[index]}\nendobj\n';
  }
  final xref = output.length;
  output += 'xref\n0 6\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    output += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  return '${output}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
}

void main() {
  late Directory directory;
  late BookRepository books;
  late ReadingStatisticsRepository statistics;
  late ReadingTracker tracker;
  var elapsed = Duration.zero;
  setUpAll(() async {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookModelAdapter());
    await initializeTestPdfium();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdf-clock-');
    Hive.init(directory.path);
    final box = await Hive.openBox<BookModel>('books');
    await Hive.openBox('settings');
    final file = await File(
      '${directory.path}/book.pdf',
    ).writeAsString(_twoPagePdf());
    await box.put(
      'book',
      BookModel(
        id: 'book',
        title: 'PDF statistics',
        author: 'Fixture',
        localPath: file.path,
        format: 'pdf',
      ),
    );
    books = BookRepository(booksBox: box);
    statistics = ReadingStatisticsRepository(
      await Hive.openBox('readingStatistics'),
    );
    elapsed = Duration.zero;
    tracker = ReadingTracker(statistics, elapsed: () => elapsed);
  });
  tearDown(() async {
    tracker.dispose();
    await statistics.flush();
    statistics.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<_PageNavigation> open(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: books),
          RepositoryProvider.value(value: tracker),
        ],
        child: const MaterialApp(home: PdfReaderScreen(bookId: 'book')),
      ),
    );
    // Bound the real PDF loading wait instead of assuming one frame is ready.
    for (var attempt = 0; attempt < 100; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      final sliders = find.byType(Slider);
      if (sliders.evaluate().isNotEmpty) break;
    }
    expect(find.byType(Slider), findsOneWidget);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final navigation = _PageNavigation(viewer.controller!.document);
    viewer.params.onViewerReady!(viewer.controller!.document, navigation);
    await tester.pump();
    return navigation;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await statistics.flush();
    await Hive.box<BookModel>('books').flush();
  }

  testWidgets('PDF drag stays paused after animation completes until release', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final navigation = await open(tester);
      final slider = tester.widget<Slider>(find.byType(Slider));
      elapsed = const Duration(seconds: 10);
      slider.onChangeStart?.call(1);
      slider.onChanged!(2);
      navigation.pending.single.complete();
      await tester.pump();
      elapsed = const Duration(seconds: 40);
      tracker.checkpoint();
      await statistics.flush();
      expect(statistics.total.inSeconds, 10);
      slider.onChangeEnd?.call(2);
      elapsed = const Duration(seconds: 50);
      await close(tester);
      expect(statistics.total.inSeconds, 20);
    });
  });
  testWidgets('PDF release waits for failed final navigation then resumes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final navigation = await open(tester);
      final slider = tester.widget<Slider>(find.byType(Slider));
      elapsed = const Duration(seconds: 10);
      slider.onChangeStart?.call(1);
      slider.onChanged!(2);
      elapsed = const Duration(seconds: 40);
      slider.onChangeEnd?.call(2);
      tracker.checkpoint();
      await statistics.flush();
      expect(statistics.total.inSeconds, 10);
      elapsed = const Duration(seconds: 60);
      navigation.pending.single.completeError(StateError('Navigation failed'));
      await tester.pump();
      elapsed = const Duration(seconds: 70);
      await close(tester);
      expect(statistics.total.inSeconds, 20);
    });
  });
  testWidgets('PDF cancelled older animation cannot unblock a held drag', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final navigation = await open(tester);
      final slider = tester.widget<Slider>(find.byType(Slider));
      elapsed = const Duration(seconds: 10);
      slider.onChangeStart?.call(1);
      slider.onChanged!(2); // This future is cancelled and never completes.
      slider.onChanged!(1);
      navigation.pending.last.complete();
      await tester.pump();
      elapsed = const Duration(seconds: 40);
      tracker.checkpoint();
      await statistics.flush();
      expect(statistics.total.inSeconds, 10);
      slider.onChangeEnd?.call(1);
      elapsed = const Duration(seconds: 50);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      await close(tester);
      expect(statistics.total.inSeconds, 20);
    });
  });

  testWidgets(
    'PDF retry pauses through reload and rejects replaced viewer readiness',
    (tester) async {
      await tester.runAsync(() async {
        final oldController = await open(tester);
        final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
        final document = viewer.controller!.document;
        final recovery = viewer.params.errorBannerBuilder!(
          tester.element(find.byType(PdfViewer)),
          StateError('Failed reader'),
          StackTrace.empty,
          viewer.documentRef,
        );
        final controls =
            ((recovery as Center).child as Padding).child as Column;
        final retry = controls.children.whereType<FilledButton>().single;
        elapsed = const Duration(seconds: 10);
        viewer.params.onDocumentChanged!(null);
        await File('${directory.path}/book.pdf').delete();
        retry.onPressed!();
        for (
          var attempt = 0;
          attempt < 100 && find.text('Retry').evaluate().isEmpty;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
        expect(find.text('Retry'), findsOneWidget);
        elapsed = const Duration(seconds: 40);
        viewer.params.onViewerReady!(document, oldController);
        await tester.pump();
        expect(
          tester
              .widget<ReaderActivityScope>(find.byType(ReaderActivityScope))
              .controller
              .ready,
          isFalse,
        );
        elapsed = const Duration(seconds: 60);
        tracker.checkpoint();
        await statistics.flush();
        expect(statistics.total.inSeconds, 10);
        await File('${directory.path}/book.pdf').writeAsString(_twoPagePdf());
        await tester.tap(find.text('Retry'));
        for (var attempt = 0; attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 20));
          if (tester
              .widget<ReaderActivityScope>(find.byType(ReaderActivityScope))
              .controller
              .ready) {
            break;
          }
        }
        expect(
          tester
              .widget<ReaderActivityScope>(find.byType(ReaderActivityScope))
              .controller
              .ready,
          isTrue,
        );
        elapsed = const Duration(seconds: 70);
        await close(tester);
        expect(statistics.total.inSeconds, 20);
        expect(Hive.box<BookModel>('books').get('book')!.lastReadPage, 1);
      });
    },
  );
}

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ereader/data/models/book_model.dart';
import 'package:ereader/data/repositories/book_repository.dart';
import 'package:ereader/data/repositories/settings_repository.dart';
import 'package:ereader/data/repositories/store_repository.dart';
import 'package:ereader/presentation/store/store_screen.dart';

class ScreenCatalog extends StoreRepository {
  bool offline = false;
  bool emptyPage = false;
  @override
  Future<StoreSearchResult> searchBooks({
    required String query,
    Set<Format> formats = const {Format.pdf, Format.epub},
    int page = 1,
    Set<BookSource> sources = const {BookSource.gutenberg},
    CancelToken? cancelToken,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 25),
    void Function(StoreSearchResult)? onPartialResult,
  }) async {
    if (offline) {
      throw const StoreRepositoryException('Catalog is offline. Try again.');
    }
    if (emptyPage) return const StoreSearchResult(books: [], hasMore: true);
    return const StoreSearchResult(
      books: [
        UnifiedBook(
          title: 'Pride and Prejudice',
          author: 'Jane Austen',
          extension: 'epub',
          source: BookSource.gutenberg,
          downloadUrl: 'https://example.org/1.epub',
        ),
        UnifiedBook(
          title: 'A long nonfiction book title for small displays',
          author: 'An author with a longer name',
          extension: 'pdf',
          source: BookSource.libgen,
          md5: '2',
        ),
      ],
    );
  }
}

void main() {
  late Directory temp;
  late Box<BookModel> books;
  late ScreenCatalog repository;
  setUpAll(() => Hive.registerAdapter(BookModelAdapter()));
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('store-screen-');
    Hive.init(temp.path);
    books = await Hive.openBox<BookModel>('books');
    await Hive.openBox('settings');
    repository = ScreenCatalog();
  });
  tearDown(() async {
    repository.dispose();
    await Hive.close();
    await temp.delete(recursive: true);
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<StoreRepository>.value(value: repository),
          RepositoryProvider<BookRepository>.value(
            value: BookRepository(booksBox: books),
          ),
          RepositoryProvider<SettingsRepository>.value(
            value: SettingsRepository(),
          ),
        ],
        child: const MaterialApp(home: StoreScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('book controls and cards fit a phone and tablet', (tester) async {
    for (final size in [const Size(360, 640), const Size(1024, 768)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await mount(tester);
      expect(find.text('Store'), findsOneWidget);
      expect(find.text('Pride and Prejudice'), findsWidgets);
      expect(find.text('PDF'), findsWidgets);
      expect(find.text('EPUB'), findsWidgets);
      expect(find.text('Project Gutenberg'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('filtered empty page still offers pagination', (tester) async {
    repository.emptyPage = true;
    await mount(tester);
    expect(find.text('Check the next page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('source error displays retry instead of no-results copy', (
    tester,
  ) async {
    repository.offline = true;
    await mount(tester);
    expect(find.text('Search unavailable'), findsOneWidget);
    expect(find.text('Retry search'), findsOneWidget);
    expect(find.text('No matching books'), findsNothing);
    repository.offline = false;
    await tester.tap(find.text('Retry search'));
    await tester.pumpAndSettle();
    expect(find.text('Pride and Prejudice'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Anna search offers an interactive browser even if other catalogs work',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField), 'Pride');
      await tester.pumpAndSettle();
      expect(find.text("Open Anna's Archive"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

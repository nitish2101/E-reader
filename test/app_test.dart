import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ereader/data/models/book_model.dart';
import 'package:ereader/main.dart';
import 'package:ereader/presentation/navigation/app_router.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('app-start-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookModelAdapter());
    await Hive.openBox<BookModel>('books');
    await Hive.openBox('settings');
    await Hive.openBox('readingStatistics');
    AppRouter.router.go('/');
  });
  tearDown(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  testWidgets('app opens offline and store errors remain recoverable', (
    tester,
  ) async {
    try {
      await tester.pumpWidget(const EReaderApp());
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(find.text('Store'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Search unavailable'), findsOneWidget);
      expect(find.text('Retry search'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'labelled Stats opens a local dashboard without changing progress',
    (tester) async {
      await tester.runAsync(
        () => Hive.box<BookModel>('books').put(
          'existing',
          BookModel(
            id: 'existing',
            title: 'Existing book',
            author: 'Author',
            localPath: '/book.epub',
            format: 'epub',
            lastReadProgress: 0.42,
          ),
        ),
      );
      try {
        await tester.pumpWidget(const EReaderApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stats'));
        await tester.pumpAndSettle();
        expect(find.text('Reading statistics'), findsOneWidget);
        expect(find.text('Total recorded'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('This week'), findsOneWidget);
        expect(find.text('Last 7 days'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Existing book'), 200);
        await tester.tap(find.text('Existing book'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('No recorded sessions yet'),
          150,
        );
        await tester.pumpAndSettle();
        expect(find.text('No recorded sessions yet'), findsOneWidget);
        expect(find.textContaining('WPM: Unavailable'), findsOneWidget);
        expect(
          Hive.box<BookModel>('books').get('existing')!.lastReadProgress,
          0.42,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('unavailable statistics storage leaves the library usable', (
    tester,
  ) async {
    await tester.runAsync(() => Hive.box('readingStatistics').close());
    try {
      await tester.pumpWidget(const EReaderApp());
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsWidgets);
      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();
      expect(find.textContaining('storage is unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}

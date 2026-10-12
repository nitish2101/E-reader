import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ereader/data/models/book_model.dart';
import 'package:ereader/main.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('app-start-');
    Hive.init(temp.path);
    Hive.registerAdapter(BookModelAdapter());
    await Hive.openBox<BookModel>('books');
    await Hive.openBox('settings');
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
      expect(find.byType(NavigationBar), findsOneWidget);
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
}

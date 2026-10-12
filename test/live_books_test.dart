import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/data/repositories/store_repository.dart';
import 'package:ereader/data/services/book_file_validator.dart';

// Opt-in only: the default suite is offline and deterministic.
void main() {
  test(
    'live Standard Ebooks search and validated public-domain EPUB download',
    () async {
      HttpOverrides.global = null;
      final directory = await Directory.systemTemp.createTemp('live-standard-');
      final repository = StoreRepository(booksDirectory: () async => directory);
      try {
        final result = await repository.searchBooks(
          query: 'Pride and Prejudice',
          sources: {BookSource.standardEbooks},
          formats: {Format.epub},
        );
        expect(result.books, isNotEmpty);
        final book = result.books.firstWhere(
          (b) => b.title == 'Pride and Prejudice',
        );
        final path = await repository.downloadBook(
          book: book,
          cancelToken: CancelToken(),
          onProgress: (_) {},
        );
        await BookFileValidator.validate(File(path), 'epub');
        expect(await File(path).length(), greaterThan(1000));
        // ignore: avoid_print
        print(
          'Live Standard Ebooks verified: ${book.title}, ${await File(path).length()} bytes',
        );
      } finally {
        repository.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_BOOK_TESTS'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'live LibGen modern book catalog returns parsed files',
    () async {
      HttpOverrides.global = null;
      final repository = StoreRepository(libgenMirrors: ['https://libgen.li']);
      try {
        final result = await repository.searchBooks(
          query: 'Pride and Prejudice',
          sources: {BookSource.libgen},
        );
        expect(result.books, isNotEmpty);
        expect(
          result.books.every((b) => b.isSupported && b.md5 != null),
          isTrue,
        );
        expect(result.hasMore, isTrue);
        // ignore: avoid_print
        print(
          'Live LibGen verified: ${result.books.length} supported book files',
        );
      } finally {
        repository.dispose();
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_BOOK_TESTS'),
    timeout: const Timeout(Duration(minutes: 1)),
  );
  test(
    'live Gutenberg title search and validated EPUB download',
    () async {
      HttpOverrides.global =
          null; // Use normal TLS, outside Flutter's test HTTP stub.
      final directory = await Directory.systemTemp.createTemp('live-book-');
      final repository = StoreRepository(booksDirectory: () async => directory);
      try {
        final result = await repository.searchBooks(
          query: 'Pride and Prejudice',
          sources: {BookSource.gutenberg},
        );
        expect(result.books, isNotEmpty);
        final book = result.books.first;
        // ignore: avoid_print
        print('Live download: ${book.downloadUrl}');
        final path = await repository.downloadBook(
          book: book,
          cancelToken: CancelToken(),
          onProgress: (_) {},
        );
        await BookFileValidator.validate(File(path), 'epub');
        expect(await File(path).length(), greaterThan(1000));
        // ignore: avoid_print
        print(
          'Live verified: ${book.title}, ${await File(path).length()} bytes',
        );
      } finally {
        repository.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_BOOK_TESTS'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

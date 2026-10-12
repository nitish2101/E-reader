import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/data/repositories/store_repository.dart';
import '../support/fake_http_adapter.dart';

void main() {
  late Dio dio;
  late FakeHttpAdapter adapter;
  late StoreRepository repository;
  setUp(() {
    dio = Dio();
    adapter = FakeHttpAdapter();
    dio.httpClientAdapter = adapter;
    repository = StoreRepository(dio: dio);
  });
  tearDown(() => repository.dispose());

  test('Retry immediately recontacts mirrors paused after an outage', () async {
    adapter.respond = (_) => ResponseBody.fromString('Forbidden', 403);
    await expectLater(
      repository.searchBooks(query: 'first', sources: {BookSource.libgen}),
      throwsA(isA<StoreRepositoryException>()),
    );
    final failedRequests = adapter.requests.length;
    adapter.respond = (_) => ResponseBody.fromString('<p>No results</p>', 200);
    await expectLater(
      repository.searchBooks(query: 'second', sources: {BookSource.libgen}),
      throwsA(isA<StoreRepositoryException>()),
    );
    expect(adapter.requests.length, failedRequests);
    final result = await repository.searchBooks(
      query: 'second',
      sources: {BookSource.libgen},
      forceRefresh: true,
    );
    expect(result.books, isEmpty);
    expect(adapter.requests.length, failedRequests + 1);
  });

  test('source outage is an error rather than no results', () async {
    adapter.respond = (_) => ResponseBody.fromString('Forbidden', 403);
    await expectLater(
      repository.searchBooks(query: 'Dune', sources: {BookSource.annasArchive}),
      throwsA(isA<StoreRepositoryException>()),
    );
  });

  test(
    'Gutenberg builds encoded queries and parses downloadable EPUB books',
    () async {
      adapter.respond = (request) {
        expect(request.queryParameters['search'], 'Pride & Prejudice');
        return ResponseBody.fromString(
          jsonEncode({
            'next': null,
            'results': [
              {
                'id': 1342,
                'title': 'Pride and Prejudice',
                'media_type': 'Text',
                'authors': [
                  {'name': 'Austen, Jane'},
                ],
                'subjects': ['Fiction'],
                'languages': ['en'],
                'formats': {
                  'application/epub+zip':
                      'https://www.gutenberg.org/ebooks/1342.epub3.images',
                  'image/jpeg':
                      'https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg',
                },
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      };
      final result = await repository.searchBooks(
        query: '  Pride & Prejudice  ',
        sources: {BookSource.gutenberg},
      );
      expect(result.books.single.title, 'Pride and Prejudice');
      expect(result.books.single.extension, 'epub');
      expect(result.hasMore, isFalse);
    },
  );

  test(
    'partial outage keeps successful results and reports a warning',
    () async {
      adapter.respond = (request) => request.uri.host == 'gutendex.com'
          ? ResponseBody.fromString(
              '{"next":null,"results":[]}',
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            )
          : ResponseBody.fromString('Forbidden', 403);
      final result = await repository.searchBooks(
        query: 'test',
        sources: {BookSource.gutenberg, BookSource.annasArchive},
      );
      expect(result.books, isEmpty);
      expect(result.warnings, hasLength(1));
    },
  );

  test('unknown HTML layout is an outage, not an empty search', () async {
    adapter.respond = (_) =>
        ResponseBody.fromString('<html>Challenge</html>', 200);
    await expectLater(
      repository.searchBooks(query: 'test', sources: {BookSource.annasArchive}),
      throwsA(isA<StoreRepositoryException>()),
    );
  });
}

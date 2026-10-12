import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../models/store_book.dart';
import 'cancellation.dart';

/// Public catalog; the OPDS feed requires a separate authenticated subscription.
class StandardEbooksProvider {
  final Dio dio;
  StandardEbooksProvider(this.dio);

  Future<StoreSearchResult> search(
    String query,
    Set<Format> formats,
    int page,
    CancelToken token,
  ) async {
    token.throwIfCancellationRequested();
    if (!formats.contains(Format.epub)) {
      return const StoreSearchResult(books: []);
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await dio.get<String>(
          const String.fromEnvironment(
            'STANDARD_EBOOKS_URL',
            defaultValue: 'https://standardebooks.org/ebooks',
          ),
          queryParameters: {
            'query': query,
            'page': page,
            'per-page': 24,
            'sort': query.isEmpty ? 'popularity' : 'relevance',
          },
          cancelToken: token,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        return parse(response.data ?? '', response.realUri, page);
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (attempt == 1 ||
            CancelToken.isCancel(error) ||
            (status != null && status < 500)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        token.throwIfCancellationRequested();
      }
    }
    throw const StoreRepositoryException('Standard Ebooks is unavailable.');
  }

  static StoreSearchResult parse(String body, Uri base, int page) {
    final document = html.parse(body);
    final catalog = document.querySelector('main.ebooks');
    if (catalog == null) {
      throw const StoreRepositoryException(
        'Standard Ebooks returned a challenge or an unrecognized catalog.',
      );
    }
    final books = <UnifiedBook>[];
    for (final entry in catalog.querySelectorAll(
      '.ebooks-list li[typeof="schema:Book"]',
    )) {
      final titleLink = entry.querySelector('p > a[property="schema:url"]');
      final href = titleLink?.attributes['href'];
      final title = titleLink?.text.trim() ?? '';
      if (href == null || title.isEmpty) continue;
      final detail = base.resolve(href);
      if (detail.host != base.host || !detail.path.startsWith('/ebooks/')) {
        continue;
      }
      final author = entry.querySelector('.author')?.text.trim();
      final cover = entry.querySelector('img')?.attributes['src'];
      books.add(
        UnifiedBook(
          title: title,
          author: author?.isNotEmpty == true ? author! : 'Unknown Author',
          extension: 'epub',
          source: BookSource.standardEbooks,
          detailUrl: detail.toString(),
          coverUrl: cover == null ? null : base.resolve(cover).toString(),
          language: 'en',
        ),
      );
    }
    if (books.isEmpty && catalog.querySelector('.no-results') == null) {
      throw const StoreRepositoryException(
        'Standard Ebooks search layout has changed.',
      );
    }
    return StoreSearchResult(
      books: books,
      hasMore: catalog.querySelectorAll('a[href]').any((link) {
        final uri = base.resolve(link.attributes['href']!);
        return uri.host == base.host &&
            uri.path == base.path &&
            int.tryParse(uri.queryParameters['page'] ?? '') == page + 1;
      }),
    );
  }
}

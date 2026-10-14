import '../services/cancellation.dart';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/store_book.dart';
import '../services/book_search_providers.dart';
import '../services/book_download_service.dart';
export '../models/store_book.dart';

class StoreRepository {
  final Dio _dio;
  late final BookSearchProviders _providers;
  late final BookDownloadService _downloads;
  final Map<String, Future<Map<String, String>> Function(Uri)>
  _browserSessions = {};
  List<Uri> get annaMirrors =>
      _providers.annaMirrors.map(Uri.parse).toList(growable: false);
  bool isAnnaUrl(Uri url) =>
      annaMirrors.any((mirror) => mirror.origin == url.origin);

  Uri annaSearchUrl(String query, Set<Format> formats) => _providers
      .preferredAnnaMirror
      .resolve('search')
      .replace(
        queryParameters: {
          'q': query,
          'ext': formats.map((f) => f.name).toList(),
          'content': ['book_fiction', 'book_nonfiction', 'book_unknown'],
        },
      );

  void registerBrowserSession(
    Uri url,
    Future<Map<String, String>> Function(Uri) headers,
  ) {
    _browserSessions[url.origin] = headers;
    if (isAnnaUrl(url)) {
      _providers.preferAnnaMirror(url);
      _cache.clear();
    }
  }

  final Map<String, ({DateTime fetchedAt, StoreSearchResult result})> _cache =
      {};

  StoreRepository({
    Dio? dio,
    Future<Directory> Function()? booksDirectory,
    List<String>? annaMirrors,
    List<String>? libgenMirrors,
    String? gutenbergUrl,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 6),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 6),
               headers: {
                 'User-Agent': 'EReader/1.2 (book reader)',
                 'Accept-Language': 'en',
               },
             ),
           ) {
    _providers = BookSearchProviders(
      _dio,
      requestHeaders: _sessionHeaders,
      annaMirrors:
          annaMirrors ??
          const [
            String.fromEnvironment(
              'ANNA_MIRROR',
              defaultValue: 'https://annas-archive.gl',
            ),
            'https://annas-archive.pk',
            'https://annas-archive.gd',
          ],
      libgenMirrors:
          libgenMirrors ??
          const [
            String.fromEnvironment(
              'LIBGEN_MIRROR',
              defaultValue: 'https://libgen.li',
            ),
            'https://libgen.is',
            'https://libgen.rs',
            'https://libgen.st',
          ],
      gutenbergUrl:
          gutenbergUrl ??
          const String.fromEnvironment(
            'GUTENDEX_URL',
            defaultValue: 'https://gutendex.com/books/',
          ),
    );
    _downloads = BookDownloadService(
      _dio,
      booksDirectory ??
          () async {
            final appDir = await getApplicationDocumentsDirectory();
            return Directory('${appDir.path}/books');
          },
      requestHeaders: _sessionHeaders,
    );
  }

  Future<Map<String, String>> _sessionHeaders(Uri uri) async =>
      await _browserSessions[uri.origin]?.call(uri) ?? {};

  Future<StoreSearchResult> searchBooks({
    required String query,
    Set<Format> formats = const {Format.pdf, Format.epub},
    int page = 1,
    Set<BookSource> sources = const {
      BookSource.annasArchive,
      BookSource.libgen,
      BookSource.gutenberg,
      BookSource.standardEbooks,
    },
    CancelToken? cancelToken,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 25),
    void Function(StoreSearchResult)? onPartialResult,
  }) async {
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (sources.isEmpty || formats.isEmpty) {
      throw const StoreRepositoryException(
        'Select at least one source and format.',
      );
    }
    final formatKey = formats.map((f) => f.name).toList()..sort();
    final sourceKey = sources.map((s) => s.name).toList()..sort();
    final key = '$normalized|$formatKey|$sourceKey|$page';
    cancelToken?.throwIfCancellationRequested();
    if (forceRefresh) _providers.resetMirrorHealth();
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(minutes: 15)) {
      return cached.result;
    }
    final completed = <StoreSearchResult>[];
    final outcomes = await Future.wait(
      sources.map((source) async {
        final token = CancelToken();
        // Each source has its own deadline; one failing catalog cannot block all others.
        final timer = Timer(timeout, () => token.cancel('Source timed out'));
        final cancellation = cancelToken?.whenCancel.then((error) {
          if (!token.isCancelled) token.cancel(error.error);
        });
        unawaited(cancellation);
        try {
          final result = await _providers.search(
            source,
            normalized,
            formats,
            page,
            token,
          );
          completed.add(result);
          if (result.books.isNotEmpty && cancelToken?.isCancelled != true) {
            onPartialResult?.call(
              StoreSearchResult(
                books: deduplicate(
                  completed
                      .expand((r) => r.books)
                      .where(
                        (b) =>
                            b.isSupported &&
                            formats.any((f) => f.name == b.extension),
                      )
                      .toList(),
                ),
                hasMore: completed.any((r) => r.hasMore),
              ),
            );
          }
          return (result: result, warning: null as String?);
        } catch (error) {
          cancelToken?.throwIfCancellationRequested();
          return (
            result: null as StoreSearchResult?,
            warning: '${source.label}: ${_sourceError(error)}',
          );
        } finally {
          timer.cancel();
        }
      }),
    );
    cancelToken?.throwIfCancellationRequested();
    final results = outcomes
        .map((o) => o.result)
        .whereType<StoreSearchResult>()
        .toList();
    final warnings = outcomes
        .map((o) => o.warning)
        .whereType<String>()
        .toList();
    if (results.isEmpty) {
      throw StoreRepositoryException(
        'Search could not reach the selected sources. ${warnings.join(' ')}',
      );
    }
    final result = StoreSearchResult(
      books: deduplicate(
        results
            .expand((r) => r.books)
            .where(
              (book) =>
                  book.isSupported &&
                  formats.any((format) => format.name == book.extension),
            )
            .toList(),
      ),
      hasMore: results.any((r) => r.hasMore),
      warnings: warnings,
    );
    // Do not cache partial outages: Retry should actually recontact the failed source.
    if (warnings.isEmpty) {
      _cache.remove(key);
      _cache[key] = (fetchedAt: DateTime.now(), result: result);
      if (_cache.length > 50) _cache.remove(_cache.keys.first);
    }
    return result;
  }

  static String _sourceError(Object error) {
    if (error is StoreRepositoryException) return error.message;
    if (error is DioException) {
      if (error.type == DioExceptionType.cancel ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'timed out. Try again or choose another source.';
      }
      return 'unavailable${error.response?.statusCode == null ? '' : ' (HTTP ${error.response!.statusCode})'}.';
    }
    return 'returned an unreadable response.';
  }

  static List<UnifiedBook> deduplicate(List<UnifiedBook> books) {
    final seen = <String>{};
    return books.where((book) => seen.add(book.id)).toList();
  }

  Future<String> downloadBook({
    required UnifiedBook book,
    required CancelToken cancelToken,
    required void Function(double) onProgress,
    Set<Uri> verifiedPages = const {},
  }) => _downloads.download(
    book,
    cancelToken,
    onProgress,
    verifiedPages: verifiedPages,
  );

  void clearCache() {
    _cache.clear();
    _providers.resetMirrorHealth();
  }

  void dispose() => _dio.close(force: true);
}

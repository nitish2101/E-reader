import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import '../models/store_book.dart';
import 'cancellation.dart';
import 'standard_ebooks_provider.dart';

class BookSearchProviders {
  static const defaultAnnaMirrors = [
    'https://annas-archive.gl',
    'https://annas-archive.pk',
    'https://annas-archive.gd',
  ];
  static const defaultLibgenMirrors = [
    'https://libgen.li',
    'https://libgen.is',
    'https://libgen.rs',
    'https://libgen.st',
  ];
  final Dio dio;
  final List<String> annaMirrors;
  final List<String> libgenMirrors;
  final String gutenbergUrl;
  final Map<String, ({DateTime until, String reason})> _failedMirrors = {};
  final Map<BookSource, String> _preferredMirrors = {};

  void resetMirrorHealth() => _failedMirrors.clear();

  BookSearchProviders(
    this.dio, {
    this.annaMirrors = defaultAnnaMirrors,
    this.libgenMirrors = defaultLibgenMirrors,
    this.gutenbergUrl = 'https://gutendex.com/books/',
  });

  Future<StoreSearchResult> search(
    BookSource source,
    String query,
    Set<Format> formats,
    int page,
    CancelToken token,
  ) async {
    if (source == BookSource.gutenberg) {
      return _gutenberg(query, formats, page, token);
    }
    if (source == BookSource.standardEbooks) {
      return StandardEbooksProvider(dio).search(query, formats, page, token);
    }
    final configured = source == BookSource.annasArchive
        ? annaMirrors
        : libgenMirrors;
    final preferred = _preferredMirrors[source];
    final mirrors = <String>{
      if (configured.contains(preferred)) preferred!,
      ...configured,
    };
    final failures = <String>[];
    for (final mirror in mirrors) {
      token.throwIfCancellationRequested();
      final failure = _failedMirrors[mirror];
      if (failure != null && DateTime.now().isBefore(failure.until)) {
        failures.add('${Uri.parse(mirror).host}: ${failure.reason}');
        continue;
      }
      final modernLibgen =
          source == BookSource.libgen && Uri.parse(mirror).host == 'libgen.li';
      try {
        final response = await dio.get<String>(
          '$mirror/${source == BookSource.annasArchive
              ? 'search'
              : modernLibgen
              ? 'index.php'
              : 'search.php'}',
          queryParameters: source == BookSource.annasArchive
              ? {
                  'q': query,
                  'page': page,
                  'ext': formats.map((f) => f.name).toList(),
                  'content': [
                    'book_fiction',
                    'book_nonfiction',
                    'book_unknown',
                  ],
                }
              : modernLibgen
              ? {
                  'req': query,
                  'page': page,
                  'curtab': 'f',
                  'topics[]': ['l', 'f', 'r'],
                }
              : {'req': query, 'page': page, 'res': 25, 'column': 'def'},
          cancelToken: token,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 6),
            sendTimeout: const Duration(seconds: 6),
          ),
        );
        final body = response.data ?? '';
        final result = source == BookSource.annasArchive
            ? parseAnna(body, response.realUri, page)
            : parseLibgen(body, response.realUri, page);
        _failedMirrors.remove(mirror);
        _preferredMirrors[source] = mirror;
        return result;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) rethrow;
        final status = error.response?.statusCode;
        final reason = status == 403
            ? 'access denied (HTTP 403 / anti-bot protection)'
            : status == 429
            ? 'rate limited (HTTP 429)'
            : status != null
            ? 'HTTP $status'
            : error.type == DioExceptionType.connectionError
            ? 'connection or DNS failure'
            : 'connection timed out';
        _recordFailure(mirror, reason, failures);
      } on StoreRepositoryException catch (error) {
        _recordFailure(mirror, error.message, failures);
      }
    }
    throw StoreRepositoryException(
      '${failures.join('; ')}. Try another source or Retry. '
      'Failed mirrors are paused for two minutes.',
    );
  }

  void _recordFailure(String mirror, String reason, List<String> failures) {
    _failedMirrors[mirror] = (
      until: DateTime.now().add(const Duration(minutes: 2)),
      reason: reason,
    );
    failures.add('${Uri.parse(mirror).host}: $reason');
  }

  Future<StoreSearchResult> _gutenberg(
    String query,
    Set<Format> formats,
    int page,
    CancelToken token,
  ) async {
    final response = await _getGutenberg(query, page, token, formats);
    final data = response.data;

    if (data is! Map || data['results'] is! List) {
      throw const StoreRepositoryException(
        'Project Gutenberg returned an invalid catalog response.',
      );
    }
    final books = <UnifiedBook>[];
    for (final entry in data['results'] as List) {
      if (entry is! Map ||
          entry['formats'] is! Map ||
          entry['title'] is! String) {
        continue;
      }
      if (entry['media_type'] != 'Text') continue;
      final subjects = (entry['subjects'] as List? ?? [])
          .join(' ')
          .toLowerCase();
      if (RegExp(
        r'\b(comic books|comic strips|manga|manhwa)\b',
      ).hasMatch(subjects)) {
        continue;
      }
      final links = entry['formats'] as Map;
      for (final format in formats) {
        final url =
            links[format == Format.epub
                ? 'application/epub+zip'
                : 'application/pdf'];
        if (url is! String || !isHttpUrl(url)) continue;
        books.add(
          UnifiedBook(
            title: entry['title'] as String,
            author: (entry['authors'] as List? ?? [])
                .whereType<Map>()
                .map((a) => a['name'])
                .whereType<String>()
                .join(', '),
            extension: format.name,
            source: BookSource.gutenberg,
            downloadUrl: url,
            alternateUrls:
                format == Format.epub &&
                    entry['id'] is int &&
                    Uri.parse(url).host == 'www.gutenberg.org'
                ? [
                    'https://www.gutenberg.org/ebooks/${entry['id']}.epub.images',
                    'https://www.gutenberg.org/ebooks/${entry['id']}.epub.noimages',
                  ]
                : const [],
            detailUrl: 'https://www.gutenberg.org/ebooks/${entry['id']}',
            coverUrl: links['image/jpeg'] as String?,
            language: (entry['languages'] as List? ?? []).join(', '),
          ),
        );
      }
    }
    return StoreSearchResult(books: books, hasMore: data['next'] != null);
  }

  Future<Response<dynamic>> _getGutenberg(
    String query,
    int page,
    CancelToken token,
    Set<Format> formats,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await dio.get(
          gutenbergUrl,
          queryParameters: {
            'search': query,
            'page': page,
            if (formats.length == 1 && formats.contains(Format.pdf))
              'mime_type': 'application/pdf',
          },
          cancelToken: token,
          options: Options(responseType: ResponseType.json),
        );
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (attempt == 1 ||
            CancelToken.isCancel(error) ||
            (status != null && status < 500)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    throw const StoreRepositoryException('Project Gutenberg is unavailable.');
  }

  static StoreSearchResult parseAnna(String body, Uri base, int page) {
    _rejectChallenge(body);
    // Some catalog rows are lazy-loaded inside HTML comments.
    final document = html.parse(
      body.replaceAll('<!--', '').replaceAll('-->', ''),
    );
    final books = <UnifiedBook>[];
    final seen = <String>{};
    var hasReadableMetadata = false;
    for (final link in document.querySelectorAll('a[href*="/md5/"]')) {
      final href = link.attributes['href'] ?? '';
      final md5 = RegExp(r'/md5/([a-fA-F0-9]{32})').firstMatch(href)?.group(1);
      if (md5 == null || link.text.trim().isEmpty || seen.contains(md5)) {
        continue;
      }
      Element? row = link.parent;
      Element? metadataElement;
      while (row != null &&
          row.localName != 'body' &&
          row.localName != 'html') {
        metadataElement = row.querySelector('.text-gray-800, .text-gray-500');
        if (metadataElement != null) break;
        // Never borrow metadata from a neighboring result when this layout changes.
        if (row.classes.contains('flex') &&
            (row.classes.contains('pt-3') ||
                row.classes.contains('border-b'))) {
          break;
        }
        row = row.parent;
      }
      if (row == null || metadataElement == null) continue;
      hasReadableMetadata = true;
      final metadata = metadataElement.text;
      if (RegExp(
        r'\b(comic|comics|manga|manhwa|magazine|musical score)\b',
        caseSensitive: false,
      ).hasMatch(metadata)) {
        continue;
      }
      final format = RegExp(
        r'\b(EPUB|PDF)\b',
        caseSensitive: false,
      ).firstMatch(metadata)?.group(1)?.toLowerCase();
      if (format == null) continue;
      seen.add(md5);
      final author = row.querySelector('a[href^="/search?q="]')?.text.trim();
      final cover =
          (row.querySelector('img') ?? row.parent?.querySelector('img'))
              ?.attributes['src'];
      books.add(
        UnifiedBook(
          title: link.text.trim(),
          author: author?.isNotEmpty == true ? author! : 'Unknown Author',
          md5: md5,
          extension: format,
          source: BookSource.annasArchive,
          coverUrl: cover == null ? null : base.resolve(cover).toString(),
          detailUrl: base.resolve(href).toString(),
          fileSize: RegExp(
            r'\d+(?:\.\d+)?\s*[KMG]B',
            caseSensitive: false,
          ).firstMatch(metadata)?.group(0),
        ),
      );
    }
    final text = document.body?.text.toLowerCase() ?? '';
    if (books.isEmpty &&
        !text.contains('no files found') &&
        !text.contains('no results found') &&
        !hasReadableMetadata) {
      throw const StoreRepositoryException(
        'The catalog is blocked or its search layout has changed.',
      );
    }
    return StoreSearchResult(
      books: books,
      hasMore: _hasNext(document, base, page),
    );
  }

  static StoreSearchResult parseLibgen(String body, Uri base, int page) {
    _rejectChallenge(body);
    final document = html.parse(body);
    final table = document.querySelector(
      'table#tablelibgen, table.c, table[rules="rows"]',
    );
    if (table == null) {
      final fileCount = document
          .querySelector('.nav-tabs a.active[href*="curtab=f"] .badge')
          ?.text
          .trim();
      if ((document.body?.text.toLowerCase() ?? '').contains('no results') ||
          (document.querySelector('form#formlibgen') != null &&
              fileCount == '0')) {
        return const StoreSearchResult(books: []);
      }
      throw const StoreRepositoryException(
        'LibGen is blocked or its search layout has changed.',
      );
    }
    final modern = table.id == 'tablelibgen';
    final books = <UnifiedBook>[];
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 9) continue;
      if (modern && cells[0].querySelector('.badge a[title="Book"]') == null) {
        continue;
      }
      final format = cells[modern ? 7 : 8].text.trim().toLowerCase();
      if (format != 'pdf' && format != 'epub') continue;
      final links = row.querySelectorAll('a[href]');
      final md5Link = links.where(
        (a) => (a.attributes['href'] ?? '').toLowerCase().contains('md5='),
      );
      if (md5Link.isEmpty) continue;
      final detail = base.resolve(md5Link.first.attributes['href']!);
      final md5 = detail.queryParameters.entries
          .where((e) => e.key.toLowerCase() == 'md5')
          .map((e) => e.value)
          .firstOrNull;
      if (md5 == null || !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(md5)) continue;
      final titleCell = cells[modern ? 0 : 2];
      final titleLink = modern
          ? titleCell.querySelector('a[href*="edition.php"]')?.clone(true)
          : titleCell.querySelector('a')?.clone(true);
      if (modern) {
        for (final marker in titleLink?.querySelectorAll('i') ?? <Element>[]) {
          marker.remove();
        }
      }
      final title = titleLink?.text.trim() ?? titleCell.text.trim();
      if (title.isEmpty) continue;
      books.add(
        UnifiedBook(
          title: title,
          author: cells[1].text.trim(),
          md5: md5,
          extension: format,
          source: BookSource.libgen,
          year: cells[modern ? 3 : 4].text.trim(),
          language: cells[modern ? 4 : 6].text.trim(),
          fileSize: cells[modern ? 6 : 7].text.trim(),
          detailUrl: detail.toString(),
          alternateUrls: md5Link
              .map((a) => base.resolve(a.attributes['href']!).toString())
              .toSet()
              .toList(),
        ),
      );
    }
    return StoreSearchResult(
      books: books,
      hasMore:
          _hasNext(document, base, page) ||
          (modern && _hasLibgenNext(body, page)),
    );
  }

  static bool _hasLibgenNext(String body, int page) {
    final match = RegExp(
      r'new\s+Paginator\s*\(\s*"[^"]+"\s*,\s*(\d+)\s*,\s*\d+\s*,\s*(\d+)',
    ).firstMatch(body);
    return match != null &&
        int.parse(match.group(2)!) == page &&
        page < int.parse(match.group(1)!);
  }

  static void _rejectChallenge(String body) {
    final document = html.parse(body);
    final title = document.querySelector('title')?.text.toLowerCase() ?? '';
    if (title.contains('ddos-guard') ||
        title.contains('just a moment') ||
        title.contains('attention required') ||
        document.querySelector('#challenge-form') != null) {
      throw const StoreRepositoryException(
        'The server requires browser verification (anti-bot challenge).',
      );
    }
  }

  static bool _hasNext(Document document, Uri base, int page) =>
      document.querySelectorAll('a[href]').any((link) {
        final uri = base.resolve(link.attributes['href']!);
        return int.tryParse(uri.queryParameters['page'] ?? '') == page + 1;
      });

  static bool isHttpUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }
}

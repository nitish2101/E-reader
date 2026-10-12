import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/data/services/book_search_providers.dart';
import 'package:ereader/data/models/store_book.dart';
import 'package:dio/dio.dart';
import '../support/fake_http_adapter.dart';
import 'package:ereader/data/services/standard_ebooks_provider.dart';

void main() {
  final base = Uri.parse('https://catalog.example.org');
  test('Standard Ebooks layout failures are not reported as empty searches', () {
    expect(
      () => StandardEbooksProvider.parse(
        '<main class="ebooks"><p>Catalog unavailable</p></main>',
        base,
        1,
      ),
      throwsA(isA<StoreRepositoryException>()),
    );
    expect(
      StandardEbooksProvider.parse(
        '<main class="ebooks"><p class="no-results">No ebooks matched your filters.</p></main>',
        base,
        1,
      ).books,
      isEmpty,
    );
  });
  test(
    'Anna detail links without readable row metadata indicate layout failure',
    () {
      expect(
        () => BookSearchProviders.parseAnna(
          '<a href="/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">A book</a>',
          base,
          1,
        ),
        throwsA(isA<StoreRepositoryException>()),
      );
    },
  );
  test(
    'Standard Ebooks searches public catalog and resolves edition metadata',
    () async {
      final dio = Dio();
      final adapter = FakeHttpAdapter();
      dio.httpClientAdapter = adapter;
      adapter.respond = (request) {
        expect(request.uri.path, '/ebooks');
        expect(request.queryParameters['query'], 'Pride & Prejudice');
        return ResponseBody.fromString(
          '<main class="ebooks"><ol class="ebooks-list"><li typeof="schema:Book">'
          '<p><a property="schema:url" href="/ebooks/jane-austen/pride-and-prejudice">'
          '<span property="schema:name">Pride and Prejudice</span></a></p>'
          '<p class="author"><span property="schema:name">Jane Austen</span></p>'
          '<img src="/cover.jpg"></li></ol>'
          '<a href="/ebooks?query=Pride&page=2">Next</a></main>',
          200,
        );
      };
      final source = BookSource.values.firstWhere(
        (s) => s.name == 'standardEbooks',
      );
      final result = await BookSearchProviders(
        dio,
      ).search(source, 'Pride & Prejudice', {Format.epub}, 1, CancelToken());
      expect(result.books.single.title, 'Pride and Prejudice');
      expect(result.books.single.author, 'Jane Austen');
      expect(
        result.books.single.detailUrl,
        'https://standardebooks.org/ebooks/jane-austen/pride-and-prejudice',
      );
      expect(
        result.books.single.coverUrl,
        'https://standardebooks.org/cover.jpg',
      );
      expect(result.hasMore, isTrue);
      dio.close();
    },
  );
  test(
    'Standard Ebooks PDF-only searches do not contact EPUB catalog',
    () async {
      final dio = Dio();
      final adapter = FakeHttpAdapter();
      dio.httpClientAdapter = adapter;
      adapter.respond = (_) =>
          throw StateError('Must not request EPUB catalog');
      final source = BookSource.values.firstWhere(
        (s) => s.name == 'standardEbooks',
      );
      final result = await BookSearchProviders(
        dio,
      ).search(source, 'test', {Format.pdf}, 1, CancelToken());
      expect(result.books, isEmpty);
      expect(result.hasMore, isFalse);
      dio.close();
    },
  );
  const modernTable =
      '<table id="tablelibgen"><thead><tr>'
      '<th>Title</th><th>Author(s)</th><th>Publisher</th><th>Year</th>'
      '<th>Language</th><th>Pages</th><th>Size</th><th>Ext.</th><th>Mirrors</th>'
      '</tr></thead><tbody><tr>'
      '<td><b>Series</b><a href="edition.php?id=1">Pride and Prejudice <i>1</i></a>'
      '<span class="badge"><a title="Book">b</a></span></td><td>Jane Austen</td>'
      '<td>Publisher</td><td>1813</td><td>English</td><td>300</td><td>2 MB</td>'
      '<td>epub</td><td><a href="/ads.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">1</a></td>'
      '</tr></tbody></table>'
      '<script>new Paginator("paginator_example_top", 3, 25, 1, "/index.php?page=");</script>';
  test('LibGen modern zero-file count is a genuine empty search', () {
    final result = BookSearchProviders.parseLibgen(
      '<form id="formlibgen"></form><ul class="nav-tabs">'
      '<li><a class="nav-link active" href="/index.php?req=absent&curtab=f">'
      'Files <span class="badge">0</span></a></li></ul>',
      base,
      1,
    );
    expect(result.books, isEmpty);
    expect(result.hasMore, isFalse);
  });
  test('LibGen li requests the modern route with only book topics', () async {
    final dio = Dio();
    final adapter = FakeHttpAdapter();
    dio.httpClientAdapter = adapter;
    adapter.respond = (request) {
      expect(request.uri.path, '/index.php');
      expect(request.queryParameters['curtab'], 'f');
      expect(request.uri.queryParametersAll['topics[]'], ['l', 'f', 'r']);
      return ResponseBody.fromString(modernTable, 200);
    };
    final result = await BookSearchProviders(
      dio,
      libgenMirrors: ['https://libgen.li'],
    ).search(BookSource.libgen, 'Pride', {Format.epub}, 1, CancelToken());
    expect(result.books.single.title, 'Pride and Prejudice');
    dio.close();
  });
  test('LibGen modern catalog parses titles and JavaScript pagination', () {
    final result = BookSearchProviders.parseLibgen(modernTable, base, 1);
    expect(result.books.single.title, 'Pride and Prejudice');
    expect(result.books.single.author, 'Jane Austen');
    expect(result.books.single.extension, 'epub');
    expect(result.books.single.year, '1813');
    expect(result.hasMore, isTrue);
  });
  test('challenge pages with incidental catalog links are outages', () {
    expect(
      () => BookSearchProviders.parseAnna(
        '<title>DDoS-Guard</title><a href="/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">Book</a>',
        base,
        1,
      ),
      throwsA(isA<StoreRepositoryException>()),
    );
  });
  test(
    'Anna sends repeated filters without bracketed parameter names',
    () async {
      final dio = Dio();
      final adapter = FakeHttpAdapter();
      dio.httpClientAdapter = adapter;
      adapter.respond = (_) =>
          ResponseBody.fromString('<p>No files found</p>', 200);
      await BookSearchProviders(
        dio,
        annaMirrors: ['https://anna.example'],
      ).search(
        BookSource.annasArchive,
        'test',
        {Format.epub, Format.pdf},
        1,
        CancelToken(),
      );
      final uri = adapter.requests.single.uri;
      expect(uri.queryParametersAll['ext'], ['epub', 'pdf']);
      expect(uri.queryParametersAll['content'], hasLength(3));
      dio.close();
    },
  );
  test(
    'working mirror is preferred after an outage on subsequent queries',
    () async {
      final dio = Dio();
      final adapter = FakeHttpAdapter();
      dio.httpClientAdapter = adapter;
      adapter.respond = (request) => request.uri.host == 'dead.example'
          ? ResponseBody.fromString('Forbidden', 403)
          : ResponseBody.fromString('<p>No results</p>', 200);
      final providers = BookSearchProviders(
        dio,
        libgenMirrors: ['https://dead.example', 'https://healthy.example'],
      );
      for (final query in ['one', 'two']) {
        await providers.search(
          BookSource.libgen,
          query,
          {Format.epub},
          1,
          CancelToken(),
        );
      }
      expect(
        adapter.requests.where((r) => r.uri.host == 'dead.example'),
        hasLength(1),
      );
      dio.close();
    },
  );
  test(
    'Anna parser keeps book rows, excludes comic rows and detects next page',
    () {
      String row(String id, String category, String format) =>
          '<div class="flex"><a href="/md5/$id"><img src="/cover.jpg"></a>'
          '<div><a class="js-vim-focus" href="/md5/$id">Book title</a>'
          '<a href="/search?q=Author">Author</a><div class="text-gray-800">English · $format · $category</div></div></div>';
      final result = BookSearchProviders.parseAnna(
        '${row('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Book (fiction)', 'EPUB')}<!--${row('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'Book (nonfiction)', 'PDF')}-->${row('cccccccccccccccccccccccccccccccc', 'Comic', 'PDF')}<a href="/search?q=test&page=2">Next</a>',
        base,
        1,
      );
      expect(result.books, hasLength(2));
      expect(result.books.first.author, 'Author');
      expect(result.hasMore, isTrue);
    },
  );
  test('Anna reads nested metadata instead of format words in a title', () {
    String row(String id, String category) =>
        '<div class="flex pt-3"><a href="/md5/$id"><img src="/cover.jpg"></a>'
        '<div class="max-w-full"><div><a class="js-vim-focus" href="/md5/$id">PDF Comics</a>'
        '<a href="/search?q=Author">Author</a></div><div><div class="text-gray-800">English · EPUB · $category</div></div></div></div>';
    final comic = BookSearchProviders.parseAnna(
      row('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Comic'),
      base,
      1,
    );
    expect(comic.books, isEmpty);
    final book = BookSearchProviders.parseAnna(
      row('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'Book (fiction)'),
      base,
      1,
    );
    expect(book.books.single.extension, 'epub');
    expect(book.books.single.coverUrl, 'https://catalog.example.org/cover.jpg');
  });
  test('Anna never borrows a neighboring book format for an unsupported file', () {
    String row(String id, String format) =>
        '<div class="flex pt-3"><div><a class="js-vim-focus" href="/md5/$id">Book</a>'
        '</div><div class="text-gray-800">English · $format · Book (fiction)</div></div>';
    final result = BookSearchProviders.parseAnna(
      '<div>${row('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'AZW3')}'
      '${row('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'EPUB')}</div>',
      base,
      1,
    );
    expect(result.books, hasLength(1));
    expect(result.books.single.md5, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
  });
  test('Anna actual no-results is allowed', () {
    expect(
      BookSearchProviders.parseAnna('<p>No files found</p>', base, 1).books,
      isEmpty,
    );
  });
  test('LibGen parses book table and excludes unsupported archives', () {
    final result = BookSearchProviders.parseLibgen(
      '<table class="c"><tr>'
      '<td>1</td><td>Author</td><td><a href="book">Title</a></td><td>Publisher</td>'
      '<td>2026</td><td>100</td><td>English</td><td>2 MB</td><td>epub</td>'
      '<td><a href="/ads.php?md5=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">1</a></td>'
      '</tr></table>',
      base,
      1,
    );
    expect(result.books.single.title, 'Title');
    expect(result.books.single.extension, 'epub');
    expect(
      result.books.single.detailUrl,
      contains('https://catalog.example.org/ads.php'),
    );
    expect(result.hasMore, isFalse);
  });
}

import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/data/repositories/store_repository.dart';
import 'package:ereader/data/services/book_download_service.dart';
import '../support/fake_http_adapter.dart';
import '../support/valid_pdf.dart';
import '../support/pdfium_test_setup.dart';

void main() {
  late Directory directory;
  late Dio dio;
  late FakeHttpAdapter adapter;
  late BookDownloadService service;
  final pdf = validPdf();
  setUpAll(initializeTestPdfium);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('book-transfer-');
    dio = Dio();
    adapter = FakeHttpAdapter();
    dio.httpClientAdapter = adapter;
    service = BookDownloadService(dio, () async => directory);
  });
  tearDown(() async {
    dio.close();
    await directory.delete(recursive: true);
  });
  test(
    'Anna resolves a free partner download without browsing or import',
    () async {
      adapter.respond = (request) {
        if (request.uri.path.startsWith('/md5/')) {
          return ResponseBody.fromString(
            '<a href="/slow_download/abc/0/0">Slow Partner Server #1</a>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        }
        if (request.uri.path.startsWith('/slow_download/')) {
          return ResponseBody.fromString(
            '<a href="https://files.example/book.pdf">Download now</a>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        }
        return ResponseBody.fromString(pdf, 200);
      };
      final path = await service.download(
        const UnifiedBook(
          title: 'Anna book',
          extension: 'pdf',
          source: BookSource.annasArchive,
          detailUrl: 'https://annas-archive.pk/md5/abc',
        ),
        CancelToken(),
        (_) {},
      );
      expect(await File(path).readAsString(), pdf);
      expect(adapter.requests.map((r) => r.uri.path), [
        '/md5/abc',
        '/slow_download/abc/0/0',
        '/book.pdf',
      ]);
      expect(await directory.list().toList(), hasLength(1));
    },
  );
  test(
    'blocked Anna download identifies the exact page needing verification',
    () async {
      adapter.respond = (_) => ResponseBody.fromString('Forbidden', 403);
      await expectLater(
        service.download(
          const UnifiedBook(
            title: 'Blocked',
            extension: 'pdf',
            source: BookSource.annasArchive,
            detailUrl: 'https://annas-archive.pk/md5/abc',
            md5: 'abc',
          ),
          CancelToken(),
          (_) {},
        ),
        throwsA(
          isA<BrowserVerificationRequired>().having(
            (e) => e.url.toString(),
            'blocked page',
            'https://annas-archive.pk/md5/abc',
          ),
        ),
      );
      expect(await directory.list().toList(), isEmpty);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'Anna partner redirect loop returns the first page for verification',
    () async {
      adapter.respond = (request) {
        if (request.uri.path.startsWith('/md5/')) {
          return ResponseBody.fromString(
            '<a href="/slow_download/abc/0/0">Slow Partner Server #1</a>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        }
        final partner = int.parse(request.uri.pathSegments.last);
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['/slow_download/abc/0/${partner + 1}'],
          },
        );
      };
      await expectLater(
        service.download(
          const UnifiedBook(
            title: 'Redirected Anna book',
            extension: 'epub',
            source: BookSource.annasArchive,
            detailUrl: 'https://annas-archive.gl/md5/abc',
          ),
          CancelToken(),
          (_) {},
        ),
        throwsA(
          isA<BrowserVerificationRequired>().having(
            (e) => e.url.toString(),
            'verification page',
            'https://annas-archive.gl/slow_download/abc/0/0',
          ),
        ),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );
  test('Anna Save and read-more anchors are not download links', () {
    expect(
      BookDownloadService.extractDownloadLinks(
        '<a href="#" onclick="save()">Save</a>'
        '<a href="">Read more…</a>'
        '<a href="https://files.example/book.epub">📚 Download now</a>',
        Uri.parse('https://annas-archive.gl/slow_download/abc/0/0'),
      ),
      ['https://files.example/book.epub'],
    );
  });
  test('Anna copy-only partner controls resolve book URLs without JavaScript', () {
    expect(
      BookDownloadService.extractDownloadLinks(
        '<main><span><button onclick="navigator.clipboard.writeText(value)">copy</button>'
        '<span>http://files.example:6060/book.epub?token=example&amp;name=short</span></span>'
        '<span><button onclick="navigator.clipboard.writeText(value)">copy</button>'
        '<span>https://files.example/short.epub</span></span>'
        '<span><button onclick="navigator.clipboard.writeText(value)">copy</button>'
        '<span>javascript:alert(1)</span></span></main>',
        Uri.parse('https://annas-archive.gl/slow_download/abc/0/1'),
      ),
      [
        'http://files.example:6060/book.epub?token=example&name=short',
        'https://files.example/short.epub',
      ],
    );
  });
  test(
    'a failed verified partner falls back to an untried partner page',
    () async {
      adapter.respond = (request) {
        if (request.uri.host == 'files.example') {
          throw const HandshakeException('Certificate hostname mismatch');
        }
        if (request.uri.path.startsWith('/md5/')) {
          return ResponseBody.fromString(
            '<a href="/slow_download/abc/0/0">Slow Partner Server #1</a>'
            '<a href="/slow_download/abc/0/1">Slow Partner Server #2</a>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        }
        return ResponseBody.fromString(
          '<p>Please wait 20 seconds.</p>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      };
      await expectLater(
        service.download(
          const UnifiedBook(
            title: 'Verified partner failed',
            extension: 'epub',
            source: BookSource.annasArchive,
            downloadUrl: 'https://files.example/book.epub',
            detailUrl: 'https://annas-archive.gl/md5/abc',
          ),
          CancelToken(),
          (_) {},
          verifiedPages: {
            Uri.parse('https://annas-archive.gl/slow_download/abc/0/0?'),
          },
        ),
        throwsA(
          isA<BrowserVerificationRequired>().having(
            (e) => e.url.toString(),
            'next partner',
            'https://annas-archive.gl/slow_download/abc/0/1',
          ),
        ),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );
  test(
    'rejects HTML even with a binary MIME type and removes partial file',
    () async {
      adapter.respond = (_) => ResponseBody.fromString(
        '<html>login</html>',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/octet-stream'],
        },
      );
      await expectLater(
        service.download(
          const UnifiedBook(
            title: 'book',
            extension: 'pdf',
            source: BookSource.gutenberg,
            downloadUrl: 'https://example.org/book',
          ),
          CancelToken(),
          (_) {},
        ),
        throwsA(isA<StoreRepositoryException>()),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );
  test('tries alternate URL when the first download is invalid', () async {
    adapter.respond = (request) => ResponseBody.fromString(
      request.uri.path == '/bad' ? '<html>invalid</html>' : pdf,
      200,
    );
    final path = await service.download(
      const UnifiedBook(
        title: '../same?book',
        extension: 'pdf',
        source: BookSource.libgen,
        downloadUrl: 'https://example.org/bad',
        alternateUrls: ['https://example.org/good'],
      ),
      CancelToken(),
      (_) {},
    );
    expect(await File(path).readAsString(), pdf);
    expect(adapter.requests, hasLength(2));
    expect(path, startsWith(directory.path));
    expect(await directory.list().toList(), hasLength(1));
  });
  test(
    'retries a temporary server error once before publishing a book',
    () async {
      adapter.respond = (_) => adapter.requests.length == 1
          ? ResponseBody.fromString('Gateway timeout', 504)
          : ResponseBody.fromString(pdf, 200);
      final path = await service.download(
        const UnifiedBook(
          title: 'book',
          extension: 'pdf',
          source: BookSource.gutenberg,
          downloadUrl: 'https://example.org/book.pdf',
        ),
        CancelToken(),
        (_) {},
      );
      expect(await File(path).readAsString(), pdf);
      expect(adapter.requests, hasLength(2));
      expect(await directory.list().toList(), hasLength(1));
    },
  );
  test('repeated server failures stop after the bounded retry', () async {
    adapter.respond = (_) => ResponseBody.fromString('Unavailable', 503);
    await expectLater(
      service.download(
        const UnifiedBook(
          title: 'book',
          extension: 'pdf',
          source: BookSource.gutenberg,
          downloadUrl: 'https://example.org/book.pdf',
        ),
        CancelToken(),
        (_) {},
      ),
      throwsA(isA<StoreRepositoryException>()),
    );
    expect(adapter.requests, hasLength(2));
    expect(await directory.list().toList(), isEmpty);
  });
  test('resolves relative landing page controls before downloading', () async {
    adapter.respond = (request) => request.uri.path == '/landing'
        ? ResponseBody.fromString(
            '<a href="/file.pdf">GET</a>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          )
        : ResponseBody.fromString(pdf, 200);
    final path = await service.download(
      const UnifiedBook(
        title: 'book',
        extension: 'pdf',
        source: BookSource.libgen,
        detailUrl: 'https://example.org/landing',
      ),
      CancelToken(),
      (_) {},
    );
    expect(await File(path).readAsString(), pdf);
    expect(adapter.requests.last.uri.path, '/file.pdf');
  });
  test('cancelled transfer publishes no file', () async {
    adapter.respond = (_) => ResponseBody.fromString(pdf, 200);
    final token = CancelToken()..cancel('user');
    await expectLater(
      service.download(
        const UnifiedBook(
          title: 'book',
          extension: 'pdf',
          source: BookSource.gutenberg,
          downloadUrl: 'https://example.org/book.pdf',
        ),
        token,
        (_) {},
      ),
      throwsA(isA<DioException>()),
    );
    expect(await directory.list().toList(), isEmpty);
  });
  test(
    'compressed content length is not compared with decoded file bytes',
    () async {
      adapter.respond = (_) => ResponseBody.fromString(
        pdf,
        200,
        headers: {
          Headers.contentEncodingHeader: ['gzip'],
          Headers.contentLengthHeader: ['999'],
        },
      );
      final path = await service.download(
        const UnifiedBook(
          title: 'book',
          extension: 'pdf',
          source: BookSource.gutenberg,
          downloadUrl: 'https://example.org/book.pdf',
        ),
        CancelToken(),
        (_) {},
      );
      expect(await File(path).readAsString(), pdf);
    },
  );
  test(
    'cancelling an active streamed transfer removes the partial file',
    () async {
      final token = CancelToken();
      Stream<Uint8List> chunks() async* {
        yield Uint8List.fromList(pdf.codeUnits.take(30).toList());
        token.cancel('user');
        yield Uint8List.fromList(pdf.codeUnits.skip(30).toList());
      }

      adapter.respond = (_) => ResponseBody(chunks(), 200);
      await expectLater(
        service.download(
          const UnifiedBook(
            title: 'book',
            extension: 'pdf',
            source: BookSource.gutenberg,
            downloadUrl: 'https://example.org/book.pdf',
          ),
          token,
          (_) {},
        ),
        throwsA(isA<DioException>()),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );
  test('link resolver excludes navigation and non-HTTP schemes', () {
    expect(
      BookDownloadService.extractDownloadLinks(
        '<a href="/about">About</a><a href="javascript:alert(1)">GET</a>'
        '<a href="../get.php?md5=a">GET</a><a href="//cdn.example.org/b.pdf">PDF</a>',
        Uri.parse('https://example.org/books/page'),
      ),
      ['https://example.org/get.php?md5=a', 'https://cdn.example.org/b.pdf'],
    );
  });
  test('Gutenberg landing pages resolve their actual EPUB download routes', () {
    expect(
      BookDownloadService.extractDownloadLinks(
        '<a href="/ebooks/1342.epub3.images">EPUB3</a>'
        '<a href="/ebooks/1342.epub.images">EPUB (older e-readers)</a>'
        '<a href="/ebooks/1342.kf8.images">Kindle</a>',
        Uri.parse('https://www.gutenberg.org/ebooks/1342'),
      ),
      [
        'https://www.gutenberg.org/ebooks/1342.epub3.images',
        'https://www.gutenberg.org/ebooks/1342.epub.images',
      ],
    );
  });
  test(
    'resolves immediate same-origin book refresh without following navigation',
    () {
      expect(
        BookDownloadService.extractDownloadLinks(
          '<meta http-equiv="refresh" content="0; url=pride.epub?source=download">'
          '<a href="/donate">Donate</a>',
          Uri.parse(
            'https://standardebooks.org/ebooks/a/b/downloads/pride.epub',
          ),
        ),
        [
          'https://standardebooks.org/ebooks/a/b/downloads/pride.epub?source=download',
        ],
      );
      for (final target in [
        'https://other.example/book.epub',
        '/honeypot',
        'javascript:alert(1)',
      ]) {
        expect(
          BookDownloadService.extractDownloadLinks(
            '<meta http-equiv="refresh" content="0; url=$target">',
            Uri.parse('https://standardebooks.org/ebooks/a/b'),
          ),
          isEmpty,
        );
      }
    },
  );
  test(
    'redirects are handled explicitly before requesting a different host',
    () async {
      final lookups = <Uri>[];
      service = BookDownloadService(
        dio,
        () async => directory,
        requestHeaders: (uri) async {
          lookups.add(uri);
          return uri.host == 'archive.test'
              ? {'Cookie': 'session=private', 'User-Agent': 'Browser-UA'}
              : {};
        },
      );
      adapter.respond = (request) => request.uri.host == 'archive.test'
          ? ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['https://files.test/book.pdf'],
              },
            )
          : ResponseBody.fromString(pdf, 200);
      final path = await service.download(
        const UnifiedBook(
          title: 'redirect',
          extension: 'pdf',
          source: BookSource.annasArchive,
          downloadUrl: 'https://archive.test/book',
        ),
        CancelToken(),
        (_) {},
      );
      expect(await File(path).readAsString(), pdf);
      expect(adapter.requests.map((r) => r.uri.host), [
        'archive.test',
        'files.test',
      ]);
      expect(adapter.requests.every((r) => !r.followRedirects), isTrue);
      expect(adapter.requests.first.headers['Cookie'], 'session=private');
      expect(adapter.requests.last.headers['Cookie'], isNull);
      expect(lookups.map((u) => u.host), ['archive.test', 'files.test']);
    },
  );
}

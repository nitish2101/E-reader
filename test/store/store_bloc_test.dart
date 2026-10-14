import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:archive/archive.dart';
import 'package:ereader/data/models/book_model.dart';
import 'package:ereader/data/repositories/book_repository.dart';
import 'package:ereader/data/repositories/store_repository.dart';
import 'package:ereader/presentation/store/bloc/store_bloc.dart';

class PendingSearch extends StoreRepository {
  final requests = <String, Completer<StoreSearchResult>>{};
  final calls = <String>[];
  final transfer = Completer<String>();
  int downloadCount = 0;
  void Function(double)? progress;
  @override
  Future<StoreSearchResult> searchBooks({
    required String query,
    Set<Format> formats = const {Format.pdf, Format.epub},
    int page = 1,
    Set<BookSource> sources = const {
      BookSource.annasArchive,
      BookSource.libgen,
      BookSource.gutenberg,
    },
    CancelToken? cancelToken,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 25),
    void Function(StoreSearchResult)? onPartialResult,
  }) {
    final key = '$query:$page';
    calls.add(key);
    return (requests[key] = Completer<StoreSearchResult>()).future;
  }

  @override
  Future<String> downloadBook({
    required UnifiedBook book,
    required CancelToken cancelToken,
    required void Function(double) onProgress,
    Set<Uri> verifiedPages = const {},
  }) {
    downloadCount++;
    progress = onProgress;
    return transfer.future;
  }
}

const dune = UnifiedBook(
  title: 'Dune',
  extension: 'epub',
  source: BookSource.annasArchive,
  md5: 'dune',
);
const pride = UnifiedBook(
  title: 'Pride',
  extension: 'epub',
  source: BookSource.gutenberg,
  downloadUrl: 'https://example.org/pride.epub',
);
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late Directory temp;
  late Box<BookModel> box;
  late PendingSearch repository;
  late StoreBloc bloc;
  setUpAll(() {
    Hive.registerAdapter(BookModelAdapter());
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('store-state-');
    Hive.init(temp.path);
    box = await Hive.openBox<BookModel>('books');
    repository = PendingSearch();
    bloc = StoreBloc(
      storeRepository: repository,
      bookRepository: BookRepository(booksBox: box),
    );
  });
  tearDown(() async {
    await bloc.close();
    repository.dispose();
    await box.close();
    await temp.delete(recursive: true);
  });

  test(
    'download verification is consumed once and a blocked resume does not reopen it',
    () async {
      final url = Uri.parse('https://annas-archive.pk/slow_download/dune');
      bloc.add(const DownloadBook(dune));
      await settle();
      repository.transfer.completeError(BrowserVerificationRequired(url));
      await settle();
      final request = bloc.state.verificationRequests.single;
      expect(request.book.id, 'dune');
      expect(request.url, url);
      expect(bloc.state.downloads, isEmpty);
      bloc.add(ConsumeDownloadVerification(request));
      bloc.add(const DownloadBook(dune, allowBrowserVerification: false));
      await settle();
      expect(bloc.state.verificationRequests, isEmpty);
      expect(bloc.state.noticeIsError, isTrue);
      expect(bloc.state.notice, contains('verification'));
      expect(bloc.state.downloadedIds, isEmpty);
    },
  );

  test(
    'verified results preserve pagination and other source warnings',
    () async {
      bloc.add(const SearchBooks('Pride'));
      await settle();
      repository.requests['Pride:1']!.complete(
        const StoreSearchResult(
          books: [pride],
          warnings: ["Anna's Archive: blocked", 'LibGen: unavailable'],
        ),
      );
      await settle();
      bloc.add(
        const UseBrowserResults(
          'Pride',
          StoreSearchResult(books: [dune], hasMore: true),
        ),
      );
      await settle();
      expect(bloc.state.books.map((b) => b.id), [pride.id, 'dune']);
      expect(bloc.state.hasMore, isTrue);
      expect(bloc.state.warnings, ['LibGen: unavailable']);
    },
  );
  for (final exhausted in [false, true]) {
    test(
      exhausted
          ? 'three verified partners stop automatic browser retries'
          : 'an already verified page cannot reopen with a different query',
      () async {
        const base = 'https://annas-archive.gl/slow_download/dune/0/';
        final pages = {
          Uri.parse('${base}0?verified=1'),
          if (exhausted) Uri.parse('${base}1'),
          if (exhausted) Uri.parse('${base}2'),
        };
        bloc.add(DownloadBook(dune, verifiedPages: pages));
        await settle();
        repository.transfer.completeError(
          BrowserVerificationRequired(Uri.parse('$base${exhausted ? 3 : 0}')),
        );
        await settle();
        expect(bloc.state.verificationRequests, isEmpty);
        expect(bloc.state.noticeIsError, isTrue);
        expect(bloc.state.downloads, isEmpty);
      },
    );
  }

  test('slow older response cannot overwrite newer search', () async {
    bloc.add(const SearchBooks('old'));
    await settle();
    bloc.add(const SearchBooks('new'));
    await settle();
    repository.requests['new:1']!.complete(
      const StoreSearchResult(books: [pride]),
    );
    await settle();
    repository.requests['old:1']!.complete(
      const StoreSearchResult(books: [dune]),
    );
    await settle();
    expect(bloc.state.query, 'new');
    expect(bloc.state.books.single, pride);
  });
  test('clear invalidates a request already in flight', () async {
    bloc.add(const SearchBooks('old'));
    await settle();
    bloc.add(const ClearSearch());
    await settle();
    repository.requests['old:1']!.complete(
      const StoreSearchResult(books: [dune]),
    );
    await settle();
    expect(bloc.state.status, SearchStatus.initial);
    expect(bloc.state.books, isEmpty);
  });
  test('clear during debounce does not send a delayed search', () async {
    bloc.add(const SearchBooks('old', debounce: true));
    await settle();
    bloc.add(const ClearSearch());
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(repository.calls, isEmpty);
    expect(bloc.state.status, SearchStatus.initial);
  });
  test('pagination failure keeps books and page for retry', () async {
    bloc.add(const SearchBooks('Dune'));
    await settle();
    repository.requests['Dune:1']!.complete(
      const StoreSearchResult(books: [dune], hasMore: true),
    );
    await settle();
    bloc.add(const LoadMoreResults());
    bloc.add(const LoadMoreResults());
    await settle();
    expect(repository.calls.where((c) => c == 'Dune:2'), hasLength(1));
    repository.requests['Dune:2']!.completeError(
      const StoreRepositoryException('offline'),
    );
    await settle();
    expect(bloc.state.books, [dune]);
    expect(bloc.state.page, 1);
    expect(bloc.state.hasMore, isTrue);
    expect(bloc.state.loadingMore, isFalse);
    expect(bloc.state.error, 'offline');
  });
  test(
    'closing store during download prevents library publication and cleans file',
    () async {
      bloc.add(const DownloadBook(pride));
      await settle();
      final closing = bloc.close();
      final file = await File(
        '${temp.path}/download.epub',
      ).writeAsString('partial');
      repository.transfer.complete(file.path);
      await closing;
      expect(box.values, isEmpty);
      expect(await file.exists(), isFalse);
    },
  );
  test('successful download publishes a valid book exactly once', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfile full-path="book.opf"/></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'book.opf',
          '<package><manifest><item id="c" href="chapter.xhtml"/></manifest>'
              '<spine><itemref idref="c"/></spine></package>',
        ),
      )
      ..addFile(
        ArchiveFile.string('chapter.xhtml', '<html><body>Book</body></html>'),
      );
    final file = await File(
      '${temp.path}/download.epub',
    ).writeAsBytes(ZipEncoder().encode(archive));
    final published = bloc.stream.firstWhere(
      (state) => state.downloadedIds.contains(pride.id),
    );
    bloc.add(const DownloadBook(pride));
    bloc.add(const DownloadBook(pride));
    await settle();
    repository.transfer.complete(file.path);
    await published.timeout(const Duration(seconds: 3));
    expect(box.values, hasLength(1));
    expect(box.values.single.storeBookId, pride.id);
    expect(box.values.single.fileSize, await file.length());
    expect(bloc.state.downloadedIds, contains(pride.id));
    expect(bloc.state.downloads, isEmpty);
    bloc.add(const DownloadBook(pride));
    await settle();
    expect(repository.downloadCount, 1);
  });
  test(
    'download completion preserves newer query and its pagination',
    () async {
      bloc.add(const SearchBooks('Dune'));
      await settle();
      repository.requests['Dune:1']!.complete(
        const StoreSearchResult(books: [dune], hasMore: true),
      );
      await settle();
      bloc.add(const DownloadBook(dune));
      bloc.add(const DownloadBook(dune));
      await settle();
      expect(repository.downloadCount, 1);
      bloc.add(const SearchBooks('Pride'));
      await settle();
      repository.requests['Pride:1']!.complete(
        const StoreSearchResult(books: [pride]),
      );
      await settle();
      repository.transfer.completeError(
        const StoreRepositoryException('bad file'),
      );
      await settle();
      expect(bloc.state.query, 'Pride');
      expect(bloc.state.books, [pride]);
      expect(bloc.state.hasMore, isFalse);
      expect(bloc.state.downloads, isEmpty);
      expect(bloc.state.noticeIsError, isTrue);
    },
  );
}

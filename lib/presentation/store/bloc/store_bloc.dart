import '../../../data/services/cancellation.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:dio/dio.dart';
import '../../../data/repositories/store_repository.dart';
import '../../../data/repositories/book_repository.dart';

part 'store_event.dart';
part 'store_state.dart';

class StoreBloc extends Bloc<StoreEvent, StoreState> {
  final StoreRepository storeRepository;
  final BookRepository bookRepository;
  CancelToken? _searchToken;
  int _searchVersion = 0;
  final Map<String, CancelToken> _downloadTokens = {};
  final Set<Future<void>> _downloadWork = {};

  StoreBloc({
    required this.storeRepository,
    required this.bookRepository,
    Set<BookSource> initialSources = const {
      BookSource.annasArchive,
      BookSource.libgen,
      BookSource.gutenberg,
      BookSource.standardEbooks,
    },
  }) : super(StoreState(sources: initialSources)) {
    on<SearchBooks>(_onSearch);
    on<ConsumeDownloadVerification>(
      (event, emit) => emit(
        state.copyWith(
          verificationRequests: state.verificationRequests
              .where((r) => r != event.request)
              .toList(),
        ),
      ),
    );
    on<UseBrowserResults>((event, emit) {
      _invalidateSearch();
      emit(
        state.copyWith(
          status: SearchStatus.ready,
          query: event.query,
          books: StoreRepository.deduplicate([
            if (state.query == event.query)
              ...state.books.where((b) => b.source != BookSource.annasArchive),
            ...event.result.books.where(
              (b) => state.formats.any((f) => f.name == b.extension),
            ),
          ]),
          page: 1,
          hasMore: event.result.hasMore,
          loadingMore: false,
          warnings: state.warnings
              .where((w) => !w.startsWith('${BookSource.annasArchive.label}:'))
              .toList(),
          clearError: true,
        ),
      );
    });
    on<LoadPopularBooks>((event, emit) => _search('', false, false, emit));
    on<ClearSearch>((event, emit) {
      _invalidateSearch();
      emit(
        state.copyWith(
          status: SearchStatus.initial,
          query: '',
          books: [],
          loadingMore: false,
          hasMore: false,
          warnings: [],
          clearError: true,
        ),
      );
    });
    on<UpdateFilter>((event, emit) async {
      if (event.formats.isEmpty) return;
      emit(state.copyWith(formats: Set.unmodifiable(event.formats)));
      if (state.status != SearchStatus.initial) {
        await _search(state.query, false, false, emit);
      }
    });
    on<UpdateSourceFilter>((event, emit) async {
      if (event.sources.isEmpty) return;
      emit(state.copyWith(sources: Set.unmodifiable(event.sources)));
      if (state.status != SearchStatus.initial) {
        await _search(state.query, false, false, emit);
      }
    });
    on<LoadMoreResults>(_onLoadMore);
    on<DownloadBook>((event, emit) async {
      final completion = Completer<void>();
      _downloadWork.add(completion.future);
      try {
        await _onDownload(event, emit);
      } finally {
        _downloadWork.remove(completion.future);
        completion.complete();
      }
    });
    on<CancelDownload>(
      (event, emit) => _downloadTokens[event.bookId]?.cancel('Cancelled'),
    );
  }

  void _invalidateSearch() {
    _searchVersion++;
    _searchToken?.cancel('Search superseded');
    _searchToken = null;
  }

  Future<void> _onSearch(SearchBooks event, Emitter<StoreState> emit) async {
    if (event.query.trim().isEmpty) {
      _invalidateSearch();
      emit(
        state.copyWith(
          status: SearchStatus.initial,
          query: '',
          books: [],
          loadingMore: false,
          hasMore: false,
          warnings: [],
          clearError: true,
        ),
      );
      return;
    }
    await _search(event.query.trim(), event.debounce, event.forceRefresh, emit);
  }

  Future<void> _search(
    String query,
    bool debounce,
    bool refresh,
    Emitter<StoreState> emit,
  ) async {
    _invalidateSearch();
    final version = _searchVersion;
    final token = _searchToken = CancelToken();
    final formats = state.formats;
    final sources = state.sources;
    emit(
      state.copyWith(
        status: SearchStatus.searching,
        query: query,
        books: [],
        page: 1,
        loadingMore: false,
        hasMore: false,
        warnings: [],
        clearError: true,
      ),
    );
    if (debounce) await Future<void>.delayed(const Duration(milliseconds: 400));
    if (version != _searchVersion || emit.isDone) return;
    try {
      // Empty query is a curated popular list, never an expensive archive-wide scan.
      final result = await storeRepository.searchBooks(
        query: query,
        formats: formats,
        sources: query.isEmpty
            ? {BookSource.gutenberg, BookSource.standardEbooks}
            : sources,
        cancelToken: token,
        forceRefresh: refresh,
        onPartialResult: (partial) {
          if (version == _searchVersion && !emit.isDone) {
            emit(state.copyWith(books: partial.books));
          }
        },
      );
      if (version != _searchVersion || emit.isDone) return;
      emit(
        state.copyWith(
          status: SearchStatus.ready,
          books: result.books,
          hasMore: result.hasMore,
          warnings: result.warnings,
          clearError: true,
        ),
      );
    } catch (error) {
      if (version != _searchVersion || emit.isDone) return;
      emit(
        state.copyWith(status: SearchStatus.failure, error: _message(error)),
      );
    }
  }

  Future<void> _onLoadMore(
    LoadMoreResults event,
    Emitter<StoreState> emit,
  ) async {
    if (state.status != SearchStatus.ready ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
    final version = _searchVersion;
    final snapshot = state;
    emit(state.copyWith(loadingMore: true, clearError: true));
    try {
      final result = await storeRepository.searchBooks(
        query: snapshot.query,
        page: snapshot.page + 1,
        formats: snapshot.formats,
        sources: snapshot.query.isEmpty
            ? {BookSource.gutenberg, BookSource.standardEbooks}
            : snapshot.sources,
        cancelToken: _searchToken,
      );
      if (version != _searchVersion || emit.isDone) return;
      final books = StoreRepository.deduplicate([
        ...snapshot.books,
        ...result.books,
      ]);
      emit(
        state.copyWith(
          books: books,
          page: snapshot.page + 1,
          loadingMore: false,
          hasMore: result.hasMore,
          warnings: result.warnings,
          clearError: true,
        ),
      );
    } catch (error) {
      if (version != _searchVersion || emit.isDone) return;
      emit(state.copyWith(loadingMore: false, error: _message(error)));
    }
  }

  Future<void> _onDownload(DownloadBook event, Emitter<StoreState> emit) async {
    final book = event.book;
    if (_downloadTokens.containsKey(book.id) ||
        state.downloadedIds.contains(book.id)) {
      return;
    }
    final existing = bookRepository.findStoreBook(book);
    if (existing != null && await File(existing.localPath).exists()) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            downloadedIds: {...state.downloadedIds, book.id},
            notice: 'Already in your library.',
          ),
        );
      }
      return;
    }
    if (emit.isDone) return;
    // Re-check after the filesystem await: two taps can otherwise start two transfers.
    if (_downloadTokens.containsKey(book.id)) return;
    final token = _downloadTokens[book.id] = CancelToken();
    emit(state.copyWith(downloads: {...state.downloads, book.id: 0}));
    String? path;
    try {
      path = await storeRepository.downloadBook(
        book: book,
        cancelToken: token,
        verifiedPages: event.verifiedPages,
        onProgress: (progress) {
          if (!emit.isDone && !isClosed) {
            emit(
              state.copyWith(
                downloads: {...state.downloads, book.id: progress},
              ),
            );
          }
        },
      );
      token.throwIfCancellationRequested();
      await bookRepository.addStoreBook(
        title: book.title,
        author: book.author,
        localPath: path,
        format: book.extension,
        coverUrl: book.coverUrl,
        md5: book.md5,
        storeBookId: book.id,
        fileSize: await File(path).length(),
      );
      if (!emit.isDone && !isClosed) {
        emit(
          state.copyWith(
            downloadedIds: {...state.downloadedIds, book.id},
            notice: 'Added "${book.title}" to your library.',
            noticeIsError: false,
          ),
        );
      }
      path = null; // Library now owns the file.
    } catch (error) {
      if (path != null && await File(path).exists()) await File(path).delete();
      if (!emit.isDone &&
          !isClosed &&
          error is BrowserVerificationRequired &&
          !token.isCancelled &&
          event.allowBrowserVerification &&
          event.verifiedPages.length < 3 &&
          !event.verifiedPages.any(
            (page) =>
                page.origin == error.url.origin && page.path == error.url.path,
          )) {
        emit(
          state.copyWith(
            verificationRequests: [
              ...state.verificationRequests,
              DownloadVerification(
                book,
                error.url,
                verifiedPages: event.verifiedPages,
              ),
            ],
          ),
        );
      } else if (!emit.isDone && !isClosed) {
        emit(
          state.copyWith(
            notice: token.cancelError?.error is TimeoutException
                ? 'Download timed out. Try again or choose another source.'
                : token.isCancelled
                ? 'Download cancelled.'
                : _message(error),
            noticeIsError:
                !token.isCancelled ||
                token.cancelError?.error is TimeoutException,
          ),
        );
      }
    } finally {
      _downloadTokens.remove(book.id);
      if (!emit.isDone && !isClosed) {
        emit(state.copyWith(downloads: {...state.downloads}..remove(book.id)));
      }
    }
  }

  static String _message(Object error) => error is StoreRepositoryException
      ? error.message
      : error is FormatException
      ? error.message
      : 'Something went wrong. Please try again.';

  @override
  Future<void> close() async {
    _invalidateSearch();
    for (final token in _downloadTokens.values) {
      token.cancel('Store closed');
    }
    await super.close();
    // Bloc closes its emitters before the underlying transfers finish cleanup.
    await Future.wait(_downloadWork.toList());
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:annas_archive_api/annas_archive_api.dart';

import '../../../core/services/store_preload_service.dart';
import '../../../data/repositories/store_repository.dart';
import '../../../data/repositories/book_repository.dart';

part 'store_event.dart';
part 'store_state.dart';

class StoreBloc extends Bloc<StoreEvent, StoreState> {
  final StoreRepository storeRepository;
  final BookRepository bookRepository;

  StoreBloc({
    required this.storeRepository,
    required this.bookRepository,
  }) : super(StoreInitial()) {
    on<SearchBooks>(_onSearchBooks);
    on<LoadMoreResults>(_onLoadMoreResults);
    on<ClearSearch>(_onClearSearch);
    on<DownloadBook>(_onDownloadBook);
    on<UpdateFilter>(_onUpdateFilter);
    on<UpdateSourceFilter>(_onUpdateSourceFilter);
    on<LoadCachedBooks>(_onLoadCachedBooks);
  }

  Future<void> _onSearchBooks(
    SearchBooks event,
    Emitter<StoreState> emit,
  ) async {
    if (event.query.trim().isEmpty) {
      emit(StoreInitial());
      return;
    }

    emit(StoreSearching(event.query));

    try {
      final books = await storeRepository.searchBooks(
        query: event.query,
        formats: event.formats,
      );

      // Apply format filtering to the results
      final filteredBooks = _filterBooksByFormat(books, event.formats);

      emit(StoreResults(
        query: event.query,
        books: filteredBooks,
        allBooks: books, // Store all books for local filtering
        hasMore: books.isNotEmpty,
        formats: event.formats,
        page: 1,
      ));
    } catch (e) {
      emit(StoreError(message: 'Search failed: $e', query: event.query));
    }
  }

  /// Filter books by format
  List<UnifiedBook> _filterBooksByFormat(List<UnifiedBook> books, List<Format> formats) {
    if (formats.length >= 2) return books; // Show all if both selected
    
    return books.where((book) {
      final ext = book.extension?.toLowerCase() ?? '';
      if (formats.contains(Format.pdf) && ext == 'pdf') return true;
      if (formats.contains(Format.epub) && ext == 'epub') return true;
      return false;
    }).toList();
  }

  Future<void> _onLoadMoreResults(
    LoadMoreResults event,
    Emitter<StoreState> emit,
  ) async {
    final currentState = state;
    if (currentState is! StoreResults || !currentState.hasMore) return;

    emit(StoreLoadingMore(
      query: currentState.query,
      currentBooks: currentState.books,
    ));

    try {
      final nextPage = currentState.page + 1;
      final moreBooks = await storeRepository.searchBooks(
        query: currentState.query,
        page: nextPage,
        formats: currentState.formats,
        searchAnnasArchive: currentState.searchAnnasArchive,
        searchLibgen: currentState.searchLibgen,
      );

      emit(StoreResults(
        query: currentState.query,
        books: [...currentState.books, ...moreBooks],
        allBooks: [...currentState.allBooks, ...moreBooks], // Update all books too
        hasMore: moreBooks.isNotEmpty,
        formats: currentState.formats,
        page: nextPage,
        searchAnnasArchive: currentState.searchAnnasArchive,
        searchLibgen: currentState.searchLibgen,
      ));
    } catch (e) {
      emit(StoreError(
        message: 'Failed to load more: $e',
        query: currentState.query,
        previousBooks: currentState.books,
      ));
    }
  }

  void _onClearSearch(
    ClearSearch event,
    Emitter<StoreState> emit,
  ) {
    emit(StoreInitial());
  }

  Future<void> _onDownloadBook(
    DownloadBook event,
    Emitter<StoreState> emit,
  ) async {
    final currentState = state;
    List<UnifiedBook> currentBooks = [];
    String query = '';

    if (currentState is StoreResults) {
      currentBooks = currentState.books;
      query = currentState.query;
    }

    try {
      // Get download links
      final links = await storeRepository.getDownloadLinks(event.book);
      
      if (links.isEmpty) {
        emit(StoreError(
          message: 'No download links available',
          query: query,
          previousBooks: currentBooks,
        ));
        return;
      }

      // Start download
      emit(BookDownloading(
        book: event.book,
        progress: 0,
        currentBooks: currentBooks,
        query: query,
      ));

      // Generate file name
      final extension = event.book.extension?.isNotEmpty == true ? event.book.extension! : 'pdf';
      final safeTitle = (event.book.title ?? 'book').replaceAll(RegExp(r'[^\w\s-]'), '');
      final fileName = '${safeTitle}_${event.book.md5 ?? DateTime.now().millisecondsSinceEpoch}.$extension';

      // Download the file
      final filePath = await storeRepository.downloadBook(
        url: links.first,
        fileName: fileName,
        onProgress: (progress) {
          emit(BookDownloading(
            book: event.book,
            progress: progress,
            currentBooks: currentBooks,
            query: query,
          ));
        },
      );

      if (filePath != null) {
        // Add to library
        await bookRepository.addStoreBook(
          title: event.book.title ?? 'Unknown',
          author: event.book.author ?? 'Unknown Author',
          localPath: filePath,
          format: extension,
          coverUrl: event.book.coverUrl,
          md5: event.book.md5,
          fileSize: int.tryParse(event.book.fileSize ?? ''),
        );

        emit(BookDownloaded(
          book: event.book,
          localPath: filePath,
          currentBooks: currentBooks,
          query: query,
        ));

        // Return to results
        emit(StoreResults(
          query: query,
          books: currentBooks,
          allBooks: currentBooks,
          hasMore: true,
        ));
      } else {
        emit(StoreError(
          message: 'Download failed',
          query: query,
          previousBooks: currentBooks,
        ));
      }
    } catch (e) {
      emit(StoreError(
        message: 'Download error: $e',
        query: query,
        previousBooks: currentBooks,
      ));
    }
  }

  void _onUpdateFilter(
    UpdateFilter event,
    Emitter<StoreState> emit,
  ) {
    final currentState = state;
    if (currentState is! StoreResults) return;

    // Filter locally instead of making new API call
    final filteredBooks = currentState._filterByFormat(event.formats);

    emit(StoreResults(
      query: currentState.query,
      books: filteredBooks,
      allBooks: currentState.allBooks, // Keep all books for future filtering
      hasMore: currentState.hasMore,
      formats: event.formats,
      page: currentState.page,
      searchAnnasArchive: currentState.searchAnnasArchive,
      searchLibgen: currentState.searchLibgen,
    ));
  }

  Future<void> _onUpdateSourceFilter(
    UpdateSourceFilter event,
    Emitter<StoreState> emit,
  ) async {
    final currentState = state;
    if (currentState is! StoreResults) return;

    // Ensure at least one source is selected
    if (!event.searchAnnasArchive && !event.searchLibgen) return;

    emit(StoreSearching(currentState.query));

    try {
      final books = await storeRepository.searchBooks(
        query: currentState.query,
        formats: currentState.formats,
        searchAnnasArchive: event.searchAnnasArchive,
        searchLibgen: event.searchLibgen,
      );

      emit(StoreResults(
        query: currentState.query,
        books: books,
        hasMore: books.isNotEmpty,
        formats: currentState.formats,
        page: 1,
        searchAnnasArchive: event.searchAnnasArchive,
        searchLibgen: event.searchLibgen,
      ));
    } catch (e) {
      emit(StoreError(
        message: 'Source filter failed: $e',
        query: currentState.query,
      ));
    }
  }

  Future<void> _onLoadCachedBooks(
    LoadCachedBooks event,
    Emitter<StoreState> emit,
  ) async {
    // First check if we have cached books
    final cachedBooks = StorePreloadService.instance.getCachedBooks();
    if (cachedBooks != null && cachedBooks.isNotEmpty) {
      emit(StoreResults(
        query: 'popular fiction',
        books: cachedBooks,
        allBooks: cachedBooks,
        hasMore: true,
        page: 1,
      ));
      return;
    }

    // If preloading is still in progress, wait a bit and check again
    if (StorePreloadService.instance.isLoading) {
      emit(StoreSearching('popular fiction'));
      
      // Wait for up to 5 seconds for preloading to complete
      for (var i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final books = StorePreloadService.instance.getCachedBooks();
        if (books != null && books.isNotEmpty) {
          emit(StoreResults(
            query: 'popular fiction',
            books: books,
            allBooks: books,
            hasMore: true,
            page: 1,
          ));
          return;
        }
      }
    }

    // If still no cached books, show initial view (don't auto-search)
    // Let the user decide to search or wait for preloading
    emit(StoreInitial());
  }
}

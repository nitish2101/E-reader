part of 'store_bloc.dart';

abstract class StoreEvent {
  const StoreEvent();
}

class SearchBooks extends StoreEvent {
  final String query;
  final bool debounce;
  final bool forceRefresh;
  const SearchBooks(
    this.query, {
    this.debounce = false,
    this.forceRefresh = false,
  });
}

class LoadPopularBooks extends StoreEvent {
  const LoadPopularBooks();
}

class LoadMoreResults extends StoreEvent {
  const LoadMoreResults();
}

class ClearSearch extends StoreEvent {
  const ClearSearch();
}

class UpdateFilter extends StoreEvent {
  final Set<Format> formats;
  const UpdateFilter(this.formats);
}

class UpdateSourceFilter extends StoreEvent {
  final Set<BookSource> sources;
  const UpdateSourceFilter(this.sources);
}

class DownloadBook extends StoreEvent {
  final UnifiedBook book;
  const DownloadBook(this.book);
}

class CancelDownload extends StoreEvent {
  final String bookId;
  const CancelDownload(this.bookId);
}

class UseBrowserResults extends StoreEvent {
  final String query;
  final StoreSearchResult result;
  const UseBrowserResults(this.query, this.result);
}

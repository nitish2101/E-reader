part of 'store_bloc.dart';

enum SearchStatus { initial, searching, ready, failure }

class StoreState extends Equatable {
  final SearchStatus status;
  final String query;
  final List<UnifiedBook> books;
  final Set<Format> formats;
  final Set<BookSource> sources;
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final List<String> warnings;
  final String? error;
  final Map<String, double> downloads;
  final Set<String> downloadedIds;
  final String? notice;
  final bool noticeIsError;
  final int noticeVersion;

  const StoreState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.books = const [],
    this.formats = const {Format.epub, Format.pdf},
    this.sources = const {
      BookSource.annasArchive,
      BookSource.libgen,
      BookSource.gutenberg,
      BookSource.standardEbooks,
    },
    this.page = 1,
    this.hasMore = false,
    this.loadingMore = false,
    this.warnings = const [],
    this.error,
    this.downloads = const {},
    this.downloadedIds = const {},
    this.notice,
    this.noticeIsError = false,
    this.noticeVersion = 0,
  });

  StoreState copyWith({
    SearchStatus? status,
    String? query,
    List<UnifiedBook>? books,
    Set<Format>? formats,
    Set<BookSource>? sources,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    List<String>? warnings,
    String? error,
    bool clearError = false,
    Map<String, double>? downloads,
    Set<String>? downloadedIds,
    String? notice,
    bool? noticeIsError,
  }) => StoreState(
    status: status ?? this.status,
    query: query ?? this.query,
    books: books ?? this.books,
    formats: formats ?? this.formats,
    sources: sources ?? this.sources,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    warnings: warnings ?? this.warnings,
    error: clearError ? null : error ?? this.error,
    downloads: downloads ?? this.downloads,
    downloadedIds: downloadedIds ?? this.downloadedIds,
    notice: notice ?? this.notice,
    noticeIsError: noticeIsError ?? this.noticeIsError,
    noticeVersion: notice == null ? noticeVersion : noticeVersion + 1,
  );

  @override
  List<Object?> get props => [
    status,
    query,
    books,
    formats,
    sources,
    page,
    hasMore,
    loadingMore,
    warnings,
    error,
    downloads,
    downloadedIds,
    notice,
    noticeIsError,
    noticeVersion,
  ];
}

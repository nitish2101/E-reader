part of 'store_bloc.dart';

abstract class StoreState extends Equatable {
  const StoreState();

  @override
  List<Object?> get props => [];
}

class StoreInitial extends StoreState {}

class StoreSearching extends StoreState {
  final String query;

  const StoreSearching(this.query);

  @override
  List<Object?> get props => [query];
}

class StoreResults extends StoreState {
  final String query;
  final List<UnifiedBook> books; // Filtered books to display
  final List<UnifiedBook> allBooks; // All books from API for local filtering
  final bool hasMore;
  final List<Format> formats;
  final int page;
  final bool searchAnnasArchive;
  final bool searchLibgen;

  const StoreResults({
    required this.query,
    required this.books,
    List<UnifiedBook>? allBooks,
    this.hasMore = true,
    this.formats = const [Format.pdf, Format.epub],
    this.page = 1,
    this.searchAnnasArchive = true,
    this.searchLibgen = true,
  }) : allBooks = allBooks ?? books;

  @override
  List<Object?> get props => [query, books, allBooks, hasMore, formats, page, searchAnnasArchive, searchLibgen];

  StoreResults copyWith({
    String? query,
    List<UnifiedBook>? books,
    List<UnifiedBook>? allBooks,
    bool? hasMore,
    List<Format>? formats,
    int? page,
    bool? searchAnnasArchive,
    bool? searchLibgen,
  }) {
    return StoreResults(
      query: query ?? this.query,
      books: books ?? this.books,
      allBooks: allBooks ?? this.allBooks,
      hasMore: hasMore ?? this.hasMore,
      formats: formats ?? this.formats,
      page: page ?? this.page,
      searchAnnasArchive: searchAnnasArchive ?? this.searchAnnasArchive,
      searchLibgen: searchLibgen ?? this.searchLibgen,
    );
  }

  /// Filter books locally by format
  List<UnifiedBook> _filterByFormat(List<Format> selectedFormats) {
    if (selectedFormats.length >= 2) return allBooks; // Show all if both selected
    
    return allBooks.where((book) {
      final ext = book.extension?.toLowerCase()?.trim() ?? '';
      // Exclude books with unknown format when user selected specific format
      if (ext.isEmpty) return false;
      if (selectedFormats.contains(Format.pdf) && ext == 'pdf') return true;
      if (selectedFormats.contains(Format.epub) && ext == 'epub') return true;
      return false;
    }).toList();
  }
}

class StoreLoadingMore extends StoreState {
  final String query;
  final List<UnifiedBook> currentBooks;

  const StoreLoadingMore({
    required this.query,
    required this.currentBooks,
  });

  @override
  List<Object?> get props => [query, currentBooks];
}

class StoreError extends StoreState {
  final String message;
  final String? query;
  final List<UnifiedBook> previousBooks;

  const StoreError({
    required this.message,
    this.query,
    this.previousBooks = const [],
  });

  @override
  List<Object?> get props => [message, query, previousBooks];
}

class BookDownloading extends StoreState {
  final UnifiedBook book;
  final double progress;
  final List<UnifiedBook> currentBooks;
  final String query;

  const BookDownloading({
    required this.book,
    required this.progress,
    required this.currentBooks,
    required this.query,
  });

  @override
  List<Object?> get props => [book, progress, currentBooks, query];
}

class BookDownloaded extends StoreState {
  final UnifiedBook book;
  final String localPath;
  final List<UnifiedBook> currentBooks;
  final String query;

  const BookDownloaded({
    required this.book,
    required this.localPath,
    required this.currentBooks,
    required this.query,
  });

  @override
  List<Object?> get props => [book, localPath, currentBooks, query];
}

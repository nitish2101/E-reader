enum Format { pdf, epub }

enum BookSource { annasArchive, libgen, gutenberg, standardEbooks }

extension BookSourceLabel on BookSource {
  String get label => switch (this) {
    BookSource.annasArchive => "Anna's Archive",
    BookSource.libgen => 'LibGen',
    BookSource.gutenberg => 'Project Gutenberg',
    BookSource.standardEbooks => 'Standard Ebooks',
  };
}

class UnifiedBook {
  final String title;
  final String author;
  final String? md5;
  final String? coverUrl;
  final String? fileSize;
  final String extension;
  final String? year;
  final String? language;
  final BookSource source;
  final String? downloadUrl;
  final String? detailUrl;
  final List<String> alternateUrls;

  const UnifiedBook({
    required this.title,
    this.author = 'Unknown Author',
    this.md5,
    this.coverUrl,
    this.fileSize,
    required this.extension,
    this.year,
    this.language,
    required this.source,
    this.downloadUrl,
    this.detailUrl,
    this.alternateUrls = const [],
  });

  // Include format: two editions of a title must not collapse into one file.
  String get id => md5?.isNotEmpty == true
      ? md5!.toLowerCase()
      : '${source.name}:${downloadUrl ?? detailUrl ?? '$title:$author'}:$extension';
  String get sourceDisplayName => source.label;
  bool get isSupported => extension == 'pdf' || extension == 'epub';
}

class StoreSearchResult {
  final List<UnifiedBook> books;
  final bool hasMore;
  final List<String> warnings;

  const StoreSearchResult({
    required this.books,
    this.hasMore = false,
    this.warnings = const [],
  });
}

class StoreRepositoryException implements Exception {
  final String message;
  const StoreRepositoryException(this.message);
  @override
  String toString() => message;
}

class BrowserVerificationRequired extends StoreRepositoryException {
  final Uri url;
  const BrowserVerificationRequired(this.url)
    : super('The download source requires browser verification.');
}

class DownloadVerification {
  final UnifiedBook book;
  final Uri url;
  const DownloadVerification(this.book, this.url);
}

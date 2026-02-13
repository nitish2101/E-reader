part of 'library_bloc.dart';

abstract class LibraryState extends Equatable {
  const LibraryState();

  @override
  List<Object?> get props => [];
}

class LibraryInitial extends LibraryState {}

class LibraryLoading extends LibraryState {}

class LibraryLoaded extends LibraryState {
  final List<BookModel> books;

  const LibraryLoaded(this.books);

  @override
  List<Object?> get props => [books];

  bool get isEmpty => books.isEmpty;
}

class LibraryError extends LibraryState {
  final String message;

  const LibraryError(this.message);

  @override
  List<Object?> get props => [message];
}

class BookImporting extends LibraryState {
  final List<BookModel> currentBooks;

  const BookImporting(this.currentBooks);

  @override
  List<Object?> get props => [currentBooks];
}

class BookImported extends LibraryState {
  final List<BookModel> books;
  final BookModel importedBook;

  const BookImported(this.books, this.importedBook);

  @override
  List<Object?> get props => [books, importedBook];
}

class BookDeleted extends LibraryState {
  final List<BookModel> books;

  const BookDeleted(this.books);

  @override
  List<Object?> get props => [books];
}

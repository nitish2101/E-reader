part of 'library_bloc.dart';

abstract class LibraryEvent extends Equatable {
  const LibraryEvent();

  @override
  List<Object?> get props => [];
}

class LoadLibrary extends LibraryEvent {}

class ImportBook extends LibraryEvent {}

class DeleteBook extends LibraryEvent {
  final String bookId;

  const DeleteBook(this.bookId);

  @override
  List<Object?> get props => [bookId];
}

class RefreshLibrary extends LibraryEvent {}

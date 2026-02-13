import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/models/book_model.dart';
import '../../../data/repositories/book_repository.dart';

part 'library_event.dart';
part 'library_state.dart';

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  final BookRepository bookRepository;
  StreamSubscription? _booksSubscription;

  LibraryBloc({required this.bookRepository}) : super(LibraryInitial()) {
    on<LoadLibrary>(_onLoadLibrary);
    on<ImportBook>(_onImportBook);
    on<DeleteBook>(_onDeleteBook);
    on<RefreshLibrary>(_onRefreshLibrary);

    _booksSubscription = bookRepository.watchBooks.listen((_) {
      add(RefreshLibrary());
    });
  }

  @override
  Future<void> close() {
    _booksSubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadLibrary(
    LoadLibrary event,
    Emitter<LibraryState> emit,
  ) async {
    emit(LibraryLoading());
    try {
      final books = bookRepository.getAllBooks();
      emit(LibraryLoaded(books));
    } catch (e) {
      emit(LibraryError('Failed to load library: $e'));
    }
  }

  Future<void> _onImportBook(
    ImportBook event,
    Emitter<LibraryState> emit,
  ) async {
    final currentBooks = state is LibraryLoaded
        ? (state as LibraryLoaded).books
        : <BookModel>[];

    emit(BookImporting(currentBooks));

    try {
      final book = await bookRepository.importBook();
      if (book != null) {
        final updatedBooks = bookRepository.getAllBooks();
        emit(BookImported(updatedBooks, book));
      } else {
        emit(LibraryLoaded(currentBooks));
      }
    } catch (e) {
      emit(LibraryError('Failed to import book: $e'));
    }
  }

  Future<void> _onDeleteBook(
    DeleteBook event,
    Emitter<LibraryState> emit,
  ) async {
    try {
      await bookRepository.deleteBook(event.bookId);
      final books = bookRepository.getAllBooks();
      emit(BookDeleted(books));
    } catch (e) {
      emit(LibraryError('Failed to delete book: $e'));
    }
  }

  Future<void> _onRefreshLibrary(
    RefreshLibrary event,
    Emitter<LibraryState> emit,
  ) async {
    try {
      final books = bookRepository.getAllBooks();
      emit(LibraryLoaded(books));
    } catch (e) {
      emit(LibraryError('Failed to refresh library: $e'));
    }
  }
}

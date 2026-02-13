import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../data/models/book_model.dart';
import '../../../data/repositories/book_repository.dart';

part 'reader_event.dart';
part 'reader_state.dart';

class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  final BookRepository bookRepository;
  BookModel? _currentBook;
  int _currentPage = 0;
  int _totalPages = 0;
  double _progress = 0.0;
  String? _cfi;

  ReaderBloc({required this.bookRepository}) : super(ReaderInitial()) {
    on<LoadBook>(_onLoadBook);
    on<UpdatePdfProgress>(_onUpdatePdfProgress);
    on<UpdateEpubProgress>(_onUpdateEpubProgress);
    on<SaveProgress>(_onSaveProgress);
  }

  Future<void> _onLoadBook(
    LoadBook event,
    Emitter<ReaderState> emit,
  ) async {
    emit(ReaderLoading());

    try {
      final book = bookRepository.getBook(event.bookId);
      if (book == null) {
        emit(const ReaderError('Book not found'));
        return;
      }

      _currentBook = book;
      _currentPage = book.lastReadPage;
      _progress = book.lastReadProgress;
      _cfi = book.lastReadCfi;
      _totalPages = book.totalPages;

      emit(ReaderLoaded(
        book: book,
        currentPage: _currentPage,
        totalPages: _totalPages,
        progress: _progress,
        cfi: _cfi,
      ));
    } catch (e) {
      emit(ReaderError('Failed to load book: $e'));
    }
  }

  void _onUpdatePdfProgress(
    UpdatePdfProgress event,
    Emitter<ReaderState> emit,
  ) {
    if (_currentBook == null) return;

    _currentPage = event.currentPage;
    _totalPages = event.totalPages;
    _progress = event.totalPages > 0 
        ? event.currentPage / event.totalPages 
        : 0.0;

    emit(ReaderLoaded(
      book: _currentBook!,
      currentPage: _currentPage,
      totalPages: _totalPages,
      progress: _progress,
    ));
  }

  void _onUpdateEpubProgress(
    UpdateEpubProgress event,
    Emitter<ReaderState> emit,
  ) {
    if (_currentBook == null) return;

    // Only update if progress changed significantly (avoid rebuilds on tiny changes)
    final progressDiff = (event.progress - _progress).abs();
    if (progressDiff < 0.005 && event.cfi == _cfi) {
      return; // Skip update for tiny changes
    }

    _cfi = event.cfi;
    _progress = event.progress;

    // Only emit state if progress changed by 1% or more to prevent UI jitter
    if (progressDiff >= 0.01) {
      emit(ReaderLoaded(
        book: _currentBook!,
        currentPage: _currentPage,
        totalPages: _totalPages,
        progress: _progress,
        cfi: _cfi,
      ));
    }
  }

  Future<void> _onSaveProgress(
    SaveProgress event,
    Emitter<ReaderState> emit,
  ) async {
    if (_currentBook == null) return;

    try {
      await bookRepository.updateReadingProgress(
        bookId: _currentBook!.id,
        page: _currentPage,
        progress: _progress,
        cfi: _cfi,
        totalPages: _totalPages,
      );

      emit(ProgressSaved(
        book: _currentBook!,
        currentPage: _currentPage,
        totalPages: _totalPages,
        progress: _progress,
        cfi: _cfi,
      ));

      // Return to loaded state
      emit(ReaderLoaded(
        book: _currentBook!,
        currentPage: _currentPage,
        totalPages: _totalPages,
        progress: _progress,
        cfi: _cfi,
      ));
    } catch (e) {
      // Silently fail - don't interrupt reading
      print('Failed to save progress: $e');
    }
  }

  @override
  Future<void> close() {
    // Save progress when closing
    if (_currentBook != null) {
      bookRepository.updateReadingProgress(
        bookId: _currentBook!.id,
        page: _currentPage,
        progress: _progress,
        cfi: _cfi,
        totalPages: _totalPages,
      );
    }
    return super.close();
  }
}

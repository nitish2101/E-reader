part of 'reader_bloc.dart';

abstract class ReaderEvent extends Equatable {
  const ReaderEvent();

  @override
  List<Object?> get props => [];
}

class LoadBook extends ReaderEvent {
  final String bookId;

  const LoadBook(this.bookId);

  @override
  List<Object?> get props => [bookId];
}

class UpdatePdfProgress extends ReaderEvent {
  final int currentPage;
  final int totalPages;

  const UpdatePdfProgress({
    required this.currentPage,
    required this.totalPages,
  });

  @override
  List<Object?> get props => [currentPage, totalPages];
}

class UpdateEpubProgress extends ReaderEvent {
  final String cfi;
  final double progress;

  const UpdateEpubProgress({
    required this.cfi,
    required this.progress,
  });

  @override
  List<Object?> get props => [cfi, progress];
}

class SaveProgress extends ReaderEvent {}

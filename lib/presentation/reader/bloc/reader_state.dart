part of 'reader_bloc.dart';

abstract class ReaderState extends Equatable {
  const ReaderState();

  @override
  List<Object?> get props => [];
}

class ReaderInitial extends ReaderState {}

class ReaderLoading extends ReaderState {}

class ReaderLoaded extends ReaderState {
  final BookModel book;
  final int currentPage;
  final int totalPages;
  final double progress;
  final String? cfi;

  const ReaderLoaded({
    required this.book,
    this.currentPage = 0,
    this.totalPages = 0,
    this.progress = 0.0,
    this.cfi,
  });

  @override
  List<Object?> get props => [book, currentPage, totalPages, progress, cfi];

  ReaderLoaded copyWith({
    BookModel? book,
    int? currentPage,
    int? totalPages,
    double? progress,
    String? cfi,
  }) {
    return ReaderLoaded(
      book: book ?? this.book,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      progress: progress ?? this.progress,
      cfi: cfi ?? this.cfi,
    );
  }
}

class ReaderError extends ReaderState {
  final String message;

  const ReaderError(this.message);

  @override
  List<Object?> get props => [message];
}

class ProgressSaved extends ReaderState {
  final BookModel book;
  final int currentPage;
  final int totalPages;
  final double progress;
  final String? cfi;

  const ProgressSaved({
    required this.book,
    required this.currentPage,
    required this.totalPages,
    required this.progress,
    this.cfi,
  });

  @override
  List<Object?> get props => [book, currentPage, totalPages, progress, cfi];
}

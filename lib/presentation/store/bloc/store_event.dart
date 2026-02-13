part of 'store_bloc.dart';

abstract class StoreEvent extends Equatable {
  const StoreEvent();

  @override
  List<Object?> get props => [];
}

class SearchBooks extends StoreEvent {
  final String query;
  final List<Format> formats;

  const SearchBooks(this.query, {this.formats = const [Format.pdf, Format.epub]});

  @override
  List<Object?> get props => [query, formats];
}

class LoadMoreResults extends StoreEvent {}

class ClearSearch extends StoreEvent {}

class DownloadBook extends StoreEvent {
  final UnifiedBook book;

  const DownloadBook(this.book);

  @override
  List<Object?> get props => [book];
}

class UpdateFilter extends StoreEvent {
  final List<Format> formats;

  const UpdateFilter(this.formats);

  @override
  List<Object?> get props => [formats];
}

class UpdateSourceFilter extends StoreEvent {
  final bool searchAnnasArchive;
  final bool searchLibgen;

  const UpdateSourceFilter({
    required this.searchAnnasArchive,
    required this.searchLibgen,
  });

  @override
  List<Object?> get props => [searchAnnasArchive, searchLibgen];
}

class LoadCachedBooks extends StoreEvent {
  final List<Format> formats;
  
  const LoadCachedBooks({this.formats = const [Format.pdf, Format.epub]});
  
  @override
  List<Object?> get props => [formats];
}

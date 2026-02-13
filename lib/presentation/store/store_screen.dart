import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:annas_archive_api/annas_archive_api.dart';

import '../../core/services/store_preload_service.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/repositories/book_repository.dart';
import 'bloc/store_bloc.dart';
import 'widgets/store_book_card.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => StoreBloc(
        storeRepository: context.read<StoreRepository>(),
        bookRepository: context.read<BookRepository>(),
      ),
      child: const _StoreContent(),
    );
  }
}

class _StoreContent extends StatefulWidget {
  const _StoreContent();

  @override
  State<_StoreContent> createState() => _StoreContentState();
}

class _StoreContentState extends State<_StoreContent> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  List<Format> _selectedFormats = [Format.pdf, Format.epub];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load cached books or popular fiction on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StoreBloc>().add(const LoadCachedBooks());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<StoreBloc>().add(LoadMoreResults());
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<StoreBloc>().add(SearchBooks(query, formats: _selectedFormats));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Store'),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search books...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    context.read<StoreBloc>().add(ClearSearch());
                  },
                ),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  if (_searchController.text.isNotEmpty) {
                    _debounce?.cancel();
                    context.read<StoreBloc>().add(SearchBooks(_searchController.text, formats: _selectedFormats));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return BlocBuilder<StoreBloc, StoreState>(
      builder: (context, state) {
        // Sync with bloc state
        if (state is StoreResults) {
          _selectedFormats = state.formats;
        }
        
        List<Format> selectedFormats = _selectedFormats;
        bool searchAnnasArchive = true;
        bool searchLibgen = true;

        if (state is StoreResults) {
          searchAnnasArchive = state.searchAnnasArchive;
          searchLibgen = state.searchLibgen;
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Source filters
              FilterChip(
                avatar: const Icon(Icons.archive, size: 16),
                label: const Text("Anna's"),
                selected: searchAnnasArchive,
                selectedColor: Colors.purple.withOpacity(0.3),
                onSelected: (selected) {
                  if (selected || searchLibgen) {
                    context.read<StoreBloc>().add(UpdateSourceFilter(
                      searchAnnasArchive: selected,
                      searchLibgen: searchLibgen,
                    ));
                  }
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.library_books, size: 16),
                label: const Text('LibGen'),
                selected: searchLibgen,
                selectedColor: Colors.orange.withOpacity(0.3),
                onSelected: (selected) {
                  if (selected || searchAnnasArchive) {
                    context.read<StoreBloc>().add(UpdateSourceFilter(
                      searchAnnasArchive: searchAnnasArchive,
                      searchLibgen: selected,
                    ));
                  }
                },
              ),
              const SizedBox(width: 16),
              Container(
                height: 24,
                width: 1,
                color: Colors.grey[300],
              ),
              const SizedBox(width: 16),
              // Format filters
              FilterChip(
                label: const Text('PDF'),
                selected: selectedFormats.contains(Format.pdf),
                onSelected: (selected) {
                  final formats = <Format>[...selectedFormats];
                  if (selected) {
                    formats.add(Format.pdf);
                  } else {
                    formats.remove(Format.pdf);
                  }
                  if (formats.isNotEmpty) {
                    setState(() {
                      _selectedFormats = formats;
                    });
                    context.read<StoreBloc>().add(UpdateFilter(formats));
                  }
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('EPUB'),
                selected: selectedFormats.contains(Format.epub),
                onSelected: (selected) {
                  final formats = <Format>[...selectedFormats];
                  if (selected) {
                    formats.add(Format.epub);
                  } else {
                    formats.remove(Format.epub);
                  }
                  if (formats.isNotEmpty) {
                    setState(() {
                      _selectedFormats = formats;
                    });
                    context.read<StoreBloc>().add(UpdateFilter(formats));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    return BlocConsumer<StoreBloc, StoreState>(
      listener: (context, state) {
        if (state is BookDownloaded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded "${state.book.title}"'),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Go to Library',
                onPressed: () {
                  // Navigate to library tab
                },
              ),
            ),
          );
        } else if (state is StoreError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is StoreInitial) {
          return _buildInitialView();
        }

        if (state is StoreSearching) {
          return const Center(child: CircularProgressIndicator());
        }

        List<UnifiedBook> books = [];
        bool isLoadingMore = false;
        UnifiedBook? downloadingBook;
        double downloadProgress = 0;

        if (state is StoreResults) {
          books = state.books;
        } else if (state is StoreLoadingMore) {
          books = state.currentBooks;
          isLoadingMore = true;
        } else if (state is BookDownloading) {
          books = state.currentBooks;
          downloadingBook = state.book;
          downloadProgress = state.progress;
        } else if (state is StoreError) {
          books = state.previousBooks;
        }

        if (books.isEmpty) {
          return _buildEmptyResults();
        }

        return _buildResultsGrid(
          books,
          isLoadingMore,
          downloadingBook,
          downloadProgress,
        );
      },
    );
  }

  Widget _buildInitialView() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 100,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Search for Books',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Find and download books from Anna\'s Archive & LibGen',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No books found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsGrid(
    List<UnifiedBook> books,
    bool isLoadingMore,
    UnifiedBook? downloadingBook,
    double downloadProgress,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 1200
        ? 6
        : screenWidth > 900
            ? 5
            : screenWidth > 600
                ? 4
                : 3;

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            // Add caching for better performance
            cacheExtent: 200,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.55,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              final isDownloading = downloadingBook?.md5 == book.md5;

              // Use RepaintBoundary to prevent unnecessary repaints
              return RepaintBoundary(
                child: StoreBookCard(
                  book: book,
                  onDownload: () {
                    context.read<StoreBloc>().add(DownloadBook(book));
                  },
                  isDownloading: isDownloading,
                  downloadProgress: isDownloading ? downloadProgress : 0,
                ),
              );
            },
          ),
        ),
        if (isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}

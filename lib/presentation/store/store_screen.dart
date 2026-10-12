import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'bloc/store_bloc.dart';
import 'widgets/store_book_card.dart';
import 'anna_browser_screen.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final settings = context.read<SettingsRepository>();
      final sources = <BookSource>{
        if (settings.getSearchAnnasArchive()) BookSource.annasArchive,
        if (settings.getSearchLibgen()) BookSource.libgen,
        if (settings.getSearchGutenberg()) BookSource.gutenberg,
        if (settings.getSearchStandardEbooks()) BookSource.standardEbooks,
      };
      return StoreBloc(
        storeRepository: context.read<StoreRepository>(),
        bookRepository: context.read<BookRepository>(),
        initialSources: sources.isEmpty ? {BookSource.gutenberg} : sources,
      )..add(const LoadPopularBooks());
    },
    child: const _StoreContent(),
  );
}

class _StoreContent extends StatefulWidget {
  const _StoreContent();
  @override
  State<_StoreContent> createState() => _StoreContentState();
}

class _StoreContentState extends State<_StoreContent> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _retry(StoreState state) {
    if (state.query.isEmpty) {
      context.read<StoreRepository>().clearCache();
      context.read<StoreBloc>().add(const LoadPopularBooks());
    } else {
      context.read<StoreBloc>().add(
        SearchBooks(state.query, forceRefresh: true),
      );
    }
  }

  Future<void> _openAnna(StoreState state, {UnifiedBook? book}) async {
    final repository = context.read<StoreRepository>();
    final query = state.query;
    final result = await Navigator.push<AnnaBrowserResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AnnaBrowserScreen(
          repository: repository,
          initialUrl: book?.detailUrl != null
              ? Uri.parse(book!.detailUrl!)
              : repository.annaSearchUrl(query, state.formats),
          book: book,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.search != null) {
      context.read<StoreBloc>().add(UseBrowserResults(query, result.search!));
    }
    if (result.download != null) {
      context.read<StoreBloc>().add(DownloadBook(result.download!));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Book Store')),
    body: BlocConsumer<StoreBloc, StoreState>(
      listenWhen: (previous, current) =>
          previous.noticeVersion != current.noticeVersion,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.notice!),
            behavior: SnackBarBehavior.floating,
            backgroundColor: state.noticeIsError
                ? Theme.of(context).colorScheme.error
                : null,
            action: state.noticeIsError
                ? null
                : SnackBarAction(
                    label: 'Library',
                    onPressed: () => context.go('/'),
                  ),
          ),
        );
      },
      builder: (context, state) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (query) {
                setState(() {});
                context.read<StoreBloc>().add(
                  SearchBooks(query, debounce: true),
                );
              },
              onSubmitted: (query) =>
                  context.read<StoreBloc>().add(SearchBooks(query)),
              decoration: InputDecoration(
                hintText: 'Search title or author',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          context.read<StoreBloc>().add(const ClearSearch());
                        },
                      ),
                    IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => context.read<StoreBloc>().add(
                        SearchBooks(_searchController.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final format in Format.values)
                    FilterChip(
                      label: Text(format.name.toUpperCase()),
                      selected: state.formats.contains(format),
                      onSelected: (selected) {
                        final formats = {...state.formats};
                        selected ? formats.add(format) : formats.remove(format);
                        if (formats.isNotEmpty) {
                          context.read<StoreBloc>().add(UpdateFilter(formats));
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final source in BookSource.values)
                    FilterChip(
                      label: Text(source.label),
                      selected: state.sources.contains(source),
                      onSelected: (selected) {
                        final sources = {...state.sources};
                        selected ? sources.add(source) : sources.remove(source);
                        if (sources.isNotEmpty) {
                          context.read<StoreBloc>().add(
                            UpdateSourceFilter(sources),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
          if (state.warnings.isNotEmpty ||
              (state.error != null && state.books.isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.error ?? state.warnings.join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _retry(state),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (state.sources.contains(BookSource.annasArchive) &&
              state.query.isNotEmpty)
            TextButton.icon(
              onPressed: () => _openAnna(state),
              icon: const Icon(Icons.public),
              label: const Text("Open Anna's Archive"),
            ),
          Expanded(child: _content(state)),
        ],
      ),
    ),
  );

  Widget _content(StoreState state) {
    if (state.status == SearchStatus.searching && state.books.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching book catalogs…'),
          ],
        ),
      );
    }
    if (state.status == SearchStatus.failure) {
      return _message(
        Icons.cloud_off_outlined,
        'Search unavailable',
        state.error ?? 'Please try again.',
        action: FilledButton.icon(
          onPressed: () => _retry(state),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry search'),
        ),
      );
    }
    if (state.status == SearchStatus.initial) {
      return _message(
        Icons.menu_book_outlined,
        'Find your next book',
        'Search by title or author, or browse popular classics.',
        action: FilledButton(
          onPressed: () =>
              context.read<StoreBloc>().add(const LoadPopularBooks()),
          child: const Text('Browse classics'),
        ),
      );
    }
    if (state.books.isEmpty) {
      return _message(
        Icons.search_off,
        state.warnings.isEmpty
            ? 'No matching books'
            : 'No books from available sources',
        '${state.warnings.isEmpty ? 'Try a different title or author.' : 'Some sources could not be reached. Retry or choose another source.'}\n'
        'Try both EPUB and PDF. Gutenberg and Standard Ebooks mainly have EPUB classics.',
        action: state.hasMore
            ? OutlinedButton(
                onPressed: state.loadingMore
                    ? null
                    : () => context.read<StoreBloc>().add(
                        const LoadMoreResults(),
                      ),
                child: Text(
                  state.loadingMore ? 'Loading…' : 'Check the next page',
                ),
              )
            : null,
      );
    }
    return Column(
      children: [
        if (state.status == SearchStatus.searching)
          const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              state.query.isEmpty
                  ? 'Popular classics · Gutenberg and Standard Ebooks'
                  : '${state.books.length} book files',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final preferred = context
                  .read<SettingsRepository>()
                  .getDownloadFormat();
              final visibleBooks = [
                ...state.books.where((b) => b.extension == preferred),
                ...state.books.where((b) => b.extension != preferred),
              ];
              final columns = (constraints.maxWidth / 190).floor().clamp(2, 6);
              return GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 340,
                ),
                itemCount: state.books.length,
                itemBuilder: (context, index) {
                  final book = visibleBooks[index];
                  return StoreBookCard(
                    book: book,
                    isDownloading: state.downloads.containsKey(book.id),
                    downloadProgress: state.downloads[book.id] ?? 0,
                    isDownloaded: state.downloadedIds.contains(book.id),
                    onCancel: () =>
                        context.read<StoreBloc>().add(CancelDownload(book.id)),
                    onDownload: () {
                      if (state.downloadedIds.contains(book.id)) {
                        context.go('/');
                      } else if (book.source == BookSource.annasArchive) {
                        _openAnna(state, book: book);
                      } else {
                        context.read<StoreBloc>().add(DownloadBook(book));
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        if (state.loadingMore)
          const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          )
        else if (state.hasMore)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton(
              onPressed: () =>
                  context.read<StoreBloc>().add(const LoadMoreResults()),
              child: Text(
                state.error == null ? 'Load more books' : 'Retry loading more',
              ),
            ),
          ),
      ],
    );
  }

  Widget _message(
    IconData icon,
    String title,
    String description, {
    Widget? action,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(description, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );
}

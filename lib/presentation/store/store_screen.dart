import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'bloc/store_bloc.dart';
import 'widgets/store_book_card.dart';
import 'anna_browser_screen.dart';
import '../shared/active_tab_scope.dart';
import '../shared/anchored_book_grid.dart';
import '../shared/page_header.dart';
import '../../core/theme/paper_ink_layout.dart';

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
  bool _active = true;
  bool _browserOpen = false;
  bool _sourcesEdited = false;
  final _downloadBooks = <String, UnifiedBook>{};
  StoreState? _pendingNotice;
  int _shownNoticeVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = ActiveTabScope.isActiveOf(context);
    if (_active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPendingNotice();
        _resumeVerification();
      });
    }
  }

  void _showPendingNotice() {
    if (!mounted || !_active || _browserOpen) return;
    final state = _pendingNotice;
    if (state == null || state.noticeVersion <= _shownNoticeVersion) return;
    _pendingNotice = null;
    _shownNoticeVersion = state.noticeVersion;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state.notice!),
        backgroundColor: state.noticeIsError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
        action: state.noticeIsError
            ? null
            : SnackBarAction(
                label: 'Library',
                onPressed: () => context.go('/'),
              ),
      ),
    );
  }

  void _submitSearch(String query, {bool debounce = false}) {
    final bloc = context.read<StoreBloc>();
    if (query.trim() != bloc.state.query) _resetScroll();
    if (!_sourcesEdited) {
      final settings = context.read<SettingsRepository>();
      final defaults = <BookSource>{
        if (settings.getSearchAnnasArchive()) BookSource.annasArchive,
        if (settings.getSearchLibgen()) BookSource.libgen,
        if (settings.getSearchGutenberg()) BookSource.gutenberg,
        if (settings.getSearchStandardEbooks()) BookSource.standardEbooks,
      };
      if (defaults.isNotEmpty &&
          (defaults.length != bloc.state.sources.length ||
              !defaults.containsAll(bloc.state.sources))) {
        bloc.add(UpdateSourceFilter(defaults));
      }
    }
    bloc.add(SearchBooks(query, debounce: debounce));
  }

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

  Future<void> _openAnna(
    StoreState state, {
    UnifiedBook? book,
    Uri? verificationUrl,
    Set<Uri> verifiedPages = const {},
  }) async {
    if (!mounted || !_active || _browserOpen) return;
    final repository = context.read<StoreRepository>();
    final query = state.query;
    _browserOpen = true;
    AnnaBrowserResult? result;
    try {
      result = await Navigator.push<AnnaBrowserResult>(
        context,
        MaterialPageRoute(
          builder: (_) => AnnaBrowserScreen(
            repository: repository,
            initialUrl:
                verificationUrl ??
                (book?.detailUrl != null
                    ? Uri.parse(book!.detailUrl!)
                    : repository.annaSearchUrl(query, state.formats)),
            book: book,
          ),
        ),
      );
    } finally {
      _browserOpen = false;
      _showPendingNotice();
    }
    if (!mounted) return;
    if (result?.search != null) {
      context.read<StoreBloc>().add(UseBrowserResults(query, result!.search!));
    }
    if (result?.download != null) {
      final download = result!.download!;
      _downloadBooks[download.id] = download;
      context.read<StoreBloc>().add(
        DownloadBook(
          download,
          verifiedPages: {
            ...verifiedPages,
            if (result.verifiedPage != null) result.verifiedPage!,
          },
        ),
      );
    }
    _resumeVerification();
  }

  Future<void> _resumeVerification() async {
    if (!mounted || !_active || _browserOpen) return;
    final bloc = context.read<StoreBloc>();
    if (bloc.state.verificationRequests.isEmpty) return;
    final request = bloc.state.verificationRequests.first;
    bloc.add(ConsumeDownloadVerification(request));
    await _openAnna(
      bloc.state,
      book: request.book,
      verificationUrl: request.url,
      verifiedPages: request.verifiedPages,
    );
  }

  void _getBook(StoreState state, UnifiedBook book) {
    if (state.downloadedIds.contains(book.id)) {
      context.go('/');
    } else {
      _downloadBooks[book.id] = book;
      context.read<StoreBloc>().add(DownloadBook(book));
    }
  }

  void _resetScroll() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: BlocConsumer<StoreBloc, StoreState>(
        listenWhen: (previous, current) =>
            previous.noticeVersion != current.noticeVersion ||
            previous.verificationRequests != current.verificationRequests,
        listener: (context, state) {
          if (state.notice != null &&
              state.noticeVersion > _shownNoticeVersion) {
            _pendingNotice = state;
            _showPendingNotice();
          }
          _resumeVerification();
        },
        builder: (context, state) => LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final layout = PaperInkLayout.forWidth(
              constraints.maxWidth,
              textScale: scale,
            );
            final inner = constraints.maxWidth - layout.gutter * 2;
            final columns = inner >= 840 && scale < 1.5 ? 2 : 1;
            final preferred = context
                .read<SettingsRepository>()
                .getDownloadFormat();
            final books = [
              ...state.books.where((book) => book.extension == preferred),
              ...state.books.where((book) => book.extension != preferred),
            ];
            final width = (inner - 24 * (columns - 1)) / columns;
            final ids = books.map((book) => book.id).toList();
            _downloadBooks.removeWhere(
              (id, _) => !state.downloads.containsKey(id),
            );
            final footer = Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 32),
              child: state.loadingMore
                  ? const Center(child: CircularProgressIndicator())
                  : state.hasMore && books.isNotEmpty
                  ? OutlinedButton(
                      onPressed: () => context.read<StoreBloc>().add(
                        const LoadMoreResults(),
                      ),
                      child: Text(
                        state.error == null
                            ? 'Load more books'
                            : 'Retry loading more',
                      ),
                    )
                  : const SizedBox.shrink(),
            );
            return AnchoredBookGrid(
              ids: ids,
              controller: _scrollController,
              header: _header(state, layout.gutter, ids),
              empty: _emptyContent(state),
              footer: footer,
              columns: columns,
              itemExtent: StoreBookCard.itemExtent(context, width),
              gutter: layout.gutter,
              storageKey: 'store-scroll',
              itemBuilder: (context, index) {
                final book = books[index];
                return StoreBookCard(
                  book: book,
                  isDownloading: state.downloads.containsKey(book.id),
                  downloadProgress: state.downloads[book.id] ?? 0,
                  isDownloaded: state.downloadedIds.contains(book.id),
                  onCancel: () =>
                      context.read<StoreBloc>().add(CancelDownload(book.id)),
                  onDownload: () => _getBook(state, book),
                );
              },
            );
          },
        ),
      ),
    ),
  );

  Widget _header(StoreState state, double gutter, List<String> visibleIds) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(title: 'Store'),
          const SizedBox(height: 24),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (query) {
              setState(() {});
              _submitSearch(query, debounce: true);
            },
            onSubmitted: _submitSearch,
            decoration: InputDecoration(
              labelText: 'Search books',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              hintText: 'Title or author',
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
                        _resetScroll();
                        setState(() {});
                        context.read<StoreBloc>().add(const ClearSearch());
                      },
                    ),
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _submitSearch(_searchController.text),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (state.status == SearchStatus.failure) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search unavailable',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(state.error ?? 'Please try again.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _retry(state),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry search'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text('Format', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in Format.values)
                FilterChip(
                  label: Text(format.name.toUpperCase()),
                  selected: state.formats.contains(format),
                  labelStyle: TextStyle(
                    color: state.formats.contains(format)
                        ? colors.onPrimary
                        : colors.onSurface,
                  ),
                  onSelected: (selected) {
                    final formats = {...state.formats};
                    selected ? formats.add(format) : formats.remove(format);
                    if (formats.isNotEmpty) {
                      _resetScroll();
                      context.read<StoreBloc>().add(UpdateFilter(formats));
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Sources', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final source in BookSource.values)
                FilterChip(
                  label: Text(source.label),
                  selected: state.sources.contains(source),
                  labelStyle: TextStyle(
                    color: state.sources.contains(source)
                        ? colors.onPrimary
                        : colors.onSurface,
                  ),
                  onSelected: (selected) {
                    final sources = {...state.sources};
                    selected ? sources.add(source) : sources.remove(source);
                    if (sources.isNotEmpty) {
                      _sourcesEdited = true;
                      _resetScroll();
                      context.read<StoreBloc>().add(
                        UpdateSourceFilter(sources),
                      );
                    }
                  },
                ),
            ],
          ),
          for (final warning in state.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(warning)),
                ],
              ),
            ),
          if (state.error != null && state.books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(state.error!),
            ),
          if (state.warnings.isNotEmpty && state.status != SearchStatus.failure)
            TextButton.icon(
              onPressed: () => _retry(state),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry search'),
            ),
          if (state.sources.contains(BookSource.annasArchive) &&
              state.query.isNotEmpty)
            TextButton.icon(
              onPressed: () => _openAnna(state),
              icon: const Icon(Icons.public),
              label: const Text("Open Anna's Archive"),
            ),
          for (final id in state.downloads.keys.where(
            (id) => !visibleIds.contains(id),
          ))
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloadBooks[id]?.title ?? 'Book download',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.downloads[id]! > 0
                            ? 'Downloading ${(state.downloads[id]! * 100).toInt()}%'
                            : 'Connecting…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: state.downloads[id]! > 0
                            ? state.downloads[id]!.clamp(0, 1)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () =>
                            context.read<StoreBloc>().add(CancelDownload(id)),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (state.status == SearchStatus.searching && state.books.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (state.books.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              state.query.isEmpty
                  ? 'Popular classics · Gutenberg and Standard Ebooks'
                  : '${state.books.length} book files',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
          SizedBox(height: math.max(8, scaler.scale(12) / 2)),
        ],
      ),
    );
  }

  Widget _emptyContent(StoreState state) {
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
      return const SizedBox.shrink();
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
    return const SizedBox.shrink();
  }

  Widget _message(
    IconData icon,
    String title,
    String description, {
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(description, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 24), action],
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/paper_ink_layout.dart';
import '../../data/models/book_model.dart';
import '../shared/active_tab_scope.dart';
import '../shared/page_header.dart';
import 'bloc/library_bloc.dart';
import 'widgets/library_grid.dart';
import 'widgets/continue_reading_card.dart';

enum LibrarySort {
  recentlyRead('Recently read'),
  title('Title'),
  author('Author'),
  dateAdded('Date added');

  final String label;
  const LibrarySort(this.label);
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scrollController = ScrollController();
  LibrarySort _sort = LibrarySort.recentlyRead;
  List<BookModel> _lastBooks = [];
  LibraryState? _pendingNotice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ActiveTabScope.isActiveOf(context) && _pendingNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingNotice());
    }
  }

  void _showPendingNotice() {
    if (!mounted || !ActiveTabScope.isActiveOf(context)) return;
    final state = _pendingNotice;
    _pendingNotice = null;
    final messenger = ScaffoldMessenger.of(context);
    if (state is BookImported) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Added "${state.importedBook.title}" to library'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openBook(context, state.importedBook),
          ),
        ),
      );
    } else if (state is BookDeleted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Book removed from library')),
      );
    } else if (state is LibraryError) {
      messenger.showSnackBar(SnackBar(content: Text(state.message)));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<BookModel> _sorted(List<BookModel> books) => [...books]
    ..sort((a, b) {
      final result = switch (_sort) {
        LibrarySort.recentlyRead => b.lastReadTime.compareTo(a.lastReadTime),
        LibrarySort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        LibrarySort.author => a.author.toLowerCase().compareTo(
          b.author.toLowerCase(),
        ),
        LibrarySort.dateAdded => b.addedTime.compareTo(a.addedTime),
      };
      return result == 0 ? a.id.compareTo(b.id) : result;
    });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: BlocConsumer<LibraryBloc, LibraryState>(
        listener: (context, state) {
          if (state is BookImported ||
              state is BookDeleted ||
              state is LibraryError) {
            _pendingNotice = state;
            _showPendingNotice();
          }
        },
        builder: (context, state) => LayoutBuilder(
          builder: (context, constraints) {
            final layout = PaperInkLayout.forWidth(
              constraints.maxWidth,
              textScale: MediaQuery.textScalerOf(context).scale(16) / 16,
            );
            final raw = _getBooksFromState(state);
            if (state is! LibraryError &&
                state is! LibraryLoading &&
                state is! LibraryInitial) {
              _lastBooks = raw;
            }
            final books = _sorted(raw);
            final current = selectContinueReading(raw);
            final header = Padding(
              padding: EdgeInsets.fromLTRB(
                layout.gutter,
                24,
                layout.gutter,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Library',
                    actions: [
                      TextButton.icon(
                        onPressed: () => context.push('/stats'),
                        icon: const Icon(Icons.bar_chart_outlined),
                        label: const Text('Stats'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showSortOptions(context),
                        icon: const Icon(Icons.sort),
                        label: const Text('Sort'),
                      ),
                      FilledButton.icon(
                        onPressed: state is BookImporting
                            ? null
                            : () =>
                                  context.read<LibraryBloc>().add(ImportBook()),
                        icon: const Icon(Icons.add),
                        label: const Text('Import'),
                      ),
                    ],
                  ),
                  if (current != null) ...[
                    const SizedBox(height: 24),
                    ContinueReadingCard(
                      book: current,
                      onContinue: () => _openBook(context, current),
                    ),
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                  ],
                  if (books.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'All books · ${_sort.label}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ],
              ),
            );
            if (state is LibraryLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return Stack(
              children: [
                LibraryGrid(
                  books: books,
                  controller: _scrollController,
                  header: header,
                  onBookTap: (book) => _openBook(context, book),
                  onBookLongPress: (book) => _showBookOptions(context, book),
                ),
                if (state is BookImporting)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.scrim.withValues(alpha: 0.7),
                      child: const Center(
                        child: Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Importing book…'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  List<BookModel> _getBooksFromState(LibraryState state) {
    if (state is LibraryLoaded) return state.books;
    if (state is BookImported) return state.books;
    if (state is BookDeleted) return state.books;
    if (state is BookImporting) return state.currentBooks;
    return _lastBooks;
  }

  void _openBook(BuildContext context, BookModel book) {
    if (book.isPdf) {
      context.push('/reader/pdf/${book.id}');
    } else {
      context.push('/reader/epub/${book.id}');
    }
  }

  void _showBookOptions(BuildContext context, BookModel book) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Book Info'),
              onTap: () {
                Navigator.pop(context);
                _showBookInfo(context, book);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, book);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBookInfo(BuildContext context, BookModel book) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(book.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Author', book.author),
              _infoRow('Format', book.format.toUpperCase()),
              if (book.fileSize != null)
                _infoRow('Size', _formatFileSize(book.fileSize!)),
              _infoRow('Progress', '${book.readingPercentage}%'),
              if (book.lastReadPage > 0)
                _infoRow('Last Page', book.lastReadPage.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _confirmDelete(BuildContext context, BookModel book) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Book?'),
        content: Text(
          'Are you sure you want to remove "${book.title}" from your library?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<LibraryBloc>().add(DeleteBook(book.id));
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSortOptions(BuildContext context) {
    showModalBottomSheet<LibrarySort>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sort books', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              for (final sort in LibrarySort.values)
                ListTile(
                  title: Text(sort.label),
                  selected: _sort == sort,
                  trailing: _sort == sort ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, sort),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ).then((sort) {
      if (!mounted || sort == null) return;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      setState(() => _sort = sort);
    });
  }
}

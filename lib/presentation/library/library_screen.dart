import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_cubit.dart';
import '../../data/models/book_model.dart';
import 'bloc/library_bloc.dart';
import 'widgets/library_grid.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          BlocBuilder<ThemeCubit, ThemeState>(
            builder: (context, state) {
              return IconButton(
                icon: Icon(
                  state.themeMode == ThemeMode.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                ),
                onPressed: () {
                  context.read<ThemeCubit>().toggleTheme();
                },
                tooltip: 'Toggle theme',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () {
              _showSortOptions(context);
            },
          ),
        ],
      ),
      body: BlocConsumer<LibraryBloc, LibraryState>(
        listener: (context, state) {
          if (state is BookImported) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added "${state.importedBook.title}" to library'),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Open',
                  onPressed: () => _openBook(context, state.importedBook),
                ),
              ),
            );
          } else if (state is BookDeleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Book removed from library'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else if (state is LibraryError) {
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
          if (state is LibraryLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final books = _getBooksFromState(state);

          if (books.isEmpty) {
            return const EmptyLibraryView();
          }

          return Stack(
            children: [
              LibraryGrid(
                books: books,
                onBookTap: (book) => _openBook(context, book),
                onBookLongPress: (book) => _showBookOptions(context, book),
              ),
              if (state is BookImporting)
                Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Importing book...'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.read<LibraryBloc>().add(ImportBook());
        },
        icon: const Icon(Icons.add),
        label: const Text('Import'),
      ),
    );
  }

  List<BookModel> _getBooksFromState(LibraryState state) {
    if (state is LibraryLoaded) return state.books;
    if (state is BookImported) return state.books;
    if (state is BookDeleted) return state.books;
    if (state is BookImporting) return state.currentBooks;
    return [];
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
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
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
        content: Column(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

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
        content: Text('Are you sure you want to remove "${book.title}" from your library?'),
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
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSortOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sort By',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Recently Read'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.abc),
              title: const Text('Title'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Author'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Date Added'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/book_model.dart';
import '../bloc/library_bloc.dart';
import 'book_card.dart';

class LibraryGrid extends StatelessWidget {
  final List<BookModel> books;
  final void Function(BookModel book) onBookTap;
  final void Function(BookModel book) onBookLongPress;

  const LibraryGrid({
    super.key,
    required this.books,
    required this.onBookTap,
    required this.onBookLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Responsive grid columns based on screen width
    final crossAxisCount = screenWidth > 1200
        ? 6
        : screenWidth > 900
            ? 5
            : screenWidth > 600
                ? 4
                : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      // Add caching for better performance
      cacheExtent: 200,
      // Use builder with findChildIndexCallback for better performance with large lists
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.65,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        // Use RepaintBoundary to prevent unnecessary repaints
        return RepaintBoundary(
          child: BookCard(
            book: book,
            onTap: () => onBookTap(book),
            onLongPress: () => onBookLongPress(book),
          ),
        );
      },
    );
  }
}

class EmptyLibraryView extends StatelessWidget {
  const EmptyLibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 120,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'Your Library is Empty',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Import books or browse the store to get started',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              context.read<LibraryBloc>().add(ImportBook());
            },
            icon: const Icon(Icons.add),
            label: const Text('Import Book'),
          ),
        ],
      ),
    );
  }
}

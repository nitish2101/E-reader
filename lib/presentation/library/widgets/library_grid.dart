import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/paper_ink_layout.dart';
import '../../../data/models/book_model.dart';
import '../../shared/anchored_book_grid.dart';
import '../bloc/library_bloc.dart';
import 'book_card.dart';

class LibraryGrid extends StatelessWidget {
  final List<BookModel> books;
  final void Function(BookModel book) onBookTap;
  final void Function(BookModel book) onBookLongPress;
  final ScrollController controller;
  final Widget header;
  const LibraryGrid({
    super.key,
    required this.books,
    required this.onBookTap,
    required this.onBookLongPress,
    required this.controller,
    required this.header,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final layout = PaperInkLayout.forWidth(
        constraints.maxWidth,
        textScale: scaler.scale(16) / 16,
      );
      final innerWidth = constraints.maxWidth - 2 * layout.gutter;
      final columns = PaperInkLayout.forWidth(
        innerWidth + 32,
        textScale: scaler.scale(16) / 16,
      ).libraryColumns;
      final coverWidth = (innerWidth - 24 * (columns - 1)) / columns;
      final titleLines = scaler.scale(16) > 24 ? 3 : 2;
      final extent =
          coverWidth * 1.5 +
          scaler.scale(16) * 1.4 * titleLines +
          scaler.scale(14) * 1.45 +
          scaler.scale(12) * 2.8 +
          68;
      return AnchoredBookGrid(
        ids: books.map((book) => book.id).toList(),
        controller: controller,
        header: header,
        empty: const EmptyLibraryView(),
        columns: columns,
        itemExtent: extent,
        gutter: layout.gutter,
        storageKey: 'library-scroll',
        itemBuilder: (context, index) {
          final book = books[index];
          return BookCard(
            book: book,
            onTap: () => onBookTap(book),
            onLongPress: () => onBookLongPress(book),
            onOptions: () => onBookLongPress(book),
          );
        },
      );
    },
  );
}

class EmptyLibraryView extends StatelessWidget {
  const EmptyLibraryView({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.menu_book_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Your library starts here',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Import a PDF or EPUB, or find your next book in the Store.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => context.read<LibraryBloc>().add(ImportBook()),
          icon: const Icon(Icons.add),
          label: const Text('Import Book'),
        ),
      ],
    ),
  );
}

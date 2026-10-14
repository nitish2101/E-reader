import 'package:flutter/material.dart';
import '../../../data/models/book_model.dart';
import '../../shared/book_cover.dart';
import '../../shared/book_progress.dart';

class BookCard extends StatelessWidget {
  final BookModel book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onOptions;
  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
    required this.onLongPress,
    this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                BookCover(
                  localPath: book.localCoverPath,
                  url: book.coverUrl,
                  title: book.title,
                  format: book.format,
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Material(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(4),
                    child: IconButton(
                      tooltip: 'Options for ${book.title}',
                      icon: const Icon(Icons.more_vert),
                      onPressed: onOptions ?? onLongPress,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              book.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: largeText ? 3 : 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              book.author,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(book.format.toUpperCase(), style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            BookProgress(
              progress: book.lastReadProgress,
              label: book.hasStartedReading
                  ? '${book.readingPercentage}% complete'
                  : 'Not started',
            ),
          ],
        ),
      ),
    );
  }
}

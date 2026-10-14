import 'package:flutter/material.dart';
import '../../../data/models/book_model.dart';
import '../../shared/book_cover.dart';
import '../../shared/book_progress.dart';

BookModel? selectContinueReading(List<BookModel> books) {
  BookModel? latest;
  for (final book in books) {
    if (book.hasStartedReading &&
        (latest == null || book.lastReadTime.isAfter(latest.lastReadTime))) {
      latest = book;
    }
  }
  return latest;
}

class ContinueReadingCard extends StatelessWidget {
  final BookModel book;
  final VoidCallback onContinue;
  const ContinueReadingCard({
    super.key,
    required this.book,
    required this.onContinue,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final compact =
          constraints.maxWidth < 600 ||
          MediaQuery.textScalerOf(context).scale(16) > 24;
      final button = FilledButton(
        onPressed: onContinue,
        child: const Text('Continue reading'),
      );
      final details = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: BookCover(
              localPath: book.localCoverPath,
              url: book.coverUrl,
              title: book.title,
              format: book.format,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue reading',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: BookProgress(
                    progress: book.lastReadProgress,
                    label: '${book.readingPercentage}% complete',
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[const SizedBox(width: 24), button],
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          details,
          if (compact) ...[const SizedBox(height: 16), button],
        ],
      );
    },
  );
}

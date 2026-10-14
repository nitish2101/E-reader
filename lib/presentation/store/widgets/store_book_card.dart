import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../data/repositories/store_repository.dart';
import '../../shared/book_cover.dart';

class StoreBookCard extends StatelessWidget {
  final UnifiedBook book;
  final VoidCallback onDownload;
  final bool isDownloading;
  final bool isDownloaded;
  final double downloadProgress;
  final VoidCallback? onCancel;
  const StoreBookCard({
    super.key,
    required this.book,
    required this.onDownload,
    this.isDownloading = false,
    this.isDownloaded = false,
    this.downloadProgress = 0,
    this.onCancel,
  });

  static double itemExtent(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final lines = scaler.scale(16) > 24 ? 3 : 2;
    final cover = width < 380 ? 88.0 : 112.0;
    final metadata =
        scaler.scale(16) * 1.4 * lines +
        scaler.scale(14) * 1.45 +
        scaler.scale(12) * 1.4 * 3 +
        math.max(48, scaler.scale(14) * 1.4 + 24) +
        104;
    return 32 + math.max(cover * 1.5, metadata);
  }

  void _showDetails(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(book.author),
            const SizedBox(height: 16),
            Text('${book.source.label} · ${book.extension.toUpperCase()}'),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final lines = scaler.scale(16) > 24 ? 3 : 2;
      final coverWidth = constraints.maxWidth < 380 ? 88.0 : 112.0;
      final progress = downloadProgress.isFinite
          ? downloadProgress.clamp(0.0, 1.0)
          : 0.0;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetails(context),
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: coverWidth,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: BookCover(
                        url: book.coverUrl,
                        title: book.title,
                        format: book.extension,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: scaler.scale(16) * 1.4 * lines,
                          child: Text(
                            book.title,
                            maxLines: lines,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${book.source.label} · ${book.extension.toUpperCase()}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        const Spacer(),
                        SizedBox(
                          height: scaler.scale(12) * 1.4 + 20,
                          child: isDownloading
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      progress > 0
                                          ? 'Downloading ${(progress * 100).toInt()}%'
                                          : 'Connecting…',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: progress > 0 ? progress : null,
                                      minHeight: 4,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        if (isDownloading)
                          OutlinedButton(
                            onPressed: onCancel,
                            child: const Text('Cancel'),
                          )
                        else
                          FilledButton(
                            onPressed: onDownload,
                            child: Text(isDownloaded ? 'Library' : 'Get'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

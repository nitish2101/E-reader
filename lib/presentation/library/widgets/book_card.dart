import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/services/cache_config.dart';
import '../../../data/models/book_model.dart';

class BookCard extends StatelessWidget {
  final BookModel book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Memoize computed values to avoid rebuild overhead
    final formatColor = book.isPdf 
        ? Colors.red.withOpacity(0.9) 
        : Colors.blue.withOpacity(0.9);
    final formatText = book.format.toUpperCase();
    
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(context),
                  // Format badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: formatColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Reading progress indicator
                  if (book.hasStartedReading)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: book.lastReadProgress < 0.01 ? 0.01 : book.lastReadProgress,
                        backgroundColor: Colors.black26,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                        minHeight: 4,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        book.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      book.author,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (book.hasStartedReading) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${book.readingPercentage}% complete',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    // Check for local cover
    if (book.localCoverPath != null) {
      return Image.file(
        File(book.localCoverPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholderCover(context),
        // Add caching for better performance
        cacheWidth: 300,
        cacheHeight: 450,
      );
    }

    // Check for network cover
    if (book.coverUrl != null) {
      return CachedNetworkImage(
        imageUrl: book.coverUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildLoadingCover(context),
        errorWidget: (_, __, ___) => _buildPlaceholderCover(context),
        cacheManager: BookCoverCacheManager(),
        memCacheWidth: 300,
        memCacheHeight: 450,
        // Fade in duration for smoother loading
        fadeInDuration: const Duration(milliseconds: 200),
      );
    }

    // Fallback to placeholder
    return _buildPlaceholderCover(context);
  }

  Widget _buildPlaceholderCover(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: book.isPdf
              ? [Colors.red[300]!, Colors.red[600]!]
              : [Colors.blue[300]!, Colors.blue[600]!],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              book.isPdf ? Icons.picture_as_pdf : Icons.book,
              size: 48,
              color: Colors.white.withOpacity(0.8),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                book.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCover(BuildContext context) {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

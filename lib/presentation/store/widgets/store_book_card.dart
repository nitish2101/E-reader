import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/services/cache_config.dart';
import '../../../data/repositories/store_repository.dart';

class StoreBookCard extends StatelessWidget {
  final UnifiedBook book;
  final VoidCallback onDownload;
  final bool isDownloading;
  final double downloadProgress;

  const StoreBookCard({
    super.key,
    required this.book,
    required this.onDownload,
    this.isDownloading = false,
    this.downloadProgress = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
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
                      color: _getFormatColor().withOpacity(0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      (book.extension ?? 'PDF').toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Source badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: book.source == BookSource.annasArchive
                          ? Colors.purple.withOpacity(0.9)
                          : Colors.orange.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      book.source == BookSource.annasArchive ? 'AA' : 'LG',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Download progress overlay
                if (isDownloading)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: downloadProgress > 0 ? downloadProgress : null,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(downloadProgress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title ?? 'Unknown Title',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author ?? 'Unknown Author',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      if (book.fileSize != null && book.fileSize!.isNotEmpty)
                        Text(
                          _formatSize(book.fileSize!),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[500],
                              ),
                        ),
                      const Spacer(),
                      SizedBox(
                        height: 32,
                        child: FilledButton.icon(
                          onPressed: isDownloading ? null : onDownload,
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Get'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    if (book.coverUrl != null && book.coverUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: book.coverUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildPlaceholderCover(context),
        errorWidget: (_, __, ___) => _buildPlaceholderCover(context),
        cacheManager: BookCoverCacheManager(),
        memCacheWidth: 300,
        memCacheHeight: 450,
        fadeInDuration: const Duration(milliseconds: 200),
      );
    }
    return _buildPlaceholderCover(context);
  }

  Widget _buildPlaceholderCover(BuildContext context) {
    final isPdf = book.extension?.toLowerCase() == 'pdf';
    final isAnnasArchive = book.source == BookSource.annasArchive;
    
    // Source-specific gradient colors
    final List<Color> gradientColors = isAnnasArchive
        ? [Colors.purple[300]!, Colors.purple[700]!]
        : [Colors.orange[300]!, Colors.orange[700]!];
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Source badge in placeholder
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isAnnasArchive ? 'AA' : 'LG',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Icon(
              isPdf ? Icons.picture_as_pdf : Icons.book,
              size: 40,
              color: Colors.white.withOpacity(0.9),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                book.title ?? 'Book',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
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

  Color _getFormatColor() {
    final ext = book.extension?.toLowerCase() ?? '';
    if (ext == 'pdf') return Colors.red;
    if (ext == 'epub') return Colors.blue;
    return Colors.grey;
  }

  String _formatSize(String size) {
    final bytes = int.tryParse(size) ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

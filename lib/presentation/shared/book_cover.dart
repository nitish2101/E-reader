import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/services/cache_config.dart';

class BookCover extends StatelessWidget {
  final String? localPath;
  final String? url;
  final String title;
  final String format;
  const BookCover({
    super.key,
    this.localPath,
    this.url,
    required this.title,
    required this.format,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '$title, ${format.toUpperCase()} cover',
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: localPath != null && File(localPath!).existsSync()
              ? Image.file(
                  File(localPath!),
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  errorBuilder: (_, __, ___) => _remote(context),
                )
              : _remote(context),
        ),
      ),
    ),
  );

  Widget _remote(BuildContext context) {
    if (url == null || url!.isEmpty) return _placeholder(context);
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      cacheManager: BookCoverCacheManager(),
      memCacheWidth: 300,
      fadeInDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      placeholder: (_, __) => _placeholder(context),
      errorWidget: (_, __, ___) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: constraints.maxWidth > 100 ? 40 : 28,
                ),
                if (constraints.maxHeight >= 160 &&
                    MediaQuery.textScalerOf(context).scale(12) < 20) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Cover unavailable',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Custom cache manager for book covers
class BookCoverCacheManager extends CacheManager {
  static const key = 'bookCoverCache';

  static BookCoverCacheManager? _instance;

  factory BookCoverCacheManager() {
    _instance ??= BookCoverCacheManager._();
    return _instance!;
  }

  BookCoverCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 30),
            maxNrOfCacheObjects: 200,
          ),
        );
}

/// Initialize caching configuration
void initializeCacheConfig() {
  // Caching is now configured in the BookCoverCacheManager
  // No additional initialization needed
}

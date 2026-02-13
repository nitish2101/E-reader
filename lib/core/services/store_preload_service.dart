import '../../data/repositories/store_repository.dart';

/// Service to preload store data when app opens for faster navigation
class StorePreloadService {
  static final StorePreloadService _instance = StorePreloadService._internal();
  static StorePreloadService get instance => _instance;

  StorePreloadService._internal();

  final StoreRepository _storeRepository = StoreRepository();
  List<UnifiedBook>? _cachedBooks;
  DateTime? _lastFetchTime;
  bool _isLoading = false;

  // Cache duration (30 minutes)
  static const Duration _cacheDuration = Duration(minutes: 30);

  /// Preload popular books in background
  Future<void> preloadStoreData() async {
    if (_isLoading || _isCacheValid()) {
      return;
    }

    _isLoading = true;

    try {
      // Fetch popular books (this runs in background)
      final books = await _storeRepository.searchBooks(
        query: 'popular fiction',
        searchAnnasArchive: true,
        searchLibgen: true,
        timeout: const Duration(seconds: 45),
      );

      _cachedBooks = books;
      _lastFetchTime = DateTime.now();

      print('StorePreloadService: Preloaded ${books.length} books');
    } catch (e) {
      print('StorePreloadService: Error preloading - $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Check if cache is still valid
  bool _isCacheValid() {
    if (_cachedBooks == null || _lastFetchTime == null) return false;
    return DateTime.now().difference(_lastFetchTime!) < _cacheDuration;
  }

  /// Check if currently loading
  bool get isLoading => _isLoading;

  /// Get cached books if available
  List<UnifiedBook>? getCachedBooks() {
    if (_isCacheValid()) {
      return _cachedBooks;
    }
    return null;
  }

  /// Force refresh cache
  Future<void> refreshCache() async {
    _cachedBooks = null;
    _lastFetchTime = null;
    await preloadStoreData();
  }

  /// Clear cache
  void clearCache() {
    _cachedBooks = null;
    _lastFetchTime = null;
  }
}

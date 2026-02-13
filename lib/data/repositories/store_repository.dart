import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:annas_archive_api/annas_archive_api.dart';
import 'package:libgen_scraper/libgen_scraper.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

/// Custom exceptions for better error handling
class StoreRepositoryException implements Exception {
  final String message;
  final String? source;
  final Exception? originalError;
  
  StoreRepositoryException(this.message, {this.source, this.originalError});
  
  @override
  String toString() => 'StoreRepositoryException [$source]: $message';
}

class MirrorUnavailableException extends StoreRepositoryException {
  MirrorUnavailableException(String message, {String? source, Exception? originalError})
      : super(message, source: source, originalError: originalError);
}

class SearchTimeoutException extends StoreRepositoryException {
  SearchTimeoutException(String message, {String? source})
      : super(message, source: source);
}

class DownloadFailedException extends StoreRepositoryException {
  DownloadFailedException(String message, {String? source, Exception? originalError})
      : super(message, source: source, originalError: originalError);
}

/// Tracks mirror health status
class MirrorHealth {
  final String url;
  DateTime? lastChecked;
  bool isHealthy = true;
  int consecutiveFailures = 0;
  DateTime? lastFailure;
  int responseTimeMs = 0;
  
  MirrorHealth(this.url);
  
  void recordSuccess(int responseTime) {
    isHealthy = true;
    consecutiveFailures = 0;
    lastChecked = DateTime.now();
    responseTimeMs = responseTime;
  }
  
  void recordFailure() {
    consecutiveFailures++;
    lastFailure = DateTime.now();
    if (consecutiveFailures >= 3) {
      isHealthy = false;
    }
    lastChecked = DateTime.now();
  }
  
  /// Cooldown period increases with consecutive failures
  Duration get cooldownPeriod {
    if (consecutiveFailures == 0) return Duration.zero;
    return Duration(minutes: min(consecutiveFailures * 2, 30));
  }
  
  bool get isInCooldown {
    if (lastFailure == null) return false;
    return DateTime.now().difference(lastFailure!) < cooldownPeriod;
  }
  
  /// Should try this mirror based on health status
  bool get shouldTry => isHealthy || !isInCooldown;
}

/// Circuit breaker to prevent hammering failing services
class CircuitBreaker {
  final String name;
  final int failureThreshold;
  final Duration resetTimeout;
  
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  bool _isOpen = false;
  
  CircuitBreaker({
    required this.name,
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(minutes: 2),
  });
  
  bool get isClosed => !_isOpen;
  bool get isOpen => _isOpen;
  bool get isHalfOpen => _isOpen && _canAttemptReset;
  
  bool get _canAttemptReset {
    if (_lastFailureTime == null) return true;
    return DateTime.now().difference(_lastFailureTime!) > resetTimeout;
  }
  
  void recordSuccess() {
    _failureCount = 0;
    _isOpen = false;
    _lastFailureTime = null;
  }
  
  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_failureCount >= failureThreshold) {
      _isOpen = true;
      print('Circuit breaker [$name] OPENED after $_failureCount failures');
    }
  }
  
  bool canExecute() {
    if (isClosed) return true;
    if (isHalfOpen) {
      print('Circuit breaker [$name] HALF-OPEN: attempting reset');
      return true;
    }
    return false;
  }
}

/// Enum to track which source a book came from
enum BookSource { annasArchive, libgen }

/// Unified book model that works with both sources
class UnifiedBook {
  final String? title;
  final String? author;
  final String? md5;
  final String? coverUrl;
  final String? fileSize;
  final String? extension;
  final String? year;
  final String? publisher;
  final String? language;
  final BookSource source;
  final String? downloadUrl;
  final Book? originalAnnaBook;
  final DateTime? fetchedAt;

  UnifiedBook({
    this.title,
    this.author,
    this.md5,
    this.coverUrl,
    this.fileSize,
    this.extension,
    this.year,
    this.publisher,
    this.language,
    required this.source,
    this.downloadUrl,
    this.originalAnnaBook,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  /// Create from Anna's Archive Book
  factory UnifiedBook.fromAnnaBook(Book book) {
    return UnifiedBook(
      title: book.title,
      author: book.author,
      md5: book.md5,
      coverUrl: book.imgUrl,
      fileSize: book.size,
      extension: book.format.extension,
      year: book.year,
      source: BookSource.annasArchive,
      originalAnnaBook: book,
    );
  }

  /// Create from LibGen search result (Map)
  factory UnifiedBook.fromLibgenResult(Map<String, dynamic> result) {
    return UnifiedBook(
      title: result['title']?.toString(),
      author: result['author']?.toString(),
      md5: result['md5']?.toString(),
      coverUrl: result['poster']?.toString(),
      fileSize: result['size']?.toString(),
      extension: result['extension']?.toString(),
      year: result['year']?.toString(),
      publisher: result['publisher']?.toString(),
      language: result['language']?.toString(),
      source: BookSource.libgen,
      downloadUrl: result['download_links']?.toString(),
    );
  }

  /// Get display name for the source
  String get sourceDisplayName {
    switch (source) {
      case BookSource.annasArchive:
        return "Anna's Archive";
      case BookSource.libgen:
        return "LibGen";
    }
  }
  
  /// Check if book data might be stale (older than 1 hour)
  bool get isStale {
    return DateTime.now().difference(fetchedAt!).inHours > 1;
  }
}

class StoreRepository {
  late final AnnaApi _annaApi;
  late final LibgenScraper _libgenScraper;
  late final Dio _dio;
  
  // Circuit breakers for fault tolerance
  late final CircuitBreaker _annaCircuitBreaker;
  late final CircuitBreaker _libgenCircuitBreaker;
  
  // Mirror health tracking
  final Map<String, MirrorHealth> _mirrorHealth = {};
  
  // Retry configuration
  static const int maxRetries = 3;
  static const Duration baseRetryDelay = Duration(seconds: 1);
  static const Duration maxRetryDelay = Duration(seconds: 10);
  
  // LibGen mirror domains with priority ordering
  static const List<String> _libgenMirrors = [
    'https://libgen.is',
    'https://libgen.rs',
    'https://libgen.st',
    'https://libgen.li',
  ];

  StoreRepository() {
    _initialize();
  }
  
  void _initialize() {
    _annaApi = AnnaApi();
    _libgenScraper = LibgenScraper();
    
    // Initialize circuit breakers
    _annaCircuitBreaker = CircuitBreaker(
      name: 'Anna\'s Archive',
      failureThreshold: 3,
      resetTimeout: const Duration(minutes: 5),
    );
    
    _libgenCircuitBreaker = CircuitBreaker(
      name: 'LibGen',
      failureThreshold: 5,
      resetTimeout: const Duration(minutes: 3),
    );
    
    // Initialize mirror health tracking
    for (final mirror in _libgenMirrors) {
      _mirrorHealth[mirror] = MirrorHealth(mirror);
    }
    
    // Configure Dio with interceptors
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept-Encoding': 'gzip, deflate, br',
          'DNT': '1',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
        },
      ),
    );
    
    // Add logging interceptor in debug mode
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          print('[Dio] ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          print('[Dio] ${response.statusCode} ${response.requestOptions.uri}');
          return handler.next(response);
        },
        onError: (error, handler) {
          print('[Dio] ERROR ${error.response?.statusCode} ${error.requestOptions.uri}: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }
  
  /// Retry logic with exponential backoff and jitter
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    required String operationName,
    int maxAttempts = maxRetries,
  }) async {
    int attempts = 0;
    
    while (attempts < maxAttempts) {
      attempts++;
      
      try {
        return await operation();
      } catch (e) {
        if (attempts >= maxAttempts) {
          throw StoreRepositoryException(
            '$operationName failed after $maxAttempts attempts',
            originalError: e is Exception ? e : null,
          );
        }
        
        // Calculate delay with exponential backoff and jitter
        final delayMs = min(
          baseRetryDelay.inMilliseconds * pow(2, attempts - 1).toInt(),
          maxRetryDelay.inMilliseconds,
        );
        final jitter = Random().nextInt(delayMs ~/ 4);
        final delay = Duration(milliseconds: delayMs + jitter);
        
        print('$operationName attempt $attempts failed, retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
      }
    }
    
    throw StoreRepositoryException('$operationName failed unexpectedly');
  }

  /// Search books from both Anna's Archive and LibGen with improved error handling
  Future<List<UnifiedBook>> searchBooks({
    required String query,
    List<Format> formats = const [Format.pdf, Format.epub],
    int page = 1,
    Language? language,
    SortOption? sort,
    bool searchAnnasArchive = true,
    bool searchLibgen = true,
    Duration? timeout,
  }) async {
    final List<UnifiedBook> allBooks = [];
    final List<String> errors = [];
    
    final searchTimeout = timeout ?? const Duration(seconds: 15);

    // Search Anna's Archive with circuit breaker
    if (searchAnnasArchive && _annaCircuitBreaker.canExecute()) {
      try {
        final annaBooks = await _searchAnnasArchiveWithRetry(
          query: query,
          formats: formats,
          page: page,
          language: language,
          sort: sort,
          timeout: searchTimeout,
        );
        
        allBooks.addAll(annaBooks);
        _annaCircuitBreaker.recordSuccess();
      } on SearchTimeoutException catch (e) {
        errors.add('Anna\'s Archive: Timeout');
        print('Anna\'s Archive search timeout: $e');
      } catch (e) {
        errors.add('Anna\'s Archive: ${e.toString()}');
        print('Error searching Anna\'s Archive: $e');
        _annaCircuitBreaker.recordFailure();
      }
    } else if (searchAnnasArchive && !_annaCircuitBreaker.canExecute()) {
      print('Skipping Anna\'s Archive search - circuit breaker is OPEN');
      errors.add('Anna\'s Archive: Temporarily unavailable');
    }

    // Search LibGen with circuit breaker (only on first page to avoid duplicates)
    if (searchLibgen && page == 1 && _libgenCircuitBreaker.canExecute()) {
      try {
        final libgenBooks = await _searchLibgenWithMirrorsAndRetry(
          query: query,
          formats: formats,
          timeout: searchTimeout,
        );
        
        allBooks.addAll(libgenBooks);
        _libgenCircuitBreaker.recordSuccess();
      } on MirrorUnavailableException catch (e) {
        errors.add('LibGen: All mirrors unavailable');
        print('LibGen mirrors unavailable: $e');
        _libgenCircuitBreaker.recordFailure();
      } on SearchTimeoutException catch (e) {
        errors.add('LibGen: Timeout');
        print('LibGen search timeout: $e');
      } catch (e) {
        errors.add('LibGen: ${e.toString()}');
        print('Error searching LibGen: $e');
        _libgenCircuitBreaker.recordFailure();
      }
    } else if (searchLibgen && page == 1 && !_libgenCircuitBreaker.canExecute()) {
      print('Skipping LibGen search - circuit breaker is OPEN');
      errors.add('LibGen: Temporarily unavailable');
    }

    // Log search results summary
    print('Search completed: ${allBooks.length} total results (Anna\'s Archive + LibGen)');
    if (errors.isNotEmpty) {
      print('Errors encountered: ${errors.join(', ')}');
    }

    // Deduplicate by MD5 with priority to Anna's Archive
    return _deduplicateBooks(allBooks);
  }
  
  /// Search Anna's Archive with retry logic
  Future<List<UnifiedBook>> _searchAnnasArchiveWithRetry({
    required String query,
    required List<Format> formats,
    required int page,
    Language? language,
    SortOption? sort,
    required Duration timeout,
  }) async {
    return _retryWithBackoff(
      operationName: 'Anna\'s Archive search',
      () async {
        final searchRequest = SearchRequest(
          query: query,
          formats: formats,
          page: page,
          language: language ?? Language.english,
          sort: sort ?? SortOption.mostRelevant,
        );

        final response = await _annaApi.find(searchRequest).timeout(
          timeout,
          onTimeout: () {
            throw SearchTimeoutException('Anna\'s Archive search timeout');
          },
        );
        
        return response.books.map((b) => UnifiedBook.fromAnnaBook(b)).toList();
      },
    );
  }

  /// Deduplicate books by MD5, preferring Anna's Archive
  List<UnifiedBook> _deduplicateBooks(List<UnifiedBook> books) {
    final Map<String, UnifiedBook> md5Map = {};
    
    for (final book in books) {
      final md5 = book.md5?.toLowerCase() ?? '';
      
      if (md5.isEmpty) {
        // Keep books without MD5
        continue;
      }
      
      final existing = md5Map[md5];
      if (existing == null) {
        md5Map[md5] = book;
      } else if (book.source == BookSource.annasArchive && 
                 existing.source == BookSource.libgen) {
        // Prefer Anna's Archive over LibGen
        md5Map[md5] = book;
      }
    }
    
    // Add books without MD5
    final booksWithoutMd5 = books.where((b) => (b.md5?.isEmpty ?? true)).toList();
    
    final deduplicated = [...md5Map.values, ...booksWithoutMd5];
    print('Deduplication: ${books.length} -> ${deduplicated.length} books');
    
    return deduplicated;
  }

  /// Get download links for a book with fallback
  Future<List<String>> getDownloadLinks(UnifiedBook book) async {
    try {
      if (book.source == BookSource.annasArchive) {
        return await _getAnnaDownloadLinksWithRetry(book.md5);
      } else {
        return await _getLibgenDownloadLinksWithRetry(book.downloadUrl, book.md5);
      }
    } catch (e) {
      print('Error getting download links: $e');
      return [];
    }
  }

  /// Get download links from Anna's Archive with retry
  Future<List<String>> _getAnnaDownloadLinksWithRetry(String? md5) async {
    if (md5 == null || md5.isEmpty) {
      throw StoreRepositoryException('MD5 is null or empty', source: 'Anna\'s Archive');
    }
    
    return _retryWithBackoff(
      operationName: 'Anna\'s Archive download links',
      () async {
        final links = await _annaApi.getDownloadLinks(md5);
        
        if (links.isEmpty) {
          throw StoreRepositoryException('No download links returned', source: 'Anna\'s Archive');
        }
        
        // Validate URLs
        final validLinks = links.where((link) => 
          link.startsWith('http') && 
          !link.contains('example.com') &&
          !link.contains('placeholder')
        ).toList();
        
        if (validLinks.isEmpty) {
          throw StoreRepositoryException('No valid download links found', source: 'Anna\'s Archive');
        }
        
        return validLinks;
      },
    );
  }

  /// Get download links from LibGen with retry and multiple extraction methods
  Future<List<String>> _getLibgenDownloadLinksWithRetry(String? downloadUrl, String? md5) async {
    if ((downloadUrl == null || downloadUrl.isEmpty) && (md5 == null || md5.isEmpty)) {
      throw StoreRepositoryException('Neither download URL nor MD5 provided', source: 'LibGen');
    }
    
    return _retryWithBackoff(
      operationName: 'LibGen download links',
      () async {
        // Try multiple methods to get download links
        final allLinks = <String>[];
        
        // Method 1: Direct URL if it looks like a download link
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          if (_isDirectDownloadUrl(downloadUrl)) {
            return [downloadUrl];
          }
        }
        
        // Method 2: Extract from LibGen page
        if (downloadUrl != null && downloadUrl.contains('libgen.')) {
          try {
            final pageLinks = await _extractLinksFromLibgenPage(downloadUrl);
            allLinks.addAll(pageLinks);
          } catch (e) {
            print('Failed to extract from LibGen page: $e');
          }
        }
        
        // Method 3: Try using scraper package
        if (allLinks.isEmpty && downloadUrl != null) {
          try {
            final scraperLinks = await _extractLinksUsingScraper(downloadUrl);
            allLinks.addAll(scraperLinks);
          } catch (e) {
            print('Scraper failed: $e');
          }
        }
        
        // Method 4: Construct library.lol URL from MD5
        if (allLinks.isEmpty && md5 != null && md5.isNotEmpty) {
          final constructedUrl = 'https://library.lol/main/$md5';
          allLinks.add(constructedUrl);
        }
        
        // Method 5: Return original URL as last resort
        if (allLinks.isEmpty && downloadUrl != null) {
          allLinks.add(downloadUrl);
        }
        
        if (allLinks.isEmpty) {
          throw StoreRepositoryException('Could not find any download links', source: 'LibGen');
        }
        
        return allLinks.toSet().toList(); // Remove duplicates
      },
    );
  }
  
  bool _isDirectDownloadUrl(String url) {
    return url.contains('library.lol') || 
           url.contains('libgen.lc') ||
           url.contains('libgen.rocks') ||
           url.contains('download2.org') ||
           url.contains('b-ok.cc');
  }
  
  Future<List<String>> _extractLinksFromLibgenPage(String url) async {
    final response = await _dio.get(
      url,
      options: Options(
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    
    if (response.statusCode != 200 || response.data == null) {
      throw StoreRepositoryException('Failed to fetch page: ${response.statusCode}');
    }
    
    final document = html_parser.parse(response.data.toString());
    final links = <String>[];
    
    // Multiple selectors to find download links
    final selectors = [
      'a[href*="library.lol"]',
      'a[href*="libgen.lc"]',
      'a[href*="download"]',
      'a[href*="get.php"]',
      'a[href*="ads.php"]',
      'a', // Fallback: check all links
    ];
    
    for (final selector in selectors) {
      for (final link in document.querySelectorAll(selector)) {
        final href = link.attributes['href'] ?? '';
        final text = link.text.toLowerCase();
        
        if (href.isNotEmpty && (
            href.contains('library.lol') ||
            href.contains('libgen.lc') ||
            href.contains('libgen.rocks') ||
            href.contains('download2.org') ||
            text.contains('get') ||
            text.contains('download') ||
            href.contains('download.php') ||
            href.contains('get.php')
        )) {
          if (href.startsWith('http')) {
            links.add(href);
          }
        }
      }
      
      // If we found links with this selector, no need to check others
      if (links.isNotEmpty) break;
    }
    
    return links;
  }
  
  Future<List<String>> _extractLinksUsingScraper(String downloadUrl) async {
    final dynamic linkData = await _libgenScraper.getDownloadLinks(downloadUrl).timeout(
      const Duration(seconds: 10),
    );
    
    final links = <String>[];
    
    if (linkData is String && linkData.isNotEmpty) {
      links.add(linkData);
    } else if (linkData is Map && linkData.isNotEmpty) {
      links.addAll(linkData.values.map((v) => v.toString()).where((s) => s.isNotEmpty));
    } else if (linkData is List && linkData.isNotEmpty) {
      links.addAll(linkData.map((e) => e.toString()).where((s) => s.isNotEmpty));
    }
    
    return links;
  }

  /// Download a book with resume capability and retry logic
  Future<String?> downloadBook({
    required String url,
    required String fileName,
    required Function(double progress) onProgress,
    Duration? timeout,
    CancelToken? cancelToken,
  }) async {
    final downloadTimeout = timeout ?? const Duration(minutes: 5);
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final booksDir = Directory('${appDir.path}/books');
      if (!await booksDir.exists()) {
        await booksDir.create(recursive: true);
      }

      final filePath = '${booksDir.path}/$fileName';
      final file = File(filePath);
      
      // Check if partial download exists and resume
      int startByte = 0;
      if (await file.exists()) {
        startByte = await file.length();
        print('Resuming download from byte $startByte');
      }

      return await _retryWithBackoff(
        operationName: 'Book download',
        maxAttempts: 2,
        () async {
          final response = await _dio.download(
            url,
            filePath,
            cancelToken: cancelToken,
            options: Options(
              headers: startByte > 0 ? {
                'Range': 'bytes=$startByte-',
              } : null,
              receiveTimeout: downloadTimeout,
            ),
            onReceiveProgress: (received, total) {
              if (total != -1) {
                final progress = (startByte + received) / (startByte + total);
                onProgress(progress.clamp(0.0, 1.0));
              }
            },
            deleteOnError: startByte == 0, // Only delete if not resuming
          );
          
          if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
            return filePath;
          } else {
            throw DownloadFailedException('HTTP ${response.statusCode}', source: 'Download');
          }
        },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        print('Download cancelled by user');
        return null;
      }
      throw DownloadFailedException('Download failed: ${e.message}', source: 'Download', originalError: e);
    } catch (e) {
      throw DownloadFailedException('Download failed: $e', source: 'Download', originalError: e is Exception ? e : null);
    }
  }

  /// Search LibGen using mirrors with health tracking and retry
  Future<List<UnifiedBook>> _searchLibgenWithMirrorsAndRetry({
    required String query,
    required List<Format> formats,
    required Duration timeout,
  }) async {
    return _retryWithBackoff(
      operationName: 'LibGen mirror search',
      maxAttempts: 2,
      () async {
        final results = await _searchLibgenWithMirrors(query, formats, timeout);
        if (results.isEmpty) {
          throw MirrorUnavailableException('All LibGen mirrors returned no results');
        }
        return results;
      },
    );
  }

  /// Search LibGen using available mirrors with health-based prioritization
  Future<List<UnifiedBook>> _searchLibgenWithMirrors(
    String query,
    List<Format> formats,
    Duration timeout,
  ) async {
    final encodedQuery = Uri.encodeQueryComponent(query);
    
    // Sort mirrors by health (healthy first, then by response time)
    final sortedMirrors = _libgenMirrors.toList()
      ..sort((a, b) {
        final healthA = _mirrorHealth[a]!;
        final healthB = _mirrorHealth[b]!;
        
        if (healthA.isHealthy && !healthB.isHealthy) return -1;
        if (!healthA.isHealthy && healthB.isHealthy) return 1;
        
        return healthA.responseTimeMs.compareTo(healthB.responseTimeMs);
      });
    
    final allResults = <UnifiedBook>[];
    final attemptedMirrors = <String>[];
    
    for (final mirror in sortedMirrors) {
      final health = _mirrorHealth[mirror]!;
      
      // Skip mirrors in cooldown
      if (!health.shouldTry) {
        print('Skipping mirror $mirror - in cooldown (${health.cooldownPeriod.inMinutes}m)');
        continue;
      }
      
      attemptedMirrors.add(mirror);
      
      try {
        print('Trying LibGen mirror: $mirror (healthy: ${health.isHealthy})');
        final stopwatch = Stopwatch()..start();
        
        final results = await _searchSingleMirror(mirror, encodedQuery, formats, timeout);
        
        stopwatch.stop();
        health.recordSuccess(stopwatch.elapsedMilliseconds);
        
        if (results.isNotEmpty) {
          print('Found ${results.length} results from $mirror in ${stopwatch.elapsedMilliseconds}ms');
          allResults.addAll(results);
          
          // If we got good results from a healthy mirror, we can stop
          if (health.isHealthy && results.length >= 10) {
            break;
          }
        }
      } catch (e) {
        health.recordFailure();
        print('Mirror $mirror failed: $e (consecutive failures: ${health.consecutiveFailures})');
      }
    }
    
    if (allResults.isEmpty && attemptedMirrors.isNotEmpty) {
      throw MirrorUnavailableException(
        'All ${attemptedMirrors.length} attempted mirrors failed or returned no results'
      );
    }
    
    return allResults;
  }
  
  Future<List<UnifiedBook>> _searchSingleMirror(
    String mirror,
    String encodedQuery,
    List<Format> formats,
    Duration timeout,
  ) async {
    final searchUrls = [
      '$mirror/search.php?req=$encodedQuery&res=100',
      '$mirror/search.php?req=$encodedQuery',
    ];
    
    for (final searchUrl in searchUrls) {
      try {
        final response = await _dio.get(
          searchUrl,
          options: Options(
            followRedirects: true,
            validateStatus: (status) => status != null && status < 500,
            receiveTimeout: timeout,
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          final results = _parseLibgenSearchResults(response.data.toString(), mirror);
          
          // Filter by format
          final filteredResults = results.where((result) {
            final ext = result['extension']?.toString().toLowerCase() ?? '';
            if (formats.contains(Format.pdf) && ext == 'pdf') return true;
            if (formats.contains(Format.epub) && ext == 'epub') return true;
            return formats.length >= 2;
          }).toList();
          
          return filteredResults.map((r) => UnifiedBook.fromLibgenResult(r)).toList();
        }
      } catch (e) {
        print('Search URL $searchUrl failed: $e');
        continue;
      }
    }
    
    return [];
  }

  /// Parse LibGen HTML search results with improved error handling
  List<Map<String, String>> _parseLibgenSearchResults(String htmlBody, String mirror) {
    try {
      final document = html_parser.parse(htmlBody);
      final List<Map<String, String>> results = [];

      // Find results table with multiple strategies
      html_dom.Element? resultsTable;
      
      // Strategy 1: Look for table with specific class or id
      resultsTable = document.querySelector('table.c') ??
                    document.querySelector('table[rules="rows"]') ??
                    document.querySelector('table.main');
      
      // Strategy 2: Look for table with headers
      if (resultsTable == null) {
        final tables = document.querySelectorAll('table');
        for (var i = 0; i < tables.length && resultsTable == null; i++) {
          final table = tables[i];
          final headerText = table.text.toLowerCase();
          
          if ((headerText.contains('author') || headerText.contains('title')) &&
              table.querySelectorAll('tr').length > 2) {
            resultsTable = table;
          }
        }
      }

      if (resultsTable == null) {
        print('No results table found in HTML from $mirror');
        return results;
      }

      final rows = resultsTable.querySelectorAll('tr');
      
      // Skip header row(s), process data rows
      for (var i = 1; i < rows.length && results.length < 100; i++) {
        try {
          final cells = rows[i].querySelectorAll('td');
          
          if (cells.length < 9) {
            continue;
          }

          final id = cells.isNotEmpty ? cells[0].text.trim() : '';
          final author = cells.length > 1 ? cells[1].text.trim() : '';
          final titleElement = cells.length > 2 ? cells[2] : null;
          final title = titleElement?.text.trim() ?? '';
          final publisher = cells.length > 3 ? cells[3].text.trim() : '';
          final year = cells.length > 4 ? cells[4].text.trim() : '';
          final pages = cells.length > 5 ? cells[5].text.trim() : '';
          final language = cells.length > 6 ? cells[6].text.trim() : '';
          final size = cells.length > 7 ? cells[7].text.trim() : '';
          final extension = cells.length > 8 ? cells[8].text.trim().toLowerCase() : '';
          
          // Extract MD5 from links
          String md5 = '';
          final allLinks = titleElement?.querySelectorAll('a') ?? [];
          for (final link in allLinks) {
            final href = link.attributes['href'] ?? '';
            final md5Match = RegExp(r'md5=([a-fA-F0-9]{32})', caseSensitive: false).firstMatch(href);
            if (md5Match != null) {
              md5 = md5Match.group(1)!.toLowerCase();
              break;
            }
          }
          
          // Extract download links
          String downloadUrl = '';
          for (var j = 9; j < cells.length && downloadUrl.isEmpty; j++) {
            final links = cells[j].querySelectorAll('a');
            for (final link in links) {
              final href = link.attributes['href'] ?? '';
              if (href.isNotEmpty) {
                if (href.startsWith('http')) {
                  downloadUrl = href;
                } else if (href.startsWith('/')) {
                  downloadUrl = '$mirror$href';
                } else if (href.startsWith('?')) {
                  downloadUrl = '$mirror/$href';
                }
                if (downloadUrl.isNotEmpty) break;
              }
            }
          }

          if (title.isNotEmpty && extension.isNotEmpty) {
            results.add({
              'id': id,
              'title': title,
              'author': author.isNotEmpty ? author : 'Unknown',
              'publisher': publisher,
              'year': year,
              'pages': pages,
              'language': language.isNotEmpty ? language : 'English',
              'size': size,
              'extension': extension,
              'md5': md5,
              'download_links': downloadUrl,
              'poster': '',
            });
          }
        } catch (e) {
          print('Error parsing row $i: $e');
          continue;
        }
      }

      print('Successfully parsed ${results.length} results from $mirror');
      return results;
    } catch (e, stackTrace) {
      print('Error parsing LibGen HTML: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }
  
  /// Get current mirror health status for debugging
  Map<String, Map<String, dynamic>> getMirrorHealthStatus() {
    return Map.fromEntries(
      _mirrorHealth.entries.map((e) => MapEntry(
        e.key,
        {
          'isHealthy': e.value.isHealthy,
          'consecutiveFailures': e.value.consecutiveFailures,
          'responseTimeMs': e.value.responseTimeMs,
          'isInCooldown': e.value.isInCooldown,
          'cooldownMinutes': e.value.cooldownPeriod.inMinutes,
          'lastChecked': e.value.lastChecked?.toIso8601String(),
        },
      )),
    );
  }
  
  /// Reset mirror health (useful for testing or manual recovery)
  void resetMirrorHealth() {
    for (final health in _mirrorHealth.values) {
      health.isHealthy = true;
      health.consecutiveFailures = 0;
      health.lastFailure = null;
    }
    print('Mirror health reset');
  }
}

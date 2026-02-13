class AppConstants {
  // App info
  static const String appName = 'E-Reader';
  static const String appVersion = '1.0.0';
  
  // Hive boxes
  static const String booksBox = 'books';
  
  // File extensions
  static const List<String> supportedFormats = ['pdf', 'epub'];
  
  // Grid settings for tablet
  static const int libraryGridCrossAxisCount = 4;
  static const double libraryGridChildAspectRatio = 0.65;
  static const double gridSpacing = 16.0;
  
  // Reading progress
  static const int autoSaveIntervalSeconds = 5;
  
  // Store settings
  static const int searchDebounceMs = 500;
  static const int itemsPerPage = 20;
}

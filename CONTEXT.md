# E-Reader Project Context

## Project Overview

**E-Reader** is a modern e-reader application built with Flutter for Android tablets. It supports PDF and EPUB formats with local library management, online book store integration via Anna's Archive, and comprehensive reading progress tracking.

### Key Information
- **Version**: 1.1.0+2
- **Platform**: Android (API 26+), optimized for tablets
- **Framework**: Flutter 3.0+
- **Language**: Dart
- **Total Code**: ~4,304 lines of Dart code
- **Architecture**: BLoC pattern with clean architecture principles

---

## Core Features

### 1. Library Management
- Import and organize PDF and EPUB books from local storage
- Grid layout optimized for tablet screens
- Reading progress tracking with visual indicators
- Book metadata display (title, author, cover, progress)
- Auto-save reading positions

### 2. Book Store Integration
- Search and browse books via Anna's Archive API and LibGen
- Multiple mirror support for LibGen with automatic fallback
- Direct book downloads from external sources
- Cover image caching
- Metadata extraction and storage
- Unified book model for both sources
- Smart deduplication by MD5 hash

### 3. PDF Reader
- Vertical scroll reading experience
- Page-by-page navigation
- Progress tracking by page number
- Powered by `pdfrx` package

### 4. EPUB Reader
- Chapter-based navigation
- CFI (Canonical Fragment Identifier) position tracking
- Precise reading progress across sessions
- Powered by `flutter_epub_viewer` package

### 5. UI/UX Features
- Material Design 3 theming
- Automatic light/dark mode support
- Google Fonts integration
- Responsive grid layouts
- Cached network images for performance
- Tablet-optimized interface

### 6. Dictionary & Definitions
- Built-in dictionary lookup for selected text
- Powered by Free Dictionary API (api.dictionaryapi.dev)
- Offline-capable definition caching (future scope)
- Context menu integration in EPUB reader
- Glassmorphic definition dialog


---

## Technology Stack

### Core Framework
- **Flutter SDK**: 3.0+
- **Dart SDK**: 3.0+

### State Management
- **flutter_bloc** (^8.1.3): BLoC pattern implementation
- **equatable** (^2.0.5): Value equality for state objects

### Local Storage
- **hive** (^2.2.3): NoSQL local database
- **hive_flutter** (^1.1.0): Flutter integration
- **hive_generator** (^2.0.1): Code generation for models
- **path_provider** (^2.1.2): File system paths

### Book Reading & Rendering
- **pdfrx** (^2.2.24): PDF rendering engine
- **flutter_epub_viewer** (^1.0.5): EPUB reading capability

### Networking & Downloads
- **dio** (^5.4.0): HTTP client for downloads
- **cached_network_image** (^3.3.1): Image caching

### Book Store APIs
- **annas_archive_api** (^1.0.0): Anna's Archive integration
- **libgen_scraper** (^1.0.5): LibGen scraping
- **html** (^0.15.0): HTML parsing

### UI Components
- **google_fonts** (^6.1.0): Typography
- **cupertino_icons** (^1.0.6): iOS-style icons

### Navigation
- **go_router** (^13.0.0): Declarative routing

### Utilities
- **file_picker** (^10.3.10): File import functionality
- **permission_handler** (^12.0.1): Android permissions
- **uuid** (^4.3.0): Unique ID generation
- **intl** (^0.19.0): Internationalization

### Development Tools
- **flutter_lints** (^3.0.0): Code quality
- **build_runner** (^2.4.8): Code generation

---

## Project Structure

```
Ereader/
├── lib/                              # Main source code
│   ├── main.dart                     # App entry point & initialization
│   ├── core/                         # Core utilities
│   │   ├── constants/                # App-wide constants
│   │   │   └── app_constants.dart    # Configuration values
│   │   └── theme/                    # Theming
│   │       └── app_theme.dart        # Material 3 light/dark themes
│   ├── data/                         # Data layer
│   │   ├── models/                   # Data models
│   │   │   ├── book_model.dart       # Book entity with Hive annotations
│   │   │   ├── book_model.g.dart     # Generated Hive adapter
│   │   │   └── dictionary_entry.dart # Dictionary data model
│   │   └── repositories/             # Data access
│   │       ├── book_repository.dart  # Local book CRUD operations
│   │       ├── store_repository.dart # Book store API integration
│   │       └── dictionary_repository.dart # Dictionary API integration
│   └── presentation/                 # UI layer
│       ├── navigation/               # Routing & navigation
│       │   ├── app_router.dart       # GoRouter configuration
│       │   └── home_screen.dart      # Main navigation shell
│       ├── library/                  # Library feature
│       │   ├── library_screen.dart   # Library UI
│       │   ├── bloc/                 # Library state management
│       │   │   ├── library_bloc.dart
│       │   │   ├── library_event.dart
│       │   │   └── library_state.dart
│       │   └── widgets/              # Reusable library widgets
│       │       ├── book_card.dart    # Book display card
│       │       └── library_grid.dart # Grid layout
│       ├── store/                    # Book store feature
│       │   ├── store_screen.dart     # Store UI
│       │   ├── bloc/                 # Store state management
│       │   │   ├── store_bloc.dart
│       │   │   ├── store_event.dart
│       │   │   └── store_state.dart
│       │   └── widgets/
│       │       └── store_book_card.dart
│       └── reader/                   # Reading feature
│           ├── pdf_reader_screen.dart   # PDF reading UI
│           ├── epub_reader_screen.dart  # EPUB reading UI
│           ├── widgets/
│           │   └── dictionary_dialog.dart # Definition popup
│           └── bloc/                 # Reader state management
│               ├── reader_bloc.dart
│               ├── reader_event.dart
│               └── reader_state.dart
├── android/                          # Android native code
│   └── app/src/main/
│       ├── AndroidManifest.xml       # App permissions & configuration
│       ├── kotlin/                   # Kotlin native code
│       ├── java/                     # Java native code
│       └── res/                      # Android resources
├── test/                             # Unit & widget tests
├── build/                            # Build artifacts
├── development/                      # Development tools (Flutter SDK)
├── .dart_tool/                       # Dart tooling cache
├── pubspec.yaml                      # Dependencies & metadata
├── pubspec.lock                      # Locked dependency versions
├── analysis_options.yaml             # Linter configuration
├── devtools_options.yaml             # DevTools settings
└── README.md                         # User documentation

```

---

## Architecture

### Design Pattern: BLoC (Business Logic Component)

The app follows **BLoC pattern** with **clean architecture** principles:

1. **Presentation Layer** (`presentation/`):
   - UI screens and widgets
   - BLoC for state management
   - Events trigger business logic
   - States represent UI states

2. **Data Layer** (`data/`):
   - Models with Hive persistence
   - Repositories for data access
   - Separation of local and remote data sources

3. **Core Layer** (`core/`):
   - Shared constants and configurations
   - Theming and styling
   - Utilities

### Key Components

#### 1. BookModel (Data Model)
- Hive-based persistent storage
- Fields: title, author, cover, local path, format, reading progress, CFI position
- Supports both PDF and EPUB formats
- Tracks reading percentage and last read time

#### 2. Repositories
- **BookRepository**: CRUD operations for local library
  - Add/remove books
  - Update reading progress
  - Fetch all books
- **StoreRepository**: Integration with Anna's Archive API
  - Search books
  - Download books
  - Parse metadata
- **DictionaryRepository**: Fetches word definitions
  - Integrates with Free Dictionary API
  - Parsing of phonetics, meanings, and examples

#### 3. BLoC State Management
Each feature has dedicated BLoC:
- **LibraryBloc**: Manages library state, book imports, deletions
- **StoreBloc**: Handles book search and downloads
- **ReaderBloc**: Tracks reading progress and position

---

## Data Flow

### Adding a Book to Library
1. User selects file via `file_picker`
2. `LibraryBloc` receives `ImportBook` event
3. `BookRepository` creates `BookModel` with metadata
4. Model saved to Hive database
5. UI updates with new book in grid

### Reading a Book
1. User taps book card in library
2. Navigation to appropriate reader (PDF/EPUB)
3. `ReaderBloc` loads last read position
4. Reader displays content from saved position
5. Progress auto-saved periodically
6. CFI (EPUB) or page number (PDF) stored in Hive

### Downloading from Store
1. User searches via `StoreScreen`
2. `StoreBloc` calls `StoreRepository.searchBooks()`
3. API results displayed in grid
4. User taps "Get" button
5. `dio` downloads file to local storage
6. Book added to library automatically

---

## Database Schema (Hive)

### Books Box (`books`)
Stores `BookModel` objects with fields:
- `id`: Unique identifier (UUID)
- `title`: Book title
- `author`: Author name
- `coverUrl`: Remote cover image URL
- `localCoverPath`: Local cover cache path
- `localPath`: Path to book file
- `format`: "pdf" or "epub"
- `totalPages`: Page count (PDF only)
- `lastReadPage`: Last read page (PDF)
- `lastReadProgress`: Progress 0.0-1.0
- `lastReadCfi`: EPUB position
- `lastReadTime`: Timestamp of last read
- `addedTime`: When book was added
- `md5`: Hash for Anna's Archive
- `fileSize`: File size in bytes

### Settings Box (`settings`)
Stores app configuration:
- Reader theme preferences
- UI settings

---

## Android Configuration

### Permissions (AndroidManifest.xml)
- `INTERNET`: Download books and load covers
- `READ_EXTERNAL_STORAGE`: Import books
- `WRITE_EXTERNAL_STORAGE`: Save downloads
- `READ_MEDIA_IMAGES`: Android 13+ image access

### Intent Filters
App can open PDF and EPUB files directly from file managers:
- `application/pdf`
- `application/epub+zip`

### Features
- Hardware acceleration enabled
- Cleartext traffic allowed (for book downloads)
- File provider for sharing files

---

## Navigation Structure (GoRouter)

```
/                          # Home shell with bottom navigation
├── /library               # Library screen (default)
└── /store                 # Book store screen

/reader/:bookId            # Reader screen (PDF or EPUB based on format)
```

---

## Key Workflows

### 1. First Launch
1. `main.dart` initializes Flutter
2. Hive database initialized
3. `BookModel` adapter registered
4. Boxes opened: `books`, `settings`
5. `LibraryBloc` loads existing books
6. Home screen displays library

### 2. Import Book
1. User taps + button
2. `file_picker` opens system picker
3. User selects PDF/EPUB file
4. File copied to app directory
5. Metadata extracted (title, author)
6. `BookModel` created and saved
7. Library UI updates

### 3. Read Book
1. User taps book card
2. Router navigates to `/reader/:bookId`
3. Appropriate reader screen loads (PDF/EPUB)
4. Last position restored from database
5. User reads, position tracked
6. On exit, progress saved to Hive

### 4. Search & Download
1. User searches in Store tab
2. API query to Anna's Archive
3. Results displayed with covers
4. User taps "Get" on desired book
5. Download starts with progress indicator
6. File saved to app storage
7. Book added to library
8. User navigated to library tab

---

## Development Commands

### Setup
```bash
flutter pub get                 # Install dependencies
flutter pub run build_runner build  # Generate code (Hive adapters)
```

### Run & Test
```bash
flutter run                     # Run in debug mode
flutter run --release          # Run in release mode
flutter test                   # Run unit tests
flutter analyze                # Static analysis
```

### Build
```bash
flutter build apk              # Build APK
flutter build appbundle        # Build App Bundle for Play Store
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

---

## Known Configurations

### HTTP Overrides
`MyHttpOverrides` class in `main.dart` disables certificate validation to allow downloads from various book sources.

### Theme Mode
Automatically follows system theme (light/dark mode).

---

## File Locations

### Books Storage
- Books saved to app's document directory
- Path obtained via `path_provider`
- Format: `/data/data/com.example.ereader/app_flutter/books/`

### Cover Cache
- Cached network images stored automatically by `cached_network_image`

---

## Dependencies Summary

| Category | Key Packages |
|----------|--------------|
| Framework | flutter, dart:core |
| State Management | flutter_bloc, equatable |
| Database | hive, hive_flutter |
| Book APIs | annas_archive_api, libgen_scraper |
| Readers | pdfrx, flutter_epub_viewer |
| Networking | dio, cached_network_image |
| Navigation | go_router |
| File System | file_picker, path_provider, permission_handler |
| UI | google_fonts, cupertino_icons |
| Utils | uuid, intl, html |

---

## Future Enhancement Opportunities

Based on the current architecture, potential improvements could include:

1. **Cloud Sync**: Sync library and progress across devices
2. **Collections**: Organize books into custom collections
3. **Reading Stats**: Track reading time and habits
4. **Annotations**: Highlight and note-taking features
5. **Text-to-Speech**: Audio reading capability
6. **Custom Fonts**: User-selectable reader fonts
7. **Bookmarks**: Save specific locations
8. **Search in Book**: Full-text search within books
9. **Library Sorting**: Multiple sort options (date, title, author, progress)
10. **Backup/Restore**: Export library database

---

## Code Quality & Standards

- **Linting**: `flutter_lints` enforces Dart style guidelines
- **Type Safety**: Strong typing throughout codebase
- **Null Safety**: Full null-safety enabled
- **Code Generation**: Used for Hive adapters
- **Architecture**: Clear separation of concerns (presentation, data, core)

---

## Development Notes

### HTTP Security
Certificate validation is disabled via `MyHttpOverrides` to allow connections to book download sources. This should be reviewed for production security.

### Permissions
Storage permissions required for Android. Consider scoped storage for Android 11+.

### Performance
- Images cached via `cached_network_image`
- PDF rendering handled by native `pdfrx` library
- EPUB rendered using webview-based `flutter_epub_viewer`

---

## Contact & Documentation

- **README**: See `README.md` for user-facing documentation
- **Build Output**: `build/` directory (gitignored)
- **Screenshot**: `screenshot_broken_reader.png` included in project root

---

*Last Updated: February 13, 2026*
*Generated from project analysis*

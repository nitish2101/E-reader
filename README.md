# E-Reader - Flutter App for Android Tablets

A modern e-reader application for Android tablets supporting PDF and EPUB formats with a local library, online book store via Anna's Archive, and reading progress tracking.

## Features

- 📚 **Library Management**: Import and organize your PDF and EPUB books
- 🔍 **Book Store**: Search and download books from Anna's Archive
- 📖 **PDF Reader**: Vertical scroll reading with page navigation
- 📱 **EPUB Reader**: Chapter navigation with CFI-based progress tracking
- 💾 **Reading Progress**: Auto-save and resume where you left off
- 🌙 **Dark Mode**: Automatic light/dark theme support
- 📱 **Tablet Optimized**: Responsive grid layouts for larger screens

## Getting Started

### Prerequisites

- Flutter SDK (3.0 or higher)
- Android Studio or VS Code with Flutter extension
- Android device or emulator (API 26+)

### Installation

1. **Install Flutter** (if not already installed):
   ```bash
   # Follow instructions at https://flutter.dev/docs/get-started/install
   ```

2. **Navigate to project directory**:
   ```bash
   cd /path/to/Ereader
   ```

3. **Get dependencies**:
   ```bash
   flutter pub get
   ```

4. **Run the app**:
   ```bash
   flutter run
   ```

### Building for Release

```bash
# Build APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── core/
│   ├── constants/              # App constants
│   └── theme/                  # Material 3 theming
├── data/
│   ├── models/                 # Data models (BookModel)
│   └── repositories/           # Data repositories
├── presentation/
│   ├── library/               # Library screen & BLoC
│   ├── store/                 # Store screen & BLoC
│   ├── reader/                # PDF & EPUB readers
│   └── navigation/            # App routing
```

## Dependencies

| Package | Purpose |
|---------|---------|
| flutter_bloc | State management |
| hive/hive_flutter | Local database |
| annas_archive_api | Book store API |
| pdfrx | PDF rendering |
| flutter_epub_viewer | EPUB rendering |
| go_router | Navigation |
| dio | HTTP downloads |
| file_picker | File import |

## Usage

### Importing Books

1. Tap the **Import** button (+ icon) on the Library screen
2. Select a PDF or EPUB file from your device
3. The book will appear in your library

### Downloading from Store

1. Navigate to the **Store** tab
2. Search for a book title or author
3. Tap **Get** to download
4. The book will be added to your Library

### Reading

1. Tap any book in your Library to open it
2. Scroll vertically to read
3. Your progress is saved automatically
4. Tap the screen to show/hide controls

## License

This project is for personal use. Books downloaded from Anna's Archive are subject to their respective copyrights.

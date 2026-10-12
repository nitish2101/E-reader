import 'package:go_router/go_router.dart';

import '../library/library_screen.dart';
import '../store/store_screen.dart';
import '../settings/settings_screen.dart';
import '../reader/pdf_reader_screen.dart';
import '../reader/epub_reader_screen.dart';
import 'home_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      // Home with bottom navigation
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LibraryScreen()),
          ),
          GoRoute(
            path: '/store',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: StoreScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      // Reader routes (outside shell for fullscreen)
      GoRoute(
        path: '/reader/pdf/:bookId',
        builder: (context, state) {
          final bookId = state.pathParameters['bookId']!;
          return PdfReaderScreen(bookId: bookId);
        },
      ),
      GoRoute(
        path: '/reader/epub/:bookId',
        builder: (context, state) {
          final bookId = state.pathParameters['bookId']!;
          return EpubReaderScreen(bookId: bookId);
        },
      ),
    ],
  );
}

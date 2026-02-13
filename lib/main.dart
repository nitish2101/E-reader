import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/app_theme.dart';
import 'core/services/store_preload_service.dart';
import 'core/services/cache_config.dart';
import 'data/models/book_model.dart';
import 'data/repositories/book_repository.dart';
import 'data/repositories/store_repository.dart';
import 'presentation/library/bloc/library_bloc.dart';
import 'presentation/navigation/app_router.dart';

void main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(BookModelAdapter());
  await Hive.openBox<BookModel>('books');
  await Hive.openBox('settings');

  // Configure caching for better performance
  initializeCacheConfig();

  // Preload store data in background immediately (non-blocking)
  // Don't wait for UI, start fetching right away
  StorePreloadService.instance.preloadStoreData();

  runApp(const EReaderApp());
}

class EReaderApp extends StatelessWidget {
  const EReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<BookRepository>(
          create: (_) => BookRepository(),
        ),
        RepositoryProvider<StoreRepository>(
          create: (_) => StoreRepository(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<LibraryBloc>(
            create: (context) => LibraryBloc(
              bookRepository: context.read<BookRepository>(),
            )..add(LoadLibrary()),
          ),
        ],
        child: MaterialApp.router(
          title: 'E-Reader',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

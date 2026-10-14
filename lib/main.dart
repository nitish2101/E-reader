import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'core/services/cache_config.dart';
import 'data/models/book_model.dart';
import 'data/statistics/reading_statistics_repository.dart';
import 'data/statistics/reading_tracker.dart';
import 'data/repositories/book_repository.dart';
import 'data/repositories/store_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'presentation/library/bloc/library_bloc.dart';
import 'presentation/navigation/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Newsreader',
    ], await rootBundle.loadString('assets/fonts/newsreader/OFL.txt'));
  });

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(BookModelAdapter());
  await Hive.openBox<BookModel>('books');
  await Hive.openBox('settings');
  ReadingStatisticsRepository statistics;
  try {
    final statisticsBox = await Hive.openBox('readingStatistics');
    statistics = ReadingStatisticsRepository(statisticsBox);
    await statistics.initialize();
  } catch (error) {
    debugPrint('Statistics storage unavailable: $error');
    statistics = ReadingStatisticsRepository.unavailable();
  }

  // Configure caching for better performance
  initializeCacheConfig();

  runApp(EReaderApp(statistics: statistics));
}

class EReaderApp extends StatefulWidget {
  final ReadingStatisticsRepository? statistics;
  const EReaderApp({super.key, this.statistics});

  @override
  State<EReaderApp> createState() => _EReaderAppState();
}

class _EReaderAppState extends State<EReaderApp> {
  late final ReadingStatisticsRepository _statistics;
  late final ReadingTracker _tracker;
  @override
  void initState() {
    super.initState();
    _statistics =
        widget.statistics ??
        (Hive.isBoxOpen('readingStatistics')
            ? ReadingStatisticsRepository(Hive.box('readingStatistics'))
            : ReadingStatisticsRepository.unavailable());
    _tracker = ReadingTracker(_statistics);
  }

  @override
  void dispose() {
    _tracker.dispose();
    _statistics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ReadingStatisticsRepository>.value(
          value: _statistics,
        ),
        RepositoryProvider<ReadingTracker>.value(value: _tracker),
        RepositoryProvider<BookRepository>(create: (_) => BookRepository()),
        RepositoryProvider<StoreRepository>(create: (_) => StoreRepository()),
        RepositoryProvider<SettingsRepository>(
          create: (_) => SettingsRepository(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<LibraryBloc>(
            create: (context) =>
                LibraryBloc(bookRepository: context.read<BookRepository>())
                  ..add(LoadLibrary()),
          ),
        ],
        child: MaterialApp.router(
          title: 'E-Reader',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}

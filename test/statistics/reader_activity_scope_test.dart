import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ereader/data/statistics/reading_statistics_repository.dart';
import 'package:ereader/data/statistics/reading_tracker.dart';
import 'package:ereader/presentation/statistics/reader_activity_scope.dart';

void main() {
  late Directory directory;
  late ReadingStatisticsRepository repository;
  late ReadingTracker tracker;
  late ReaderActivityController activity;
  late Duration elapsed;
  late DateTime wall;
  void advance(int seconds) {
    elapsed += Duration(seconds: seconds);
    wall = wall.add(Duration(seconds: seconds));
  }

  int total() => repository.total.inSeconds;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reader-activity-');
    Hive.init(directory.path);
    repository = ReadingStatisticsRepository(
      await Hive.openBox('readingStatistics'),
    );
    wall = DateTime(2026, 10, 12, 12);
    elapsed = Duration.zero;
    tracker = ReadingTracker(
      repository,
      now: () => wall,
      elapsed: () => elapsed,
    );
    activity = ReaderActivityController();
  });
  tearDown(() async {
    tracker.dispose();
    await repository.flush();
    activity.dispose();
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<void> open(
    WidgetTester tester, {
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: tracker,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [readingRouteObserver],
          home: ReaderActivityScope(
            bookId: 'a',
            controller: activity,
            child: const Scaffold(body: Text('Reader')),
          ),
        ),
      ),
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await repository.flush();
  }

  testWidgets(
    'loading, screen lock and background resume gate the real clock',
    (tester) async {
      await tester.runAsync(() async {
        await open(tester);
        advance(20);
        tracker.checkpoint();
        expect(total(), 0);
        activity.setLoaded(true);
        advance(30);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        advance(100);
        tracker.checkpoint();
        expect(total(), 30);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        advance(10);
        activity.setBlocked(true);
        advance(60);
        activity.setBlocked(false);
        advance(20);
        await close(tester);
        expect(total(), 60);
      });
    },
  );
  testWidgets('covered routes and popup dialogs pause a loaded reader', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final navigator = GlobalKey<NavigatorState>();
      await open(tester, navigatorKey: navigator);
      activity.setLoaded(true);
      advance(10);
      final route = navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Cover')),
        ),
      );
      await tester.pumpAndSettle();
      advance(80);
      tracker.checkpoint();
      expect(total(), 10);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await route;
      advance(20);
      final dialog = showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Definition')),
      );
      await tester.pumpAndSettle();
      advance(80);
      tracker.checkpoint();
      expect(total(), 30);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await dialog;
      advance(10);
      await close(tester);
      expect(total(), 40);
    });
  });
  testWidgets('a real pointer wakes idle time but excludes the inactive gap', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await open(tester);
      activity.setLoaded(true);
      advance(600);
      tracker.checkpoint();
      expect(total(), 300);
      await tester.tap(find.text('Reader'));
      advance(20);
      await close(tester);
      expect(total(), 320);
    });
  });

  test(
    'cancelled PDF animation does not prevent the latest seek from resuming',
    () async {
      final reader = tracker.open('a');
      activity.addListener(() => reader.setActive(activity.ready));
      activity.setLoaded(true);
      advance(10);
      final abandoned = Completer<void>();
      final oldNavigation = activity.navigate(() => abandoned.future);
      final timedOut = expectLater(
        oldNavigation,
        throwsA(isA<TimeoutException>()),
      );
      final completed = Completer<void>();
      final latestNavigation = activity.navigate(() => completed.future);
      advance(20);
      completed.complete();
      await latestNavigation;
      expect(activity.ready, isTrue);
      advance(10);
      tracker.checkpoint();
      expect(total(), 20);
      await timedOut;
      expect(activity.ready, isTrue);
      reader.close();
    },
  );
  test(
    'superseded navigation completion cannot release the current seek',
    () async {
      final old = Completer<void>();
      final latest = Completer<void>();
      activity.setLoaded(true);
      final first = activity.navigate(() => old.future);
      final second = activity.navigate(() => latest.future);
      old.complete();
      await first;
      expect(activity.ready, isFalse);
      latest.complete();
      await second;
      expect(activity.ready, isTrue);
    },
  );
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ereader/data/statistics/reading_statistics_repository.dart';
import 'package:ereader/data/statistics/reading_tracker.dart';

void main() {
  late Directory directory;
  late ReadingStatisticsRepository repository;
  late ReadingTracker tracker;
  late DateTime wall;
  late Duration elapsed;
  void advance(Duration duration) {
    elapsed += duration;
    wall = wall.add(duration);
  }

  int total() =>
      repository.sessions.fold(0, (sum, s) => sum + s.duration.inSeconds);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reading-stats-');
    Hive.init(directory.path);
    final box = await Hive.openBox('readingStatistics');
    repository = ReadingStatisticsRepository(box);
    wall = DateTime(2026, 10, 12, 12);
    elapsed = Duration.zero;
    tracker = ReadingTracker(
      repository,
      now: () => wall,
      elapsed: () => elapsed,
    );
  });
  tearDown(() async {
    tracker.dispose();
    await repository.flush();
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test(
    'loading is excluded and checkpoints replace rather than add time',
    () async {
      final reader = tracker.open('a');
      advance(const Duration(seconds: 20));
      reader.setActive(true);
      advance(const Duration(seconds: 15));
      tracker.checkpoint();
      await repository.flush();
      advance(const Duration(seconds: 15));
      tracker.checkpoint();
      tracker.checkpoint();
      await repository.flush();
      expect(total(), 30);
      expect(repository.sessions, hasLength(1));
      reader.close();
      expect(total(), 30);
    },
  );
  test('idle is capped; interaction resumes without filling the idle gap', () {
    final reader = tracker.open('a')..setActive(true);
    advance(const Duration(minutes: 20));
    tracker.checkpoint();
    expect(total(), 300);
    reader.interact();
    advance(const Duration(seconds: 30));
    reader.close();
    expect(total(), 330);
    expect(repository.sessions, hasLength(2));
  });
  test(
    'background, inactive, disposal overlap does not duplicate duration',
    () {
      final reader = tracker.open('a')..setActive(true);
      advance(const Duration(seconds: 40));
      reader.setActive(false);
      reader.setActive(false);
      advance(const Duration(minutes: 10));
      reader.setActive(true);
      advance(const Duration(seconds: 20));
      reader.setActive(false);
      reader.close();
      reader.close();
      expect(total(), 60);
      expect(repository.sessions, hasLength(2));
    },
  );
  test('opening a new reader revokes the old reader lease', () {
    final old = tracker.open('a')..setActive(true);
    advance(const Duration(seconds: 10));
    final current = tracker.open('b')..setActive(true);
    old.setActive(true);
    old.interact();
    old.close();
    advance(const Duration(seconds: 20));
    current.close();
    expect(total(), 30);
    expect(
      repository.sessions
          .where((s) => s.bookId == 'a')
          .single
          .duration
          .inSeconds,
      10,
    );
    expect(
      repository.sessions
          .where((s) => s.bookId == 'b')
          .single
          .duration
          .inSeconds,
      20,
    );
  });
  test('midnight and Monday boundaries allocate actual intervals', () {
    wall = DateTime(2026, 10, 11, 23, 59, 30);
    final reader = tracker.open('a')..setActive(true);
    advance(const Duration(seconds: 90));
    reader.close();
    expect(repository.durationOn(DateTime(2026, 10, 11)).inSeconds, 30);
    expect(repository.durationOn(DateTime(2026, 10, 12)).inSeconds, 60);
    expect(repository.durationThisWeek(DateTime(2026, 10, 12)).inSeconds, 60);
    expect(repository.sessions, hasLength(1));
    expect(repository.sessions.single.intervals, hasLength(2));
  });
  test('monotonic elapsed time protects durations from wall clock edits', () {
    final reader = tracker.open('a')..setActive(true);
    elapsed += const Duration(seconds: 30);
    wall = wall.subtract(const Duration(hours: 3));
    reader.close();
    expect(total(), 30);
  });
  test(
    'lower idle setting takes effect without counting old idle time',
    () async {
      await repository.setIdleMinutes(2);
      final reader = tracker.open('a')..setActive(true);
      advance(const Duration(minutes: 8));
      reader.close();
      expect(total(), 120);
    },
  );
  test('periodic persisted sessions survive repository reopen', () async {
    final reader = tracker.open('a')..setActive(true);
    advance(const Duration(seconds: 15));
    tracker.checkpoint();
    await repository.flush();
    final second = ReadingStatisticsRepository(Hive.box('readingStatistics'));
    expect(second.sessions.single.duration.inSeconds, 15);
    expect(second.sessions.single.bookId, 'a');
    second.dispose();
    reader.close();
  });
  test('overlapping flushes persist the latest complete snapshot', () async {
    final reader = tracker.open('a')..setActive(true);
    advance(const Duration(seconds: 10));
    tracker.checkpoint();
    final firstSave = repository.flush();
    advance(const Duration(seconds: 10));
    tracker.checkpoint();
    final secondSave = repository.flush();
    advance(const Duration(seconds: 10));
    reader.close();
    await Future.wait([firstSave, secondSave, repository.flush()]);
    final reopened = ReadingStatisticsRepository(Hive.box('readingStatistics'));
    expect(reopened.sessions.single.duration.inSeconds, 30);
    expect(reopened.sessions, hasLength(1));
    reopened.dispose();
  });
  test('programmatic navigation cannot wake a reader after idle', () {
    final reader = tracker.open('a')..setActive(true);
    advance(const Duration(minutes: 8));
    tracker.checkpoint();
    // Reader relocation has no activity hook: only real user input calls interact.
    tracker.checkpoint();
    advance(const Duration(minutes: 1));
    reader.close();
    expect(total(), 300);
  });
}

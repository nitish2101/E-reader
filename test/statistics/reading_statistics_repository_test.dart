import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ereader/data/statistics/reading_session.dart';
import 'package:ereader/data/statistics/reading_statistics_repository.dart';

// Only disk write/flush failures are simulated; Hive serialization and reads
// still use a real temporary box.
class _FailingDiskBox implements Box<dynamic> {
  final Box<dynamic> box;
  bool failWrite = false;
  bool failFlush = false;
  _FailingDiskBox(this.box);
  @override
  Iterable<dynamic> get keys => box.keys;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      box.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (failWrite) {
      throw const FileSystemException('Simulated unavailable disk');
    }
    await box.put(key, value);
  }

  @override
  Future<void> flush() async {
    if (failFlush) throw const FileSystemException('Simulated failed flush');
    await box.flush();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late _FailingDiskBox disk;
  late ReadingStatisticsRepository repository;
  ReadingSession snapshot(int seconds) => ReadingSession(
    id: 'same-session',
    bookId: 'a',
    intervals: [
      ReadingInterval(
        DateTime.utc(2026, 10, 12, 12),
        DateTime.utc(2026, 10, 12, 12, 0, seconds),
        '2026-10-12',
      ),
    ],
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reading-disk-');
    Hive.init(directory.path);
    disk = _FailingDiskBox(await Hive.openBox('readingStatistics'));
    repository = ReadingStatisticsRepository(disk);
  });
  tearDown(() async {
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test(
    'failed writes retry the latest snapshot without doubling time',
    () async {
      disk.failWrite = true;
      repository.record(snapshot(15));
      await expectLater(
        repository.flush(),
        throwsA(isA<FileSystemException>()),
      );
      expect(repository.saveError, isNotNull);
      expect(repository.total.inSeconds, 15);
      repository.record(snapshot(30));
      disk.failWrite = false;
      await repository.flush();
      expect(repository.saveError, isNull);
      final reopened = ReadingStatisticsRepository(disk.box);
      expect(reopened.sessions, hasLength(1));
      expect(reopened.total.inSeconds, 30);
      reopened.dispose();
    },
  );
  test('disk flush failure leaves all snapshots retryable', () async {
    repository.record(snapshot(15));
    disk.failFlush = true;
    await expectLater(repository.flush(), throwsA(isA<FileSystemException>()));
    repository.record(snapshot(25));
    disk.failFlush = false;
    await repository.flush();
    final reopened = ReadingStatisticsRepository(disk.box);
    expect(reopened.total.inSeconds, 25);
    reopened.dispose();
  });
  test(
    'tracking installation date and idle setting persist independently',
    () async {
      await repository.initialize();
      final start = repository.trackingStarted;
      await repository.setIdleMinutes(10);
      final reopened = ReadingStatisticsRepository(disk.box);
      await reopened.initialize();
      expect(reopened.trackingStarted, start);
      expect(reopened.idleMinutes, 10);
      expect(reopened.total, Duration.zero);
      reopened.dispose();
    },
  );

  test('installation metadata write failure is recoverable', () async {
    disk.failWrite = true;
    await repository.initialize();
    expect(repository.saveError, isNotNull);
    expect(repository.trackingStarted, isNull);
    disk.failWrite = false;
    await repository.flush();
    expect(repository.trackingStarted, isNotNull);
    expect(repository.saveError, isNull);
  });

  test(
    'storage recovery hydrates history and flushes pending time in one retry',
    () async {
      repository.record(snapshot(15));
      await repository.flush();
      final recovered = ReadingStatisticsRepository.unavailable();
      final pending = snapshot(25);
      recovered.record(
        ReadingSession(
          id: 'new-session',
          bookId: pending.bookId,
          intervals: pending.intervals,
        ),
      );
      await recovered.flush();
      expect(recovered.total.inSeconds, 40);
      expect(recovered.sessions, hasLength(2));
      final reopened = ReadingStatisticsRepository(disk.box);
      expect(reopened.total.inSeconds, 40);
      expect(reopened.sessions, hasLength(2));
      recovered.dispose();
      reopened.dispose();
    },
  );
  test(
    'a newer pending snapshot wins over history loaded during recovery',
    () async {
      repository.record(snapshot(15));
      await repository.flush();
      final recovered = ReadingStatisticsRepository.unavailable();
      recovered.record(snapshot(25));
      await recovered.flush();
      expect(recovered.total.inSeconds, 25);
      final reopened = ReadingStatisticsRepository(disk.box);
      expect(reopened.total.inSeconds, 25);
      expect(reopened.sessions, hasLength(1));
      recovered.dispose();
      reopened.dispose();
    },
  );

  test(
    'omitted corrupt history stays visible after initialization and write recovery',
    () async {
      await disk.box.put('session:corrupt', {'intervals': 'invalid'});
      repository.dispose();
      repository = ReadingStatisticsRepository(disk);
      final readWarning = repository.saveError;
      expect(readWarning, isNotNull);
      await repository.initialize();
      expect(repository.saveError, readWarning);
      repository.record(snapshot(15));
      disk.failWrite = true;
      await expectLater(
        repository.flush(),
        throwsA(isA<FileSystemException>()),
      );
      expect(repository.saveError, isNot(readWarning));
      disk.failWrite = false;
      await repository.flush();
      expect(repository.saveError, readWarning);
      expect(repository.total.inSeconds, 15);
    },
  );
}

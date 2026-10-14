import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'reading_session.dart';

/// Local only. Full snapshots replace the same session ID, never add deltas.
/// The pending overlay survives write failures for a later retry in this process.
class ReadingStatisticsRepository {
  final changes = ValueNotifier<int>(0);
  Box? _box;
  final Map<String, ReadingSession> _sessions = {};
  final Map<String, ReadingSession> _pending = {};
  Future<void> _writes = Future.value();
  bool _disposed = false;
  bool _initializationFailed = false;
  String? _writeError;
  String? _readWarning;
  String? get saveError => _writeError ?? _readWarning;
  ReadingStatisticsRepository(Box box) : _box = box {
    _readSessions(box);
  }
  void _readSessions(Box box) {
    for (final key in box.keys.where(
      (key) => key is String && key.startsWith('session:'),
    )) {
      try {
        final session = ReadingSession.fromMap(box.get(key) as Map);
        if (session.intervals.isNotEmpty) {
          _sessions.putIfAbsent(session.id, () => session);
        }
      } catch (_) {
        _readWarning = 'Some recorded sessions could not be read.';
      }
    }
  }

  ReadingStatisticsRepository.unavailable() {
    _writeError =
        'Reading statistics storage is unavailable. Your library is still accessible.';
  }
  bool get isAvailable => _box != null;
  List<ReadingSession> get sessions =>
      _sessions.values.toList()..sort((a, b) => b.start.compareTo(a.start));
  DateTime? get trackingStarted => _box?.get('trackingStarted') is int
      ? DateTime.fromMillisecondsSinceEpoch(_box?.get('trackingStarted') as int)
      : null;
  int get idleMinutes {
    final value = _box?.get('idleMinutes', defaultValue: 5);
    return const [2, 5, 10, 15].contains(value) ? value as int : 5;
  }

  Future<void> initialize() async {
    try {
      if (_box == null) {
        _box = await Hive.openBox('readingStatistics');
        _readSessions(_box!);
      }
      if (trackingStarted == null) {
        await _box!.put(
          'trackingStarted',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      _initializationFailed = false;
      _writeError = null;
    } catch (error) {
      _initializationFailed = true;
      _writeError =
          'Reading statistics storage is unavailable. Your library is still accessible.';
      debugPrint('Statistics initialization failed: $error');
    }
    if (!_disposed) changes.value++;
  }

  Future<void> setIdleMinutes(int minutes) async {
    if (!const [2, 5, 10, 15].contains(minutes)) {
      throw ArgumentError('Unsupported idle threshold');
    }
    if (_box == null) throw StateError('Statistics storage unavailable');
    await _box!.put('idleMinutes', minutes);
    if (!_disposed) changes.value++;
  }

  void record(ReadingSession session) {
    if (session.intervals.isEmpty) return;
    _sessions[session.id] = session;
    _pending[session.id] = session;
    if (!_disposed) changes.value++;
  }

  Future<void> flush() {
    if (_pending.isEmpty && _box != null && !_initializationFailed) {
      return _writes;
    }
    final operation = _writes.then((_) async {
      if (_box == null || _initializationFailed) {
        await initialize();
        if (_box == null || _initializationFailed) {
          throw StateError('Statistics storage unavailable');
        }
      }
      if (_pending.isEmpty) return;
      final snapshots = Map<String, ReadingSession>.from(_pending);
      try {
        for (final entry in snapshots.entries) {
          await _box!.put('session:${entry.key}', entry.value.toMap());
          if (identical(_pending[entry.key], entry.value)) {
            _pending.remove(entry.key);
          }
        }
        await _box!.flush();
        _writeError = null;
      } catch (_) {
        // Keep every snapshot retryable, including a failed disk flush.
        for (final entry in snapshots.entries) {
          _pending.putIfAbsent(entry.key, () => entry.value);
        }
        _writeError =
            'Reading time could not be saved. Keep the app open and retry.';
        rethrow;
      } finally {
        if (!_disposed) changes.value++;
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Duration get total =>
      sessions.fold(Duration.zero, (sum, s) => sum + s.duration);
  List<ReadingSession> forBook(String bookId) =>
      sessions.where((s) => s.bookId == bookId).toList();
  Duration durationOn(DateTime date) {
    final day = readingDay(date);
    return sessions
        .expand((s) => s.intervals)
        .where((i) => i.day == day)
        .fold(Duration.zero, (sum, i) => sum + i.duration);
  }

  Duration durationThisWeek(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    var total = Duration.zero;
    for (
      var day = monday;
      !day.isAfter(today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      total += durationOn(day);
    }
    return total;
  }

  void dispose() {
    _disposed = true;
    changes.dispose();
  }
}

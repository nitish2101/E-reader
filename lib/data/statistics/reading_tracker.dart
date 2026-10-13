import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'reading_session.dart';
import 'reading_statistics_repository.dart';

/// One lease owns the tablet's reader clock. Elapsed time is monotonic, so
/// changing the system clock cannot create negative or inflated durations.
class ReadingTracker {
  final ReadingStatisticsRepository repository;
  final DateTime Function() now;
  late final Duration Function() elapsed;
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _timer;
  ReadingLease? _owner;
  bool _active = false;
  bool _disposed = false;
  Duration? _anchor;
  Duration? _cursor;
  Duration? _lastInteraction;
  DateTime? _wallAnchor;
  String? _sessionId;
  final List<ReadingInterval> _intervals = [];
  ReadingTracker(
    this.repository, {
    DateTime Function()? now,
    Duration Function()? elapsed,
  }) : now = now ?? DateTime.now {
    this.elapsed = elapsed ?? () => _stopwatch.elapsed;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => checkpoint());
  }
  ReadingLease open(String bookId) {
    if (_disposed) throw StateError('Tracker disposed');
    _stop();
    final lease = ReadingLease._(this, bookId);
    _owner = lease;
    return lease;
  }

  void _begin() {
    final instant = elapsed();
    _anchor = _cursor = _lastInteraction = instant;
    _wallAnchor = now();
    _sessionId = const Uuid().v4();
    _intervals.clear();
  }

  void _sample() {
    if (!_active || _anchor == null) return;
    final instant = elapsed();
    final deadline =
        _lastInteraction! + Duration(minutes: repository.idleMinutes);
    final end = instant < deadline ? instant : deadline;
    if (end > _cursor!) {
      var startWall = _wallAnchor!.add(_cursor! - _anchor!);
      final endWall = _wallAnchor!.add(end - _anchor!);
      while (startWall.isBefore(endWall)) {
        final midnight = DateTime(
          startWall.year,
          startWall.month,
          startWall.day + 1,
        );
        final boundary = midnight.isBefore(endWall) ? midnight : endWall;
        final interval = ReadingInterval(
          startWall.toUtc(),
          boundary.toUtc(),
          readingDay(startWall),
        );
        if (_intervals.isNotEmpty &&
            _intervals.last.day == interval.day &&
            _intervals.last.end == interval.start) {
          final previous = _intervals.removeLast();
          _intervals.add(
            ReadingInterval(previous.start, interval.end, interval.day),
          );
        } else {
          _intervals.add(interval);
        }
        startWall = boundary;
      }
      _cursor = end;
      repository.record(
        ReadingSession(
          id: _sessionId!,
          bookId: _owner!.bookId,
          intervals: _intervals,
        ),
      );
    }
    if (instant >= deadline) {
      _anchor = null;
      _intervals.clear();
    }
  }

  void checkpoint() {
    if (_disposed) return;
    _sample();
    _save();
  }

  void _save() {
    unawaited(
      repository.flush().catchError((Object error) {
        debugPrint('Reading statistics save failed: $error');
      }),
    );
  }

  void _stop() {
    _sample();
    _active = false;
    _anchor = null;
    _intervals.clear();
    _save();
  }

  void _setActive(ReadingLease lease, bool value) {
    if (_disposed ||
        !identical(lease, _owner) ||
        lease._closed ||
        _active == value) {
      return;
    }
    if (value && !repository.isAvailable) return;
    if (value) {
      _active = true;
      _begin();
    } else {
      _stop();
    }
  }

  void _interact(ReadingLease lease) {
    if (_disposed || !identical(lease, _owner) || lease._closed || !_active) {
      return;
    }
    _sample();
    if (_anchor == null) _begin();
    _lastInteraction = elapsed();
  }

  void _close(ReadingLease lease) {
    if (identical(lease, _owner)) {
      _stop();
      _owner = null;
    }
  }

  void dispose() {
    if (_disposed) return;
    _stop();
    _disposed = true;
    _timer?.cancel();
    _stopwatch.stop();
  }
}

class ReadingLease {
  final ReadingTracker _tracker;
  final String bookId;
  bool _closed = false;
  ReadingLease._(this._tracker, this.bookId);
  void setActive(bool active) => _tracker._setActive(this, active);
  void interact() => _tracker._interact(this);
  void close() {
    if (_closed) return;
    _closed = true;
    _tracker._close(this);
  }
}

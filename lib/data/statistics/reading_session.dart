/// A counted interval, stored in UTC with the local calendar day at recording.
/// Day keys stay stable if the tablet later changes time zone.
class ReadingInterval {
  final DateTime start;
  final DateTime end;
  final String day;
  const ReadingInterval(this.start, this.end, this.day);
  Duration get duration => end.difference(start);
  Map<String, dynamic> toMap() => {
    'start': start.toUtc().millisecondsSinceEpoch,
    'end': end.toUtc().millisecondsSinceEpoch,
    'day': day,
  };
  factory ReadingInterval.fromMap(Map data) => ReadingInterval(
    DateTime.fromMillisecondsSinceEpoch(data['start'] as int, isUtc: true),
    DateTime.fromMillisecondsSinceEpoch(data['end'] as int, isUtc: true),
    data['day'] as String,
  );
}

String readingDay(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class ReadingSession {
  final String id;
  final String bookId;
  final List<ReadingInterval> intervals;
  ReadingSession({
    required this.id,
    required this.bookId,
    required List<ReadingInterval> intervals,
  }) : intervals = List.unmodifiable(intervals);
  DateTime get start => intervals.first.start;
  DateTime get end => intervals.last.end;
  Duration get duration =>
      intervals.fold(Duration.zero, (sum, i) => sum + i.duration);
  Map<String, dynamic> toMap() => {
    'version': 1,
    'id': id,
    'bookId': bookId,
    'intervals': intervals.map((i) => i.toMap()).toList(),
  };
  factory ReadingSession.fromMap(Map data) => ReadingSession(
    id: data['id'] as String,
    bookId: data['bookId'] as String,
    intervals: (data['intervals'] as List)
        .map((i) => ReadingInterval.fromMap(i as Map))
        .toList(),
  );
}

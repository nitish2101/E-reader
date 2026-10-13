import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../data/models/book_model.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/statistics/reading_session.dart';
import '../../data/statistics/reading_statistics_repository.dart';

String formatReadingTime(Duration duration) {
  if (duration.inMinutes < 1) return '${duration.inSeconds}s';
  if (duration.inHours < 1) return '${duration.inMinutes}m';
  return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
}

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  Timer? _refresh;
  @override
  void initState() {
    super.initState();
    // Refresh calendar totals when midnight passes while this screen is open.
    _refresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ReadingStatisticsRepository>();
    final books = context.read<BookRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Reading statistics')),
      body: AnimatedBuilder(
        animation: repository.changes,
        builder: (context, _) => StreamBuilder(
          stream: books.watchBooks,
          builder: (context, _) {
            final now = DateTime.now();
            final library = books.getAllBooks();
            library.sort((a, b) {
              final aTime = repository
                  .forBook(a.id)
                  .fold(Duration.zero, (sum, s) => sum + s.duration);
              final bTime = repository
                  .forBook(b.id)
                  .fold(Duration.zero, (sum, s) => sum + s.duration);
              return bTime.compareTo(aTime);
            });
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _total(context, 'Total recorded', repository.total),
                        _total(context, 'Today', repository.durationOn(now)),
                        _total(
                          context,
                          'This week',
                          repository.durationThisWeek(now),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Estimated reading time · This tablet only',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Counts while a loaded reader is visible and active. Pauses in the background, during loading, and after inactivity. Inactivity does not necessarily mean you stopped reading. Weeks start on Monday. '
                      '${repository.trackingStarted == null ? 'Tracking begins with this feature.' : 'Tracking since ${DateFormat.yMMMd().format(repository.trackingStarted!)}.'} Earlier reading progress is preserved.',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Pause after no interaction'),
                        ),
                        DropdownButton<int>(
                          value: repository.idleMinutes,
                          items: const [2, 5, 10, 15]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text('$value minutes'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            try {
                              await repository.setIdleMinutes(value);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not save the idle setting. Try again.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    if (repository.saveError != null)
                      ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(repository.saveError!),
                        trailing: TextButton(
                          onPressed: () async {
                            try {
                              await repository.flush();
                            } catch (_) {
                              /* Error stays visible for retry. */
                            }
                          },
                          child: const Text('Retry'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Last 7 days',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            _DailyChart(repository: repository, now: now),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Books',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (library.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Open a book to begin recording reading time.',
                        ),
                      ),
                    for (final book in library)
                      _BookStatistics(
                        book: book,
                        sessions: repository.forBook(book.id),
                      ),
                    if (repository.sessions.any(
                      (session) =>
                          !library.any((book) => book.id == session.bookId),
                    ))
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Totals include recorded time for books removed from the library.',
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _total(BuildContext context, String label, Duration duration) =>
      SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 6),
                Text(
                  formatReadingTime(duration),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
        ),
      );
}

class _DailyChart extends StatelessWidget {
  final ReadingStatisticsRepository repository;
  final DateTime now;
  const _DailyChart({required this.repository, required this.now});
  @override
  Widget build(BuildContext context) {
    final dates = List.generate(
      7,
      (index) => DateTime(now.year, now.month, now.day - 6 + index),
    );
    final times = dates.map(repository.durationOn).toList();
    final maxSeconds = math.max(
      1,
      times.map((duration) => duration.inSeconds).reduce(math.max),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < 7; index++)
          Expanded(
            child: Semantics(
              label:
                  '${DateFormat.yMMMd().format(dates[index])}: ${formatReadingTime(times[index])}',
              child: Tooltip(
                message:
                    '${DateFormat.yMMMd().format(dates[index])}: ${formatReadingTime(times[index])}',
                child: Column(
                  children: [
                    Text(
                      formatReadingTime(times[index]),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 90,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: times[index].inSeconds / maxSeconds * 90,
                          width: 24,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('EEE').format(dates[index]),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BookStatistics extends StatelessWidget {
  final BookModel book;
  final List<ReadingSession> sessions;
  const _BookStatistics({required this.book, required this.sessions});
  @override
  Widget build(BuildContext context) {
    final total = sessions.fold(Duration.zero, (sum, s) => sum + s.duration);
    final progress = book.lastReadProgress.isFinite
        ? book.lastReadProgress.clamp(0.0, 1.0)
        : 0.0;
    Widget placeholder() => const ColoredBox(
      color: Colors.black12,
      child: Center(child: Icon(Icons.menu_book)),
    );
    final lastRead = sessions.isEmpty
        ? null
        : sessions.map((s) => s.end).reduce((a, b) => a.isAfter(b) ? a : b);
    return Card(
      child: ExpansionTile(
        key: PageStorageKey('stats:${book.id}'),
        leading: SizedBox(
          width: 40,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: book.localCoverPath != null
                ? Image.file(
                    File(book.localCoverPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => placeholder(),
                  )
                : book.coverUrl != null
                ? Image.network(
                    book.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => placeholder(),
                  )
                : placeholder(),
          ),
        ),
        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatReadingTime(total)} recorded · ${(progress * 100).toStringAsFixed(1)}% progress',
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lastRead == null
                ? 'Last recorded read: No sessions yet'
                : 'Last recorded read: ${DateFormat.yMMMd().add_jm().format(lastRead.toLocal())}',
          ),
          Text(
            'Average session: ${sessions.isEmpty ? '—' : formatReadingTime(Duration(milliseconds: total.inMilliseconds ~/ sessions.length))}',
          ),
          const SizedBox(height: 8),
          Text(
            book.isEpub
                ? 'Estimated WPM: Unavailable — this reader cannot reliably measure text traversed.'
                : 'Estimated WPM: Unavailable — PDF text traversal is not supported, including scanned PDFs.',
          ),
          const SizedBox(height: 12),
          if (sessions.isEmpty)
            const Text('No recorded sessions yet')
          else ...[
            Text(
              'Session history (${sessions.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            // Keep expanded rows compact even after months of daily reading.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      DateFormat.yMMMd().add_jm().format(
                        session.start.toLocal(),
                      ),
                    ),
                    subtitle: Text(
                      'Until ${DateFormat.yMMMd().add_jm().format(session.end.toLocal())}',
                    ),
                    trailing: Text(formatReadingTime(session.duration)),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

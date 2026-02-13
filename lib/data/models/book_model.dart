import 'package:hive/hive.dart';

part 'book_model.g.dart';

@HiveType(typeId: 0)
class BookModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final String? coverUrl;

  @HiveField(4)
  final String? localCoverPath;

  @HiveField(5)
  final String localPath;

  @HiveField(6)
  final String format; // 'pdf' or 'epub'

  @HiveField(7)
  final int totalPages;

  @HiveField(8)
  int lastReadPage;

  @HiveField(9)
  double lastReadProgress; // 0.0 to 1.0

  @HiveField(10)
  String? lastReadCfi; // For EPUB position

  @HiveField(11)
  DateTime lastReadTime;

  @HiveField(12)
  final DateTime addedTime;

  @HiveField(13)
  final String? md5; // For Anna's Archive

  @HiveField(14)
  final int? fileSize; // In bytes

  BookModel({
    required this.id,
    required this.title,
    required this.author,
    this.coverUrl,
    this.localCoverPath,
    required this.localPath,
    required this.format,
    this.totalPages = 0,
    this.lastReadPage = 0,
    this.lastReadProgress = 0.0,
    this.lastReadCfi,
    DateTime? lastReadTime,
    DateTime? addedTime,
    this.md5,
    this.fileSize,
  })  : lastReadTime = lastReadTime ?? DateTime.now(),
        addedTime = addedTime ?? DateTime.now();

  bool get isPdf => format.toLowerCase() == 'pdf';
  bool get isEpub => format.toLowerCase() == 'epub';
  
  String get readingPercentage {
    final percent = lastReadProgress * 100;
    if (percent == 0) return '0';
    return percent.toStringAsFixed(1);
  }
  
  bool get hasStartedReading => lastReadPage > 0 || lastReadProgress > 0;

  BookModel copyWith({
    String? id,
    String? title,
    String? author,
    String? coverUrl,
    String? localCoverPath,
    String? localPath,
    String? format,
    int? totalPages,
    int? lastReadPage,
    double? lastReadProgress,
    String? lastReadCfi,
    DateTime? lastReadTime,
    DateTime? addedTime,
    String? md5,
    int? fileSize,
  }) {
    return BookModel(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverUrl: coverUrl ?? this.coverUrl,
      localCoverPath: localCoverPath ?? this.localCoverPath,
      localPath: localPath ?? this.localPath,
      format: format ?? this.format,
      totalPages: totalPages ?? this.totalPages,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      lastReadProgress: lastReadProgress ?? this.lastReadProgress,
      lastReadCfi: lastReadCfi ?? this.lastReadCfi,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      addedTime: addedTime ?? this.addedTime,
      md5: md5 ?? this.md5,
      fileSize: fileSize ?? this.fileSize,
    );
  }
}

import 'dart:io';
import 'package:ereader/data/models/book_model.dart';
import 'package:ereader/data/repositories/book_repository.dart';
import 'package:ereader/presentation/reader/bloc/reader_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test(
    'PDF close preserves the latest synchronous native page callback',
    () async {
      final dir = await Directory.systemTemp.createTemp('pdf-checkpoint-');
      Hive.init(dir.path);
      Hive.registerAdapter(BookModelAdapter());
      final box = await Hive.openBox<BookModel>('books');
      final file = await File(
        '${dir.path}/book.pdf',
      ).writeAsBytes([37, 80, 68, 70]);
      await box.put(
        'pdf',
        BookModel(
          id: 'pdf',
          title: 'PDF',
          author: 'Author',
          localPath: file.path,
          format: 'pdf',
          lastReadPage: 2,
          totalPages: 10,
        ),
      );
      final bloc = ReaderBloc(bookRepository: BookRepository(booksBox: box));
      final loaded = bloc.stream.firstWhere((state) => state is ReaderLoaded);
      bloc.add(const LoadBook('pdf'));
      await loaded;
      bloc.confirmPdfPosition(8, 10);
      await bloc.close();
      await box.close();
      final reopened = await Hive.openBox<BookModel>('books');
      expect(reopened.get('pdf')!.lastReadPage, 8);
      expect(reopened.get('pdf')!.lastReadProgress, 0.8);
      await Hive.close();
      await dir.delete(recursive: true);
    },
  );
}

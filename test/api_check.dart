
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:annas_archive_api/annas_archive_api.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = MyHttpOverrides();
  });

  test('Search Anna\'s Archive', () async {
    final api = AnnaApi(); 
    try {
      final searchRequest = SearchRequest(
        query: 'flutter programming',
        formats: [Format.pdf, Format.epub],
        page: 1,
      );
      
      final result = await api.find(searchRequest);
      
      print('\n--- API CHECK RESULTS ---');
      print('Total results found: ${result.total}');
      if (result.books.isNotEmpty) {
        print('First book title: ${result.books.first.title}');
        print('First book author: ${result.books.first.author}');
      } else {
        print('No books found for query "flutter programming"');
      }
      print('--- END RESULTS ---\n');
      
      expect(result.books.isNotEmpty, true);
    } catch (e) {
      print('\n--- API ERROR ---');
      print(e);
      print('--- END ERROR ---\n');
      rethrow;
    }
  });
}

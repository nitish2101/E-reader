import 'package:dio/dio.dart';
import '../models/dictionary_entry.dart';

class DictionaryRepository {
  final Dio _dio;

  DictionaryRepository({Dio? dio}) : _dio = dio ?? Dio();

  Future<List<DictionaryEntry>> getDefinition(String word) async {
    try {
      final response = await _dio.get('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => DictionaryEntry.fromJson(json)).toList();
      } else {
        return [];
      }
    } catch (e) {
      // 404 means word not found
      if (e is DioException && e.response?.statusCode == 404) {
        return [];
      }
      throw Exception('Failed to load definition: $e');
    }
  }
}

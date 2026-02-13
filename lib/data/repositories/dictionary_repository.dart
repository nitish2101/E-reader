
import 'package:dio/dio.dart';
import '../models/dictionary_entry.dart';

class DictionaryRepository {
  final Dio _dio = Dio();
  final String _baseUrl = 'https://api.dictionaryapi.dev/api/v2/entries/en';

  Future<List<DictionaryEntry>> getDefinition(String word) async {
    try {
      final response = await _dio.get('$_baseUrl/$word');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => DictionaryEntry.fromJson(json)).toList();
      }
      return [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Word not found
        return [];
      }
      throw Exception('Failed to fetch definition: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }
}

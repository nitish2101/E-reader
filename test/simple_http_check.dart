
import 'dart:io';
import 'package:http/http.dart' as http;

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  HttpOverrides.global = MyHttpOverrides();
  try {
    print('Testing https://annas-archive.li');
    final response = await http.get(Uri.parse('https://annas-archive.li'));
    print('Status: ${response.statusCode}');
    print('Body length: ${response.body.length}');
    if (response.body.length < 1000) {
      print('Body preview: ${response.body}');
    } else {
      print('Body preview: ${response.body.substring(0, 500)}...');
    }
  } catch (e) {
    print('Error: $e');
  }
}

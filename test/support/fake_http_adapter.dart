import 'dart:typed_data';
import 'package:dio/dio.dart';

class FakeHttpAdapter implements HttpClientAdapter {
  late ResponseBody Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

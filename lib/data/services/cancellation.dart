import 'package:dio/dio.dart';

extension CancellationCheck on CancelToken {
  void throwIfCancellationRequested() {
    if (isCancelled) throw cancelError!;
  }
}

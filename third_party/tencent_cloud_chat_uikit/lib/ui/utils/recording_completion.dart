import 'dart:async';
import 'package:flutter_plugin_record_plus/const/response.dart';

/// A bounded subscription owned by the accepted send, independent of UI listeners.
Future<RecordResponse> waitForRecordingCompletion(
  Stream<RecordResponse> responses,
  String sessionId, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final result = Completer<RecordResponse>();
  final subscription = responses.listen((event) {
    if (event.sessionId == sessionId &&
        (event.msg == 'onStop' || event.msg == 'onRecordFail') &&
        !result.isCompleted) {
      result.complete(event);
    }
  }, onError: (Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  }, onDone: () {
    if (!result.isCompleted)
      result.completeError(StateError('recorder closed'));
  });
  try {
    return await result.future.timeout(timeout);
  } finally {
    await subscription.cancel();
  }
}

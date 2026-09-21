import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_plugin_record_plus/const/response.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/recording_completion.dart';

void main() {
  test('iOS finalization performs disk I/O before returning to the main queue',
      () {
    final source = File(
            'third_party/flutter_plugin_record_plus/ios/Classes/DPAudioRecorder.m')
        .readAsStringSync();
    final begin = source.indexOf('- (void)audioRecorderDidFinishRecording:');
    final finish = source.indexOf('NSData* writeWavFileHeader', begin);
    final body = source.substring(begin, finish);
    final worker = body.indexOf('dispatch_async(dispatch_get_global_queue');
    final read = body.indexOf('dataWithContentsOfFile:');
    final write = body.indexOf('writeToFile:');
    final main = body.indexOf('dispatch_async(dispatch_get_main_queue()');
    expect(worker, greaterThanOrEqualTo(0));
    expect(read, greaterThan(worker));
    expect(write, greaterThan(read));
    expect(main, greaterThan(write));
    expect(body.contains('dispatch_sync'), isFalse);
    expect(body.contains('NSUUID.UUID.UUIDString'), isTrue);
    expect(body.contains('finished(wave, duration, outputPath)'), isTrue);
  });

  test('accepted completion survives removal of the page listener', () async {
    final events = StreamController<RecordResponse>.broadcast();
    final page = events.stream.listen((_) {});
    final completion = waitForRecordingCompletion(events.stream, 'accepted');
    await page.cancel();
    events.add(RecordResponse(sessionId: 'other', msg: 'onStop'));
    events.add(RecordResponse(sessionId: 'accepted', msg: 'onStart'));
    final stopped =
        RecordResponse(sessionId: 'accepted', msg: 'onStop', path: 'voice.wav');
    events.add(stopped);
    expect(await completion, same(stopped));
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('concurrent sessions never consume each others completion', () async {
    final events = StreamController<RecordResponse>.broadcast();
    final first = waitForRecordingCompletion(events.stream, 'first');
    final second = waitForRecordingCompletion(events.stream, 'second');
    events.add(RecordResponse(sessionId: 'second', msg: 'onRecordFail'));
    expect((await second).msg, 'onRecordFail');
    events.add(RecordResponse(sessionId: 'first', msg: 'onStop'));
    expect((await first).sessionId, 'first');
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('missing native callback times out and releases its subscription',
      () async {
    final events = StreamController<RecordResponse>.broadcast();
    await expectLater(
        waitForRecordingCompletion(events.stream, 'missing',
            timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()));
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('recorder shutdown rejects pending completion and releases listener',
      () async {
    final events = StreamController<RecordResponse>.broadcast();
    final check = expectLater(
        waitForRecordingCompletion(events.stream, 'pending'), throwsStateError);
    await events.close();
    await check;
    expect(events.hasListener, isFalse);
  });
}

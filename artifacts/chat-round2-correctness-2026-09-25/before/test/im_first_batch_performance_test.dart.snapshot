import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
// fake_async is supplied by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/local_image_file_cache.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/speculative_media_queue.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/voice_waveform_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('media gate waits for every interaction and a quiet interval', () {
    var now = DateTime(2026);
    var animation = false;
    final gate = BackgroundMediaGate(
      platformBusy: () => animation,
      now: () => now,
    );
    final feed = Object(), chat = Object();
    gate.setBusy(feed, true);
    gate.setBusy(chat, true);
    gate.setBusy(feed, false);
    now = now.add(const Duration(seconds: 1));
    expect(gate.canStart, false);
    gate.setBusy(chat, false);
    expect(gate.canStart, false);
    now = now.add(const Duration(milliseconds: 201));
    expect(gate.canStart, true);
    animation = true;
    expect(gate.canStart, false);
    animation = false;
    expect(gate.canStart, false);
    now = now.add(const Duration(milliseconds: 201));
    expect(gate.canStart, true);
    gate.pauseKeyboard();
    expect(gate.canStart, false);
    gate.resumeKeyboard();
    expect(gate.canStart, false);
    now = now.add(const Duration(milliseconds: 201));
    expect(gate.canStart, true);
    gate.didChangeMetrics();
    expect(gate.canStart, true);
  });

  test('queued prefetch deduplicates, resumes gradually, and cancels pending',
      () {
    fakeAsync((clock) {
      var idle = false;
      final starts = <String>[];
      final queue = SpeculativeMediaQueue(canStart: () => idle);
      for (final key in ['a', 'b', 'a', 'c']) {
        queue.add(key, () async {
          starts.add(key);
        });
      }
      clock.elapse(const Duration(milliseconds: 300));
      expect(starts, isEmpty);
      idle = true;
      clock.elapse(const Duration(milliseconds: 100));
      expect(starts, ['a']);
      clock.elapse(const Duration(milliseconds: 32));
      expect(starts, ['a', 'b']);
      queue.cancelPending();
      clock.elapse(const Duration(seconds: 1));
      expect(starts, ['a', 'b']);
    });
  });

  test('in-flight prefetch finishes but cannot start more during interaction',
      () {
    fakeAsync((clock) {
      var idle = true;
      final active = Completer<void>();
      final starts = <String>[];
      final queue =
          SpeculativeMediaQueue(canStart: () => idle, maxConcurrent: 1);
      queue.add('a', () {
        starts.add('a');
        return active.future;
      });
      queue.add('b', () async {
        starts.add('b');
      });
      clock.elapse(Duration.zero);
      idle = false;
      active.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(starts, ['a']);
      idle = true;
      clock.elapse(const Duration(milliseconds: 100));
      expect(starts, ['a', 'b']);
      queue.cancelPending();
    });
  });

  test('prefetch lifecycle pause has no polling and resumes pending work', () {
    fakeAsync((clock) {
      var count = 0;
      final queue = SpeculativeMediaQueue(canStart: () => true);
      queue.setPaused(true);
      queue.add('a', () async {
        count++;
      });
      clock.elapse(const Duration(seconds: 2));
      expect(count, 0);
      expect(clock.pendingTimers, isEmpty);
      queue.setPaused(false);
      clock.elapse(const Duration(milliseconds: 32));
      expect(count, 1);
      queue.cancelPending();
    });
  });

  test('prefetch failure releases slot and queue capacity keeps newest work',
      () {
    fakeAsync((clock) {
      var idle = false;
      final starts = <int>[];
      final queue = SpeculativeMediaQueue(
          canStart: () => idle, capacity: 2, maxConcurrent: 1);
      queue.add('old', () async {
        starts.add(0);
      });
      queue.add('bad', () async {
        starts.add(1);
        throw StateError('decode');
      });
      queue.add('new', () async {
        starts.add(2);
      });
      idle = true;
      clock.elapse(const Duration(milliseconds: 100));
      expect(starts, [1, 2]);
      queue.cancelPending();
    });
  });

  test(
      'file probes coalesce and stale completion cannot revive invalidated path',
      () async {
    var probes = 0;
    final first = Completer<bool>(), second = Completer<bool>();
    final cache = LocalImageFileCache(probe: (_) {
      return ++probes == 1 ? first.future : second.future;
    });
    final a = cache.check('image');
    final b = cache.check('image');
    expect(identical(a, b), true);
    expect(cache.peek('image'), isNull);
    cache.invalidate('image');
    final fresh = cache.check('image');
    second.complete(false);
    await fresh;
    first.complete(true);
    await a;
    expect(cache.peek('image'), false);
    expect(probes, 2);
  });

  test('file cache refresh discovers download and expiry discovers deletion',
      () async {
    var now = DateTime(2026);
    var exists = false;
    var probes = 0;
    final cache = LocalImageFileCache(
      now: () => now,
      probe: (_) async {
        probes++;
        return exists;
      },
    );
    expect(await cache.check('p'), false);
    exists = true;
    expect(await cache.check('p'), false);
    expect(probes, 1);
    expect(await cache.check('p', refresh: true), true);
    exists = false;
    now = now.add(const Duration(seconds: 6));
    expect(await cache.check('p'), false);
    cache.clear();
    expect(cache.peek('p'), isNull);
  });

  test('file cache is bounded and does not cache failed probes as available',
      () async {
    final cache = LocalImageFileCache(
        capacity: 2,
        probe: (path) async {
          if (path == 'broken') throw FileSystemException('missing');
          return true;
        });
    await cache.check('a');
    await cache.check('b');
    cache.peek('a');
    await cache.check('c');
    expect(cache.peek('b'), isNull);
    expect(cache.peek('a'), true);
    expect(await cache.check('broken'), false);
  });

  test('waveform worker reads PCM accurately and missing files can recover',
      () async {
    final dir = await Directory.systemTemp.createTemp('waveform-worker-test-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/voice.wav';
    final missing = await VoiceWaveformExtractor.load(
        cacheKey: path, localPath: path, fallbackSeed: 'voice', barCount: 2);
    expect(missing.durationMs, isNull);
    final wav = ByteData(44 + 32000);
    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        wav.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    wav.setUint32(4, wav.lengthInBytes - 8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, 1, Endian.little);
    wav.setUint32(24, 16000, Endian.little);
    wav.setUint32(28, 32000, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    wav.setUint32(40, 32000, Endian.little);
    wav.setInt16(44, 16384, Endian.little);
    wav.setInt16(44 + 16000, 8192, Endian.little);
    await File(path).writeAsBytes(wav.buffer.asUint8List());
    final results = await Future.wait(List.generate(
        4,
        (_) => VoiceWaveformExtractor.load(
            cacheKey: path,
            localPath: path,
            fallbackSeed: 'voice',
            barCount: 2)));
    for (final result in results) {
      expect(result.durationMs, 1000);
      expect(result.bars[0], closeTo(1, 0.001));
      expect(result.bars[1], closeTo(0.61, 0.001));
    }
    expect(await VoiceWaveformExtractor.extractFromFile(path, barCount: 3),
        isNotNull);
  });

  test('invalid waveform paths do not block later files', () async {
    final dir =
        await Directory.systemTemp.createTemp('waveform-worker-errors-');
    addTearDown(() => dir.delete(recursive: true));
    expect(await VoiceWaveformExtractor.extractFromFile(dir.path), isNull);
    final valid = File('${dir.path}/valid.raw');
    await valid.writeAsBytes(List.filled(512, 200));
    expect(await VoiceWaveformExtractor.extractFromFile(valid.path), isNotNull);
    expect(await VoiceWaveformExtractor.extractFromFile('${dir.path}/missing'),
        isNull);
  });
}

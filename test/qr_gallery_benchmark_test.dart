// This opt-in test deliberately emits machine-readable benchmark JSON.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_demo/src/utils/qr_app_payload.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_gallery_decoder.dart';

// Opt-in so normal CI does not turn timing/RSS variation into a pass/fail gate.
// A manifest can supply real failure images and expected IDs or exact values.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('QR_GALLERY_BENCHMARK');
  const manifestPath = String.fromEnvironment('QR_GALLERY_BENCHMARK_MANIFEST');
  const repeats =
      int.fromEnvironment('QR_GALLERY_BENCHMARK_REPEATS', defaultValue: 3);
  test('gallery recognition benchmark', () async {
    var base = Directory.current.path;
    var samples = <Map<String, dynamic>>[
      {
        'file':
            'test/fixtures/qr_gallery/IMAGE_2026-06-20_21_22_37-56b1a881-05d3-45e7-b6b2-8ee6d77e0cf7.png',
        'expectedIds': ['acnj6oxey9'],
      },
      {
        'file':
            'test/fixtures/qr_gallery/IMAGE_2026-06-20_21_22_39-e3caf051-8631-41c6-bc49-fb42868d0d79.png',
        'expectedIds': ['jc1kbqdxvf'],
      },
    ];
    if (manifestPath.isNotEmpty) {
      final manifest = File(manifestPath).absolute;
      base = manifest.parent.path;
      samples = (jsonDecode(await manifest.readAsString()) as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    }
    expect(samples, isNotEmpty);
    expect(repeats, greaterThan(0));
    var correctRuns = 0;
    var runs = 0;
    final elapsedTimes = <int>[];
    for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
      final sample = samples[sampleIndex];
      final path = p.normalize(p.join(base, sample['file'] as String));
      final expectedIds =
          (sample['expectedIds'] as List? ?? []).cast<String>().toSet();
      final expectedValues =
          (sample['expectedValues'] as List? ?? []).cast<String>().toSet();
      expect(expectedIds.isNotEmpty || expectedValues.isNotEmpty, isTrue,
          reason: 'Sample $sampleIndex needs ground truth');
      for (var run = 0; run < repeats; run++) {
        final clock = Stopwatch()..start();
        var lastTick = 0;
        var maxGap = 0;
        final rssBefore = ProcessInfo.currentRss;
        var sampledPeak = rssBefore;
        final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
          final now = clock.elapsedMilliseconds;
          maxGap = math.max(maxGap, now - lastTick);
          lastTick = now;
          sampledPeak = math.max(sampledPeak, ProcessInfo.currentRss);
        });
        late QrGalleryScanResult result;
        late int elapsed;
        try {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          final start = clock.elapsedMilliseconds;
          result = await QrGalleryDecoder.scan(path);
          elapsed = clock.elapsedMilliseconds - start;
          sampledPeak = math.max(sampledPeak, ProcessInfo.currentRss);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        } finally {
          timer.cancel();
        }
        final actual = result.values.toSet();
        final actualIds = actual
            .map(QrAppPayload.tryParse)
            .whereType<QrAppPayload>()
            .map((payload) => payload.id)
            .toSet();
        final correct = result.status == 'ok' &&
            actualIds.containsAll(expectedIds) &&
            actual.containsAll(expectedValues);
        if (correct) correctRuns++;
        runs++;
        elapsedTimes.add(elapsed);
        // No filenames, QR contents, login sessions or user IDs in benchmark logs.
        print(jsonEncode({
          'sampleIndex': sampleIndex,
          'run': run,
          'correct': correct,
          ...result.diagnostics,
          'codes': actual.length,
          'elapsedMs': elapsed,
          'maxEventLoopGapMs': maxGap,
          'sampledProcessRssDeltaBytes': sampledPeak - rssBefore,
        }));
      }
    }
    elapsedTimes.sort();
    print(jsonEncode({
      'samples': samples.length,
      'correctRuns': correctRuns,
      'runs': runs,
      'recognitionRate': correctRuns / runs,
      'p50Ms': elapsedTimes[(runs * 0.50).ceil() - 1],
      'p95Ms': elapsedTimes[(runs * 0.95).ceil() - 1],
      'platform': Platform.operatingSystem,
    }));
  }, skip: !enabled);
}

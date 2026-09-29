import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/android_performance_profile.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/native_bootstrap_perf_flags.dart';

/// Relationship-list consume rhythm. Time constants come from the existing
/// startup chain; isolate thresholds follow [AndroidPerformanceProfile.tier].
class ImSdkRelationshipPerf {
  ImSdkRelationshipPerf._();

  static const int firstScreenCount = 80;
  static const int projectionBatchSize = 250;
  static const Duration groupSdkMinInterval = Duration(milliseconds: 150);
  static const Duration uiIdleTimeout = Duration(seconds: 15);

  static Duration get stageYield => NativeBootstrapPerfFlags.stageYield;

  static int isolateSortMinEntries() {
    if (kIsWeb) {
      return 1 << 30;
    }
    switch (AndroidPerformanceProfile.instance.tier) {
      case AndroidPerformanceTier.low:
        return 1500;
      case AndroidPerformanceTier.medium:
        return 3000;
      case AndroidPerformanceTier.normal:
        return 5000;
    }
  }

  static bool shouldIsolateSort(int entryCount) {
    return entryCount >= isolateSortMinEntries();
  }
}

/// Isolate entry: each row is `[userId, sortKey]`. Returns only ordered ids.
List<String> imSdkRelationshipSortIds(List<List<String>> rows) {
  final copy = List<List<String>>.from(rows);
  copy.sort((a, b) {
    final byKey = a[1].compareTo(b[1]);
    if (byKey != 0) {
      return byKey;
    }
    return a[0].compareTo(b[0]);
  });
  return <String>[for (final row in copy) row[0]];
}

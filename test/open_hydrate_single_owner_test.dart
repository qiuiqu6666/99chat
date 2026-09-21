import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/open_hydrate_result.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  late TUIChatGlobalModel model;
  setUp(() => model = TUIChatGlobalModel());
  tearDown(() => model.dispose());

  test(
      'alias callers share a task; timeout keeps flight and empty result is reused',
      () async {
    final release = Completer<bool>();
    var calls = 0;
    Future<bool> load() {
      calls++;
      return release.future;
    }

    final task = model.ensureOpenHydrate('c2c_u1',
        requestSignature: 'tip1', load: load, canPublish: () => true);
    final alias = model.ensureOpenHydrate('u1',
        requestSignature: 'tip1', load: load, canPublish: () => true);
    expect(identical(task, alias), isTrue);
    await model.awaitOpenHydrateInFlight('c2c_u1',
        timeout: const Duration(milliseconds: 1));
    expect(model.hasOpenHydrateInFlight('u1'), isTrue);
    expect(calls, 1);
    model.markLocalInitialHistoryVisible('c2c_u1');
    release.complete(true);
    expect((await task).kind, OpenHydrateResultKind.committedEmpty);
    final again = await model.ensureOpenHydrate('c2c_u1',
        requestSignature: 'tip1', load: load, canPublish: () => true);
    expect(again.shouldSuppressOrdinaryLoad, isTrue);
    expect(calls, 1);
    expect(model.hasOpenHydrateInFlight('u1'), isFalse);
  });

  test(
      'false and failed reads never become prepared; subsequent attempt retries',
      () async {
    final failed = await model.ensureOpenHydrate('c2c_u1',
        requestSignature: 'tip1',
        load: () async => false,
        canPublish: () => true);
    expect(failed.shouldSuppressOrdinaryLoad, isFalse);
    final error = await model.ensureOpenHydrate('c2c_u1',
        requestSignature: 'tip1',
        load: () async => throw StateError('offline'),
        canPublish: () => true);
    expect(error.kind, OpenHydrateResultKind.failed);
    final retry = await model.ensureOpenHydrate('c2c_u1',
        requestSignature: 'tip1',
        load: () async => true,
        canPublish: () => true);
    expect(retry.shouldSuppressOrdinaryLoad, isTrue);
  });

  test('account or search invalidation cannot publish a late success',
      () async {
    var current = true;
    final release = Completer<bool>();
    final task = model.ensureOpenHydrate('c2c_u1',
        requestSignature: 'tip1',
        load: () => release.future,
        canPublish: () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    release.complete(true);
    expect((await task).kind, OpenHydrateResultKind.aborted);
    expect(model.openHydrateResultFor('c2c_u1'), isNull);
  });

  test('clearing during a read rejects its terminal result', () async {
    final release = Completer<bool>();
    final task = model.ensureOpenHydrate('c2c_u1',
        requestSignature: 'tip1',
        load: () => release.future,
        canPublish: () => true);
    await Future<void>.delayed(Duration.zero);
    model.clearLocalHistoryAsEmptyLoaded('c2c_u1');
    release.complete(true);
    expect((await task).kind, OpenHydrateResultKind.aborted);
    expect(model.openHydrateResultFor('c2c_u1'), isNull);
  });

  test('window eviction invalidates a completed result', () async {
    model.markLocalInitialHistoryVisible('c2c_u1');
    await model.ensureOpenHydrate('c2c_u1',
        requestSignature: 'tip1',
        load: () async => true,
        canPublish: () => true);
    model.removeMessageList('c2c_u1');
    expect(model.openHydrateResultFor('c2c_u1'), isNull);
  });
}

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/api_wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_controller.dart';

Map<String, Object> ledgerRow(int id) => {
      'id': '$id',
      'ledgerType': 'TRANSFER_IN',
      'source': 'INTERNAL',
      'currency': 'USDT',
      'amount': 100,
      'direction': 'IN',
      'status': 'SUCCESS',
      'createdAt': '2026-09-25T04:00:00Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'second history page committed in background becomes visible without reopening or refetch',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('ledger_commit_');
    await databaseFactory.setDatabasesPath(directory.path);
    final dio = ApiClient.instance.dio;
    final interceptors = dio.interceptors.toList();
    final secondStarted = Completer<void>();
    final secondReply = Completer<void>();
    var ledgerRequests = 0;
    await ApiClient.instance.saveToken('token', userId: 'ledger-commit-owner');
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (request, handler) async {
        if (request.path != '/wallet/ledger') {
          handler.resolve(Response(
              requestOptions: request, statusCode: 200, data: {'data': []}));
          return;
        }
        ledgerRequests++;
        final page = request.queryParameters['page'];
        if (page == 1) {
          secondStarted.complete();
          await secondReply.future;
        }
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'data': {
            'content':
                page == 0 ? List.generate(100, ledgerRow) : [ledgerRow(100)],
          }
        }));
      }));
    final controller =
        WalletRecordController(repo: const ApiWalletRepository());
    try {
      await controller.load();
      expect(controller.list.length, 100);
      await secondStarted.future;
      final updated = Completer<void>();
      controller.addListener(() {
        if (controller.list.length == 101 && !updated.isCompleted)
          updated.complete();
      });
      secondReply.complete();
      await updated.future.timeout(const Duration(seconds: 3));
      expect(controller.list.map((row) => row.id), contains('100'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(ledgerRequests, 2);
    } finally {
      controller.dispose();
      dio.interceptors
        ..clear()
        ..addAll(interceptors);
      await ApiClient.instance.clearToken();
      final db =
          await openDatabase('${directory.path}/wallet_ledger_local_v1.db');
      await db.close();
      await directory.delete(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

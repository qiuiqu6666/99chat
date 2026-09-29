import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'package:flutter/foundation.dart';

import 'web_conversation_meta_snapshot.dart';

/// Web IndexedDB：持久化会话清空水位 / 已读清零标记（对齐移动端 SQLite 关键字段）。
class WebConversationMetaStore {
  WebConversationMetaStore._();

  static final WebConversationMetaStore instance = WebConversationMetaStore._();

  static const _dbName = 'xj_chat_conversation_meta_v1';
  static const _storeName = 'owner_meta';
  static const _dbVersion = 1;

  Future<IDBDatabase> _openDb() {
    final completer = Completer<IDBDatabase>();
    final request = window.indexedDB.open(_dbName, _dbVersion);
    request.onupgradeneeded = ((Event _) {
      final db = request.result as IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;
    request.onsuccess = ((Event _) {
      if (!completer.isCompleted) {
        completer.complete(request.result as IDBDatabase);
      }
    }).toJS;
    request.onerror = ((Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(request.error?.message ?? 'IndexedDB open failed'),
        );
      }
    }).toJS;
    return completer.future;
  }

  Future<WebConversationMetaSnapshot?> load(String ownerUserId) async {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) {
      return null;
    }
    try {
      final db = await _openDb();
      final txn = db.transaction(_storeName.toJS, 'readonly');
      final completion = _transactionCompletion(txn);
      final store = txn.objectStore(_storeName);
      final raw = await _request(store.get(owner.toJS));
      await completion;
      db.close();
      if (raw == null || raw.isUndefinedOrNull) {
        return null;
      }
      final encoded = (raw as JSString).toDart;
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        return WebConversationMetaSnapshot.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
      return null;
    } catch (e, st) {
      debugPrint(
        '[WebConversationMetaStore] load failed owner=$owner err=$e\n$st',
      );
      return null;
    }
  }

  Future<void> save(
    String ownerUserId,
    WebConversationMetaSnapshot snapshot,
  ) async {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) {
      return;
    }
    try {
      final db = await _openDb();
      final txn = db.transaction(_storeName.toJS, 'readwrite');
      final completion = _transactionCompletion(txn);
      final store = txn.objectStore(_storeName);
      final payload = jsonEncode(snapshot.toJson());
      await _request(store.put(payload.toJS, owner.toJS));
      await completion;
      db.close();
    } catch (e, st) {
      debugPrint(
        '[WebConversationMetaStore] save failed owner=$owner err=$e\n$st',
      );
    }
  }
}

Future<JSAny?> _request(IDBRequest request) {
  final completer = Completer<JSAny?>();
  request.onsuccess = ((Event _) {
    if (!completer.isCompleted) completer.complete(request.result);
  }).toJS;
  request.onerror = ((Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(request.error?.message ?? 'IndexedDB request failed'),
      );
    }
  }).toJS;
  return completer.future;
}

Future<void> _transactionCompletion(IDBTransaction transaction) {
  final completer = Completer<void>();
  transaction.oncomplete = ((Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  transaction.onabort = ((Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(transaction.error?.message ?? 'IndexedDB aborted'),
      );
    }
  }).toJS;
  transaction.onerror = ((Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(transaction.error?.message ?? 'IndexedDB failed'),
      );
    }
  }).toJS;
  return completer.future;
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/picker_recovery_coordinator.dart';
import 'session_identity.dart';
import '../session/session_manager.dart';

/// Initialize after bindings/plugins; recover again after authenticated identity
/// is ready. Only the coordinator consumes the native lost-data cache.
class PickerRecoveryService {
  static Future<void>? _initializing;
  static Future<void> initialize() async {
    final work = _initializing ??= _initialize();
    try {
      await work;
    } catch (_) {
      if (identical(_initializing, work)) _initializing = null;
      rethrow;
    }
  }

  static Future<void> _initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final support = await getApplicationSupportDirectory();
    PickerRecoveryCoordinator.instance.configure(
        directory: Directory(p.join(support.path, 'picker_recovery')),
        owner: () async {
          final service = SessionIdentityService.instance;
          // Registration/avatar selection is allowed without a signed-in owner.
          // Never assign a logged-out operation to a cached previous account.
          final state = SessionManager.instance.state;
          final owner = state.isLoggedOut ? '' : state.userId?.trim() ?? '';
          return PickerRecoveryOwner(owner, service.generation);
        });
  }

  static Future<void> recoverPending() async {
    await initialize();
    await PickerRecoveryCoordinator.instance.recover();
  }

  static Future<List<PickerRecoveredDraft>> listCurrentDrafts() async {
    await recoverPending();
    return PickerRecoveryCoordinator.instance.drafts(includeClaimed: true);
  }

  static Future<void> discardDraft(PickerRecoveredDraft draft) =>
      PickerRecoveryCoordinator.instance.discard(draft);
}

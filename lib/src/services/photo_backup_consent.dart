import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_identity.dart';

/// Separate, versioned backup state. Existing OS photo access can enable backup
/// silently, while an explicit Settings choice to disable it is respected.
class PhotoBackupConsent extends ChangeNotifier {
  PhotoBackupConsent._();
  static final instance = PhotoBackupConsent._();
  String _owner = '';
  bool _enabled = false;
  Future<bool>? _prompt;
  static String keyFor(String owner) => 'photo_backup_purpose_v1_$owner';

  bool get enabledForCurrentAccount =>
      _enabled &&
      _owner.isNotEmpty &&
      SessionIdentityService.instance.capture().ownerUserId == _owner;

  Future<bool> enabled(SessionIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    if (!SessionIdentityService.instance.isCurrent(identity)) return false;
    _owner = identity.ownerUserId;
    _enabled = prefs.getBool(keyFor(_owner)) == true;
    return _enabled;
  }

  Future<void> setEnabled(SessionIdentity identity, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    await prefs.setBool(keyFor(identity.ownerUserId), enabled);
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    _owner = identity.ownerUserId;
    _enabled = enabled;
    notifyListeners();
  }

  /// Silently enables backup the first time photo access is granted.
  /// An explicit Settings choice, including false, is always respected.
  Future<bool> enableIfUnset(SessionIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    if (!SessionIdentityService.instance.isCurrent(identity)) return false;
    final key = keyFor(identity.ownerUserId);
    if (prefs.containsKey(key)) {
      _owner = identity.ownerUserId;
      _enabled = prefs.getBool(key) == true;
      return _enabled;
    }
    await prefs.setBool(key, true);
    if (!SessionIdentityService.instance.isCurrent(identity)) return false;
    _owner = identity.ownerUserId;
    _enabled = true;
    notifyListeners();
    return true;
  }

  Future<bool> request(BuildContext context, {bool askAgain = false}) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }
    if (_prompt != null) {
      return _prompt!;
    }
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      return false;
    }
    // Purpose consent is controlled explicitly by the Settings switch. Picking
    // media must never show a dialog or silently enable cloud backup.
    final task = enabled(identity);
    _prompt = task;
    try {
      return await task;
    } finally {
      _prompt = null;
    }
  }
}

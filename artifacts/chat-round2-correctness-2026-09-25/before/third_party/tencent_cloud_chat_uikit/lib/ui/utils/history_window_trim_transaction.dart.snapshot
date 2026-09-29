import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';

/// One short-lived trim. UI owns the viewport pixel; the model owns membership
/// and authority. References are released at finish/rollback, including errors.
class HistoryWindowTrimTicket {
  HistoryWindowTrimTicket({
    required this.scope,
    required this.conversationID,
    required this.rawRevision,
    required this.writerRevision,
    required this.generation,
    required this.anchorMsgID,
    this.anchorSeq,
    required this.before,
    required this.after,
    required this.wasMissingOlder,
    required this.wasMissingNewer,
    required this.removedOlder,
    required this.removedNewer,
  });
  final HistoryWindowScope scope;
  final String conversationID;
  final int rawRevision;
  final int writerRevision;
  final int generation;
  final String anchorMsgID;
  final String? anchorSeq;
  List<V2TimMessage> before;
  List<V2TimMessage> after;
  final bool wasMissingOlder;
  final bool wasMissingNewer;
  final bool removedOlder;
  final bool removedNewer;
  bool committed = false;
  bool finished = false;

  void release() {
    before = const [];
    after = const [];
    finished = true;
  }
}

import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_popout_window_stub.dart'
    if (dart.library.io) 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_popout_window_io.dart'
    as impl;

class GroupLivePopoutWindow {
  static Future<void> openOrFocus(GroupLivePlayInfo playInfo) {
    return impl.openOrFocus(playInfo);
  }
}

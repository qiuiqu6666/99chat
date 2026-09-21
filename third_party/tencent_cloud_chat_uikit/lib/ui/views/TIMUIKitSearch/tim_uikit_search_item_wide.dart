import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_item.dart';

/// Kept for callers of the desktop API; both layouts now share result metrics.
class TIMUIKitSearchWideItem extends TIMUIKitSearchItem {
  TIMUIKitSearchWideItem({
    super.key,
    required super.faceUrl,
    required super.showName,
    super.avatarType,
    required super.lineOne,
    super.lineOneWidget,
    super.lineTwo,
    super.lineTwoWidget,
    super.lineOneRight,
    super.onClick,
  });
}

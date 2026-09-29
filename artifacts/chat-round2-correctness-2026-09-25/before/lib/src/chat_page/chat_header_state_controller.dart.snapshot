import 'package:flutter/foundation.dart';

/// Lightweight state for the chat header title/avatar.
///
/// The chat page can update this without rebuilding the whole TIMUIKitChat tree.
class ChatHeaderStateController extends ChangeNotifier {
  String? _conversationFaceUrl;
  String? _titleText;
  int? _memberCount;

  String? get conversationFaceUrl => _conversationFaceUrl;

  String? get titleText => _titleText;

  int? get memberCount => _memberCount;

  void setSnapshot({
    required String? conversationFaceUrl,
    required String titleText,
    int? memberCount,
    bool notify = true,
  }) {
    final normalizedFace = conversationFaceUrl?.trim();
    final normalizedTitle = titleText.trim();
    if (_conversationFaceUrl == normalizedFace &&
        _titleText == normalizedTitle &&
        _memberCount == memberCount) {
      return;
    }
    _conversationFaceUrl = normalizedFace;
    _titleText = normalizedTitle;
    _memberCount = memberCount;
    if (notify) {
      notifyListeners();
    }
  }
}

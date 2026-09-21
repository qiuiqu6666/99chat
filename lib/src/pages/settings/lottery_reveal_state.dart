import 'package:flutter/foundation.dart';
import '../../api/api_client.dart';

/// In-memory reveal state shared by preview and full-screen cards.
class LotteryRevealState extends ChangeNotifier {
  bool enabled = false;
  String? _revealedIssue;

  bool isHidden(String issue) => enabled && _revealedIssue != issue;

  void toggle() {
    enabled = !enabled;
    _revealedIssue = null;
    notifyListeners();
  }

  void reveal(String issue) {
    _revealedIssue = issue;
    notifyListeners();
  }
}

final _states = <(String, String?, String, String), LotteryRevealState>{};

LotteryRevealState lotteryRevealState(String machineCode) =>
    _states.putIfAbsent((
      ApiClient.instance.authenticatedUserId,
      ApiClient.instance.token,
      ApiClient.resolveBaseUrl(),
      machineCode
    ), LotteryRevealState.new);

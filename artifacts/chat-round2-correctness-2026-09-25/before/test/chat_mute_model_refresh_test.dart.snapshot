import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  TUIChatSeparateViewModel createModel() {
    final model = TUIChatSeparateViewModel()
      ..conversationID = 'group_mute_refresh'
      ..groupInfo =
          V2TimGroupInfo(groupID: 'group_mute_refresh', groupType: 'Public', isAllMuted: false)
      ..selfMemberInfo = V2TimGroupMemberFullInfo(
          userID: 'mute_self', role: 200, muteUntil: 0);
    addTearDown(model.dispose);
    return model;
  }

  test('authoritative personal mute and unmute notify the mounted consumer',
      () async {
    final model = createModel();
    final observed = <int>[];
    model.addListener(() => observed.add(model.selfMemberInfo!.muteUntil!));
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: until);
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: 0);
    expect(observed, [until, 0]);
  });

  test('all mute toggles notify even when personal mute value stays identical',
      () async {
    final model = createModel();
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: 0, isAllMuted: true);
    final permanent = model.selfMemberInfo!.muteUntil!;
    final observed = <bool>[];
    model.addListener(() => observed.add(model.groupInfo!.isAllMuted!));
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: permanent, isAllMuted: false);
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: permanent, isAllMuted: true);
    expect(observed, [false, true]);
  });

  test('turning off all mute clears its synthetic personal deadline', () async {
    final model = createModel();
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: 0, isAllMuted: true);
    expect(model.selfMemberInfo!.muteUntil, greaterThan(0));
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: 0, isAllMuted: false);
    expect(model.groupInfo!.isAllMuted, isFalse);
    expect(model.selfMemberInfo!.muteUntil, 0);
  });

  test('identical snapshots avoid redundant notifications', () async {
    final model = createModel();
    var notifications = 0;
    model.addListener(() => notifications++);
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: 0);
    await model.updateSelfMuteStatus(
        groupID: 'group_mute_refresh', muteUntil: 0);
    expect(notifications, 0);
  });
}

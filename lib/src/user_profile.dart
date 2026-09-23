import 'package:tencent_cloud_chat_demo/src/widgets/star_burst_button.dart';
import 'dart:async';
import 'dart:convert';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/platform/clipboard_guard.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/privileged_game_user_service.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/user_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/block_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/pages/chat_background_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/moments/moments_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/starred_friend_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/user_api_error_message.dart';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/tencent_page.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/pages/profile_nickname_edit_page.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/contact_card_message.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_card_send_confirm_dialog.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/friend_became_friends_message.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_demo/utils/commonUtils.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_qr_add_policy.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_launcher.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/profile_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_profile_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitProfile/profile_widget.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitProfile/widget/tim_uikit_profile_widget.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/user_profile/user_profile_game_admin_panel.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/user_profile/user_profile_game_privilege_side_column.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/user_profile/profile_page_keyboard.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/user_profile/user_profile_game_ledger_floating_entry.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/user_profile/user_profile_game_ledger_sheet.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_share_picker_page.dart';
import 'package:tencent_cloud_chat_demo/utils/profile_page_nav.dart';
import 'package:tencent_cloud_chat_demo/utils/group_privacy_guard.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/pages/complaint/complaint_reason_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/common_group_chats_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/common_group_chats_service.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_esc_back.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_column_scope.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_member_join_meta_section.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_add_source.dart';
import 'package:tencent_cloud_chat_demo/utils/group_member_join_meta.dart';
import 'package:tencent_cloud_chat_demo/utils/group_member_join_meta_loader.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';

class UserProfileRouteResult {
  static const String friendDeleted = 'friendDeleted';
}

enum _WideProfileDetail {
  none,
  commonGroups,
  moments,
  chatBackground,
}

class UserProfile extends StatefulWidget {
  final String userID;
  final ValueChanged<V2TimConversation>? onClickSendMessage;
  final ValueChanged<String>? onRemarkUpdate;
  final String? addSource;
  final String? initialAvatarUrl;

  /// 群入口打开资料时传入，用于 can-view 二次校验与资料 API `viewGroupId`。
  final String? groupId;

  /// 桌面壳内打开时提供关闭回调（返回会话列表右侧原内容）。
  final VoidCallback? onClose;

  const UserProfile({
    Key? key,
    required this.userID,
    this.onRemarkUpdate,
    this.onClickSendMessage,
    this.addSource,
    this.initialAvatarUrl,
    this.groupId,
    this.onClose,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => UserProfileState();
}

class UserProfileState extends State<UserProfile> {
  static const int _addFriendPendingApprovalCode = 30539;

  final TIMUIKitProfileController _timuiKitProfileController =
      TIMUIKitProfileController();
  final V2TIMManager sdkInstance = TIMUIKitCore.getSDKInstance();
  String? newUserMARK;
  bool _addingFriend = false;
  bool _deletingFriend = false;
  bool _togglingBlackList = false;
  FriendRelation? _friendRelation;
  bool _isPrivilegedGameUser = PrivilegedGameUserService.instance.isPrivileged;
  String _ledgerDisplayName = '';
  bool _publishingProfile = false;
  bool _profileEnrichmentInFlight = false;
  bool _blockMyMoments = false;
  bool _hideTheirMoments = false;
  int _commonGroupCount = 0;
  GroupMemberRecord? _groupJoinMetaRecord;

  /// Web / 桌面右栏内嵌子页（保持左侧导航 + 会话列表）。
  _WideProfileDetail _wideDetail = _WideProfileDetail.none;
  String? _wideMomentsAuthorId;
  String? _wideMomentsName;
  String? _wideMomentsAvatar;
  String? _wideBgConversationId;
  String? _wideBgConversationName;

  bool get _isDesktopFormFactor =>
      TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;

  void _closeWideDetail() {
    if (_wideDetail == _WideProfileDetail.none) {
      return;
    }
    setState(() {
      _wideDetail = _WideProfileDetail.none;
      _wideMomentsAuthorId = null;
      _wideMomentsName = null;
      _wideMomentsAvatar = null;
      _wideBgConversationId = null;
      _wideBgConversationName = null;
    });
  }

  void _openWideCommonGroups() {
    setState(() => _wideDetail = _WideProfileDetail.commonGroups);
  }

  void _openWideMoments({
    required String authorId,
    String? profileName,
    String? profileAvatarUrl,
  }) {
    setState(() {
      _wideDetail = _WideProfileDetail.moments;
      _wideMomentsAuthorId = authorId;
      _wideMomentsName = profileName;
      _wideMomentsAvatar = profileAvatarUrl;
    });
  }

  void _openWideChatBackground({
    required String conversationId,
    required String conversationName,
  }) {
    setState(() {
      _wideDetail = _WideProfileDetail.chatBackground;
      _wideBgConversationId = conversationId;
      _wideBgConversationName = conversationName;
    });
  }

  Future<void> _loadFriendRelation() async {
    if (widget.userID.trim().isEmpty) {
      if (mounted) {
        setState(() => _friendRelation = null);
      }
      return;
    }
    try {
      final relation =
          await MeFriendApi.instance.tryFetchRelation(widget.userID.trim());
      if (!mounted) return;
      setState(() => _friendRelation = relation);
      final imType = await MeFriendApi.instance
          .imFriendCheckResultType(widget.userID.trim());
      _getProfileModel()?.applyFriendCheckResultType(imType);
      unawaited(_loadMomentsPrivacy());
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendRelation = null);
      unawaited(_loadMomentsPrivacy());
    }
  }

  void _toastProcessing() {
    ToastUtils.toast(AppI18n.of(context).t(
      zhHans: '操作处理中，请稍后',
      zhHant: '操作處理中，請稍後',
      en: 'Processing. Please wait.',
      ja: '処理中です。しばらくお待ちください',
      ko: '처리 중입니다. 잠시만 기다려 주세요',
    ));
  }

  TUIProfileViewModel? _getProfileModel() {
    try {
      return _timuiKitProfileController.model;
    } catch (_) {
      return null;
    }
  }

  bool _resolveIsFriend() {
    final relation = _friendRelation;
    if (relation != null) {
      return relation.canMessage;
    }
    return false;
  }

  bool _resolveInMyFriendList() {
    final relation = _friendRelation;
    if (relation != null) {
      return relation.inMyFriendList;
    }
    return false;
  }

  V2TimFriendInfo _applyBackendProfile(
    V2TimFriendInfo info, {
    String? nickname,
    String? avatarUrl,
    String? remark,
  }) {
    final profile = info.userProfile ?? V2TimUserFullInfo(userID: info.userID);
    final nick = nickname?.trim();
    if (nick != null && nick.isNotEmpty) {
      profile.nickName = nick;
    }
    final avatar = avatarUrl?.trim();
    if (avatar != null && avatar.isNotEmpty) {
      // Open-path stability: fill-only. Keep a usable current face so
      // didGetFriendInfo does not swap CDN hosts and flash the header.
      // Real avatar rotations stay on profile-refresh buses.
      if (UserAvatarHelper.shouldReplaceProfileFaceUrl(
        current: profile.faceUrl,
        incoming: avatar,
      )) {
        profile.faceUrl = UserAvatarHelper.usableAvatarOrEmpty(avatar);
      }
    }
    final r = remark;
    if (r != null) {
      info.friendRemark = r.trim();
    }
    info.userProfile = profile;
    return info;
  }

  void _syncDisplayNameFromFriendInfo(V2TimFriendInfo info) {
    final userId = info.userID.trim();
    if (userId.isEmpty) {
      return;
    }
    DisplayNameStore.instance.applyImFriendShowName(
      userID: userId,
      imRemark: info.friendRemark ?? '',
      imNickName: info.userProfile?.nickName ?? '',
    );
  }

  /// Publish the freshly fetched profile into the conversation list as well
  /// as the profile/chat-header caches. The IM conversation snapshot may keep
  /// an old showName/faceUrl until the next SDK conversation callback.
  void _publishConversationProfile(V2TimFriendInfo info) {
    final userId = info.userID.trim();
    if (userId.isEmpty) return;
    final resolvedRemark = FriendDisplayName.resolveFriendRemark(
      userId: userId,
      imRemark: info.friendRemark,
      friendList: serviceLocator<TUIFriendShipViewModel>().friendList,
    );
    final showName = resolvedRemark.isNotEmpty ? resolvedRemark : null;
    final avatar =
        UserAvatarHelper.usableAvatarOrEmpty(info.userProfile?.faceUrl);
    final conversationId = 'c2c_$userId';

    DisplayNameStore.instance.applyImFriendShowName(
      userID: userId,
      imRemark: info.friendRemark ?? '',
      imNickName: info.userProfile?.nickName ?? '',
    );
    unawaited(
      ConversationSyncService.instance.applyConversationMetadataPatch(
        conversationID: conversationId,
        showName: showName,
        faceUrl: avatar.isEmpty ? null : avatar,
        remoteAuthority: true,
      ),
    );
    // This page is the writer for the profile it just enriched. The bus
    // listener is for external changes and must not immediately reload this
    // same page again.
    _publishingProfile = true;
    try {
      PeerProfileRefreshBus.instance.notify(userId);
    } finally {
      _publishingProfile = false;
    }
  }

  Future<V2TimFriendInfo?> _enrichFriendInfoFromBackend(
    V2TimFriendInfo? friendInfo,
  ) async {
    if (_profileEnrichmentInFlight) {
      return friendInfo;
    }
    _profileEnrichmentInFlight = true;
    try {
      return await _enrichFriendInfoFromBackendImpl(friendInfo);
    } finally {
      _profileEnrichmentInFlight = false;
    }
  }

  Future<V2TimFriendInfo?> _enrichFriendInfoFromBackendImpl(
    V2TimFriendInfo? friendInfo,
  ) async {
    final userId = widget.userID.trim();
    if (userId.isEmpty) {
      return friendInfo;
    }

    var info = friendInfo ?? V2TimFriendInfo(userID: userId);
    info.userProfile ??= V2TimUserFullInfo(userID: userId);

    final friendRecord = await MeFriendApi.instance.cachedByUserId(userId);
    if (friendRecord != null) {
      info = _applyBackendProfile(
        info,
        nickname: friendRecord.friendNickname,
        avatarUrl: friendRecord.friendAvatarUrl,
        remark: friendRecord.remark,
      );
    }

    final remote = await UserApi.instance.tryFetchUserById(userId);
    if (remote != null) {
      info = _applyBackendProfile(
        info,
        nickname: remote.nickname,
        avatarUrl: remote.avatarUrl,
      );
      if (friendRecord != null) {
        await UserProfileLocalService.instance.saveFriendRecord(
          friendRecord.copyWith(
            friendNickname: remote.nickname.trim().isNotEmpty
                ? remote.nickname.trim()
                : friendRecord.friendNickname,
            friendAvatarUrl: remote.avatarUrl?.trim().isNotEmpty == true
                ? remote.avatarUrl!.trim()
                : friendRecord.friendAvatarUrl,
          ),
        );
      } else {
        await UserProfileLocalService.instance.saveBackendProfile(
          userId: userId,
          nickname: remote.nickname,
          avatarUrl: remote.avatarUrl,
          avatarVersion: remote.avatarVersion,
        );
      }
    } else if (friendRecord != null) {
      await UserProfileLocalService.instance.saveFriendRecord(friendRecord);
    }

    // TIM/网络仍无可用头像时，补本地资料与 IM 好友列表（与聊天顶栏同源）。
    final currentFace =
        UserAvatarHelper.usableAvatarOrEmpty(info.userProfile?.faceUrl);
    if (currentFace.isEmpty) {
      final local = await UserProfileLocalService.instance.read(userId);
      final localAvatar =
          UserAvatarHelper.usableAvatarOrEmpty(local?.avatarUrl);
      String? friendListAvatar;
      try {
        final friendship = serviceLocator<TUIFriendShipViewModel>();
        friendListAvatar = UserAvatarHelper.usableAvatarOrEmpty(
          ConversationFaceUrl.resolve(
            userId: userId,
            conversationFaceUrl: null,
            friendList: friendship.friendList,
          ),
        );
      } catch (_) {
        friendListAvatar = '';
      }
      final fallback =
          localAvatar.isNotEmpty ? localAvatar : (friendListAvatar ?? '');
      if (fallback.isNotEmpty) {
        info = _applyBackendProfile(info, avatarUrl: fallback);
      }
    }

    _syncDisplayNameFromFriendInfo(info);
    _publishConversationProfile(info);
    return info;
  }

  Future<void> _handleDeleteFriend() async {
    if (_deletingFriend) {
      _toastProcessing();
      return;
    }
    _deletingFriend = true;
    try {
      await MeFriendApi.instance.deleteFriend(widget.userID);
      try {
        await serviceLocator<ConversationService>().deleteConversation(
          conversationID: 'c2c_${widget.userID}',
        );
      } catch (_) {}
      try {
        final friendship = serviceLocator<TUIFriendShipViewModel>();
        await friendship.loadContactListData();
        await friendship.loadContactApplicationData();
      } catch (_) {}
      ConversationRefreshBus.instance.requestRefresh(
        reason: 'friend_deleted',
      );
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '好友删除成功',
        zhHant: '好友刪除成功',
        en: 'Friend removed',
        ja: '友達を削除しました',
        ko: '친구 삭제 완료',
      ));
      if (mounted) {
        Navigator.of(context).pop(UserProfileRouteResult.friendDeleted);
      }
    } on DioError catch (e) {
      ToastUtils.toast(UserApiErrorMessage.fromFriendRequest(e));
    } catch (_) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '好友删除失败',
        zhHant: '好友刪除失敗',
        en: 'Failed to remove friend',
        ja: '友達の削除に失敗',
        ko: '친구 삭제 실패',
      ));
    } finally {
      _deletingFriend = false;
    }
  }

  String _resolvedFriendRemark({String? imRemark}) {
    return FriendDisplayName.resolveFriendRemark(
      userId: widget.userID,
      imRemark: imRemark,
      friendList: serviceLocator<TUIFriendShipViewModel>().friendList,
    );
  }

  String _friendRemarkForEdit() {
    final friendInfo = _getProfileModel()?.userProfile?.friendInfo;
    return _resolvedFriendRemark(imRemark: friendInfo?.friendRemark);
  }

  String _friendRemarkHintBaseline() {
    final model = _getProfileModel();
    final friendInfo = model?.userProfile?.friendInfo;
    final nickName = friendInfo?.userProfile?.nickName?.trim() ?? '';
    if (nickName.isNotEmpty) {
      return nickName;
    }
    final showName = model?.userProfile?.conversation?.showName?.trim() ?? '';
    if (showName.isNotEmpty) {
      return showName;
    }
    return widget.userID;
  }

  void _applyFriendRemarkLocally(String remark) {
    final text = remark.trim();
    newUserMARK = text;
    final model = _getProfileModel();
    final friendInfo = model?.userProfile?.friendInfo;
    if (friendInfo != null) {
      friendInfo.friendRemark = text;
    }
    // 统一打通好友备注 → 会话列表 showName / DisplayNameStore / RefreshBus。
    // MeFriendApi.updateRemark 内也会走同一路径；此处再调一次保证 UIKit-only 路径也刷新。
    unawaited(
      FriendSyncService.instance.publishFriendRemarkDisplayName(
        friendUserId: widget.userID,
        remark: text,
      ),
    );
    unawaited(
      UserProfileLocalService.instance.saveFriendRemark(
        userId: widget.userID,
        remark: text,
      ),
    );
    widget.onRemarkUpdate?.call(text);
  }

  Future<void> _openFriendRemarkEdit(BuildContext context) async {
    final model = _getProfileModel();
    final friendInfo = model?.userProfile?.friendInfo;
    final faceUrl =
        TencentUtils.checkString(friendInfo?.userProfile?.faceUrl) ??
            (widget.initialAvatarUrl ?? '');
    final result = await ProfileNicknameEditPage.pushFriendRemark(
      context,
      initialRemark: _friendRemarkForEdit(),
      hintBaseline: _friendRemarkHintBaseline(),
      avatarFaceUrl: faceUrl,
      avatarShowName: _friendRemarkHintBaseline(),
      onSave: (String remark) async {
        final res = await _timuiKitProfileController
            .updateRemarks(
              widget.userID,
              remark.trim(),
            )
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () => V2TimCallback(
                code: -1,
                desc: 'REQUEST_TIMEOUT',
              ),
            );
        if (res.code != 0) {
          ToastUtils.toast(
            DioErrorMessage.sanitizeUserText(
              res.desc,
              fallback: AppI18n.of(context).t(
                zhHans: '保存失败',
                zhHant: '儲存失敗',
                en: 'Save failed',
                ja: '保存に失敗',
                ko: '저장 실패',
              ),
            ),
          );
          return false;
        }
        _applyFriendRemarkLocally(remark);
        return true;
      },
    );
    if (result != null && mounted) {
      setState(() {
        newUserMARK = result;
      });
    }
  }

  Future<void> _handleAddFriend() async {
    if (_addingFriend) {
      _toastProcessing();
      return;
    }
    if (isQrAddSource(widget.addSource)) {
      try {
        final check = await UserApi.instance.checkAddFriend(
          targetUserId: widget.userID,
          channel: AddFriendCheckChannel.qr,
        );
        if (!check.allowed) {
          ToastUtils.toast(UserApiErrorMessage.fromAddFriendReasonCode(
            check.reason,
            fallback: qrAddNotAllowedText(),
          ));
          return;
        }
      } on DioError catch (e) {
        ToastUtils.toast(UserApiErrorMessage.fromFriendRequest(e));
        return;
      }
    }
    _addingFriend = true;
    try {
      final res = await _timuiKitProfileController.addFriend(
        widget.userID,
        addSource: widget.addSource,
      );
      if (res == null) {
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '好友添加失败',
          zhHant: '好友新增失敗',
          en: 'Failed to add friend',
          ja: '友達の追加に失敗',
          ko: '친구 추가 실패',
        ));
        return;
      }
      final resultCode = res.resultCode;
      if (resultCode == 0) {
        final friendInfo = _getProfileModel()?.userProfile?.friendInfo;
        final profile = friendInfo?.userProfile;
        await FriendSyncService.instance.onBecameFriends(
          peerUserId: widget.userID,
          nickname: profile?.nickName,
          avatarUrl: profile?.faceUrl,
          remark: friendInfo?.friendRemark ?? '',
          reason: 'friend_add_success',
        );
        await FriendBecameFriendsNotifier.notifyIfBecameFriends(
          peerUserId: widget.userID,
        );
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '好友添加成功',
          zhHant: '好友新增成功',
          en: 'Friend added',
          ja: '友達を追加しました',
          ko: '친구 추가 완료',
        ));
        _timuiKitProfileController.loadData(widget.userID);
        await _loadFriendRelation();
        if (mounted) {
          setState(() {});
        }
        return;
      }
      if (resultCode == _addFriendPendingApprovalCode) {
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '好友申请已发送',
          zhHant: '好友申請已發送',
          en: 'Friend request sent',
          ja: '友だち申請を送信しました',
          ko: '친구 요청을 보냈습니다',
        ));
        return;
      }
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '好友添加失败',
        zhHant: '好友新增失敗',
        en: 'Failed to add friend',
        ja: '友達の追加に失敗',
        ko: '친구 추가 실패',
      ));
    } catch (_) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '好友添加失败',
        zhHant: '好友新增失敗',
        en: 'Failed to add friend',
        ja: '友達の追加に失敗',
        ko: '친구 추가 실패',
      ));
    } finally {
      _addingFriend = false;
    }
  }

  Future<void> _handleToggleBlackList({bool? shouldAdd}) async {
    if (ProfilePageNav.isSelfUser(widget.userID)) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '不能拉黑自己',
        zhHant: '不能拉黑自己',
        en: 'You cannot block yourself',
        ja: '自分をブロックすることはできません',
        ko: '자신을 차단할 수 없습니다',
      ));
      return;
    }
    if (_togglingBlackList) {
      _toastProcessing();
      return;
    }
    final add = shouldAdd ?? !BlockLocalStore.instance.isBlocked(widget.userID);
    if (add) {
      final confirmed = await AppDialog.confirm(
        title: AppI18n.of(context).t(
          zhHans: '加入黑名单',
          zhHant: '加入黑名單',
          en: 'Block User',
          ja: 'ブロック',
          ko: '차단',
        ),
        message: AppI18n.of(context).t(
          zhHans: '加入后双方将无法再添加好友。若你们已是好友，通讯录关系会保留。',
          zhHant: '加入後雙方將無法再添加好友。若你們已是好友，通訊錄關係會保留。',
          en: 'After blocking, neither of you can send friend requests. Existing contacts stay in the address book.',
          ja: 'ブロック後、双方とも友だち申請できなくなります。既存の連絡先は残ります。',
          ko: '차단 후 서로 친구 요청을 보낼 수 없습니다. 기존 주소록 관계는 유지됩니다.',
        ),
        confirmText: AppI18n.of(context).t(
          zhHans: '确定',
          zhHant: '確定',
          en: 'Confirm',
          ja: '確定',
          ko: '확인',
        ),
        cancelText: AppI18n.of(context).t(
          zhHans: '取消',
          zhHant: '取消',
          en: 'Cancel',
          ja: 'キャンセル',
          ko: '취소',
        ),
        destructive: true,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    _togglingBlackList = true;
    try {
      if (add) {
        await BlockLocalStore.instance.block(widget.userID);
      } else {
        await BlockLocalStore.instance.unblock(widget.userID);
      }
      ToastUtils.toast(add
          ? AppI18n.of(context).t(
              zhHans: '已加入黑名单',
              zhHant: '已加入黑名單',
              en: 'Blocked',
              ja: 'ブロックしました',
              ko: '차단됨',
            )
          : AppI18n.of(context).t(
              zhHans: '已移出黑名单',
              zhHant: '已移出黑名單',
              en: 'Unblocked',
              ja: 'ブロック解除しました',
              ko: '차단 해제됨',
            ));
      if (mounted) {
        setState(() {});
      }
    } on DioError catch (e) {
      ToastUtils.toast(UserApiErrorMessage.fromBlock(e));
    } catch (_) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '操作失败，请重试',
        zhHant: '操作失敗，請重試',
        en: 'Operation failed. Please try again.',
        ja: '操作に失敗しました。もう一度お試しください。',
        ko: '작업에 실패했습니다. 다시 시도해 주세요.',
      ));
    } finally {
      _togglingBlackList = false;
    }
  }

  Future<ContactCardMessage> _buildShareContactMessage() async {
    final userInfo = _getProfileModel()?.userProfile?.friendInfo?.userProfile;
    bool? allowViaCard;
    try {
      final selfUserId =
          serviceLocator<TUISelfInfoViewModel>().loginInfo?.userID ?? '';
      if (widget.userID == selfUserId) {
        final privacy = await UserApi.instance.fetchPrivacy();
        allowViaCard = privacy.allowViaCard;
      } else {
        final remote = await UserApi.instance.fetchUserPrivacy(
          widget.userID,
        );
        allowViaCard = remote?.allowViaCard;
      }
    } catch (_) {
      allowViaCard = null;
    }
    return ContactCardMessage(
      businessID: kContactCardBusinessID,
      version: 1,
      userID: widget.userID,
      nickName: _getDisplayName(userInfo),
      faceUrl: userInfo?.faceUrl ?? "",
      selfSignature: userInfo?.selfSignature ?? "",
      allowViaCard: allowViaCard,
    );
  }

  Future<_ShareTarget?> _showShareContactPicker(
    BuildContext context,
    TUITheme theme,
  ) async {
    final target = await ConversationSharePickerPage.open(
      context,
      theme: theme,
      groupCollector: (groupInfo) {
        final groupID = groupInfo?.groupID ?? '';
        return !groupID.contains('im_discuss_');
      },
    );
    if (target == null) {
      return null;
    }
    return _ShareTarget(userID: target.userID, groupID: target.groupID);
  }

  Future<void> _handleShareContact(BuildContext context, TUITheme theme) async {
    final target = await _showShareContactPicker(context, theme);
    if (target == null) {
      return;
    }
    final card = await _buildShareContactMessage();
    final allowed = await resolveContactCardAllowViaCard(
      targetUserId: widget.userID,
      embeddedAllowViaCard: card.allowViaCard,
    );
    if (!allowed) {
      final selfUserId =
          serviceLocator<TUISelfInfoViewModel>().loginInfo?.userID ?? '';
      ToastUtils.toast(
        widget.userID == selfUserId
            ? AppI18n.of(context).t(
                zhHans: '你未开放通过名片添加，请在「添加我的方式」中开启',
                zhHant: '你未開放透過名片新增，請在「新增我的方式」中開啟',
                en: 'You have not enabled adding via contact card. Enable it in Add Me settings.',
                ja: '名刺での追加が無効です。「追加方法」で有効にしてください。',
                ko: '명함으로 추가가 비활성화되어 있습니다. \'나를 추가하는 방법\'에서 켜 주세요.',
              )
            : AppI18n.of(context).t(
                zhHans: '对方未开放通过名片添加',
                zhHant: '對方未開放透過名片新增',
                en: 'They have not enabled adding via contact card',
                ja: '相手は名刺での追加を許可していません',
                ko: '상대가 명함 추가를 허용하지 않음',
              ),
      );
      return;
    }
    final receiver = target.userID.trim();
    final groupID = target.groupID.trim();
    if (receiver.isEmpty && groupID.isEmpty) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '分享失败',
        zhHant: '分享失敗',
        en: 'Share failed',
        ja: '共有に失敗',
        ko: '공유 실패',
      ));
      return;
    }

    var conversationName = receiver.isNotEmpty ? receiver : groupID;
    var conversationFaceUrl = '';
    try {
      final conversationID = receiver.isNotEmpty
          ? (receiver.startsWith('c2c_') ? receiver : 'c2c_$receiver')
          : (groupID.startsWith('group_') ? groupID : 'group_$groupID');
      final conversationRes = await sdkInstance
          .getConversationManager()
          .getConversation(conversationID: conversationID);
      final conversation = conversationRes.data;
      final resolvedName = conversation?.showName?.trim() ?? '';
      if (resolvedName.isNotEmpty) {
        conversationName = resolvedName;
      }
      conversationFaceUrl = ConversationFaceUrl.resolve(
        userId: receiver,
        conversationFaceUrl: conversation?.faceUrl,
        isGroup: groupID.isNotEmpty,
        groupId: groupID,
      );
    } catch (_) {
      // The target ID still provides a stable fallback for the confirmation.
    }
    if (!context.mounted) {
      return;
    }
    final confirmed = await showContactCardSendConfirm(
      context: context,
      theme: theme,
      card: card,
      conversationName: conversationName,
      conversationFaceUrl: conversationFaceUrl,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    final messageData = jsonEncode(card.toJson());
    final createMessageRes = await sdkInstance
        .getMessageManager()
        .createCustomMessage(data: messageData);
    final messageID = createMessageRes.data?.id;
    if (createMessageRes.code != 0 || messageID == null || messageID.isEmpty) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '分享失败',
        zhHant: '分享失敗',
        en: 'Share failed',
        ja: '共有に失敗',
        ko: '공유 실패',
      ));
      return;
    }
    final sent = await ChatExternalMessageSender.sendCreatedMessage(
      messageInfo: createMessageRes.data?.messageInfo,
      receiverUserId: receiver,
      groupId: groupID,
      reason: 'contact_card_share_sent',
    );
    if (sent) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '联系人已分享',
        zhHant: '聯絡人已分享',
        en: 'Contact shared',
        ja: '連絡先を共有しました',
        ko: '연락처 공유됨',
      ));
      return;
    }
    ToastUtils.toast(AppI18n.of(context).t(
      zhHans: '分享失败',
      zhHant: '分享失敗',
      en: 'Share failed',
      ja: '共有に失敗',
      ko: '공유 실패',
    ));
  }

  Future<void> _handleMoreAction(String value) async {
    switch (value) {
      case "toggleBlackList":
        await _handleToggleBlackList();
        break;
      case "deleteFriend":
        await _handleDeleteFriend();
        break;
      case "addFriend":
        await _handleAddFriend();
        break;
    }
  }

  Future<void> _handleToggleStarFriend() async {
    final starred = StarredFriendProvider.shared;
    final isStarred = starred.isStarred(widget.userID);
    try {
      if (isStarred) {
        await starred.unstar(widget.userID);
      } else {
        await starred.star(widget.userID);
      }
      if (mounted) {
        setState(() {});
      }
    } on DioError catch (e) {
      ToastUtils.toast(UserApiErrorMessage.fromStarredFriend(e));
    } catch (_) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '操作失败',
        zhHant: '操作失敗',
        en: 'Operation failed',
        ja: '操作に失敗',
        ko: '작업 실패',
      ));
    }
  }

  String _getDisplayName(V2TimUserFullInfo? userInfo) {
    return TencentUtils.checkString(userInfo?.nickName) ??
        TencentUtils.checkString(userInfo?.userID) ??
        "";
  }

  Widget? _buildGenderIcon(int? gender) {
    switch (gender) {
      case 1:
        return Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 1),
          child: Icon(
            Icons.male_rounded,
            size: 18,
            color: const Color(0xFF4DA3FF),
          ),
        );
      case 2:
        return Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 1),
          child: Icon(
            Icons.female_rounded,
            size: 18,
            color: const Color(0xFFFF6B9D),
          ),
        );
      default:
        return null;
    }
  }

  Widget _buildProfileAvatar(
    V2TimUserFullInfo? userInfo,
    TUITheme theme, {
    double size = 72,
    BorderRadius? borderRadius,
  }) {
    final name = _getDisplayName(userInfo);
    final faceUrl = TencentUtils.checkString(userInfo?.faceUrl) ?? "";
    final userId = ChatIdFormat.rawUserUid(
      userInfo?.userID?.trim().isNotEmpty == true
          ? userInfo!.userID!
          : widget.userID,
    );
    final avatarVersion =
        UserProfileLocalService.instance.readCached(userId)?.avatarVersion ?? 0;
    final backendThumb =
        UserProfileLocalService.instance.readCached(userId)?.avatarUrl.trim() ??
            '';
    final displayThumb = backendThumb.isNotEmpty
        ? backendThumb
        : (faceUrl.isNotEmpty ? faceUrl : (widget.initialAvatarUrl ?? ''));
    return Avatar(
      faceUrl: displayThumb,
      showName: name,
      type: 1,
      borderRadius: borderRadius ?? BorderRadius.circular(size / 2),
      isShowBigWhenClick: displayThumb.isNotEmpty,
      previewUrlResolver: userId.isEmpty
          ? null
          : () async {
              final result =
                  await UserApi.instance.fetchUserAvatarPreview(userId);
              return result.previewUrl;
            },
      // Version 0 means no authoritative backend version yet. Keep the URL
      // cache key so the avatar shown in the contact list can be reused on the
      // profile first frame instead of flashing a placeholder.
      avatarCacheKey: userId.isEmpty || avatarVersion <= 0
          ? null
          : 'avatar|user|$userId|$avatarVersion|thumb',
      previewCacheKey:
          userId.isEmpty ? null : 'avatar|user|$userId|$avatarVersion|preview',
    );
  }

  Widget _buildMobileProfileHeader(
      V2TimUserFullInfo? userInfo, TUITheme theme) {
    const avatarSize = 78.0;
    final name = _getDisplayName(userInfo);
    final userID = userInfo?.userID ?? "";
    final displayUserId = ChatIdFormat.display(userID);
    final signature = TencentUtils.checkString(userInfo?.selfSignature) ??
        AppI18n.of(context).t(
          zhHans: '对方什么都没有写',
          zhHant: '對方什麼都沒有寫',
          en: 'No bio yet',
          ja: '自己紹介はありません',
          ko: '소개 없음',
        );
    final backgroundColor =
        theme.conversationItemBgColor ?? AppColors.card(dark: false);
    final isDarkBackground =
        ThemeData.estimateBrightnessForColor(backgroundColor) ==
            Brightness.dark;
    final titleColor =
        theme.darkTextColor ?? AppColors.text(dark: isDarkBackground);
    final weakTextColor =
        theme.weakTextColor ?? AppColors.subText(dark: isDarkBackground);
    final accountBgColor =
        isDarkBackground ? AppTokens.surfaceAltDark : AppTokens.surfaceAltLight;
    final accountBorderColor =
        isDarkBackground ? Colors.transparent : AppTokens.borderLight;
    final genderIcon = _buildGenderIcon(userInfo?.gender);
    return Container(
      width: double.infinity,
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(20, 22, 16, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: _buildProfileAvatar(
              userInfo,
              theme,
              size: avatarSize,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (genderIcon != null) genderIcon,
                  ],
                ),
                if (displayUserId.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () async {
                        await ClipboardGuard.copy(displayUserId);
                        ToastUtils.toast(AppI18n.of(context).t(
                          zhHans: '用户ID已复制',
                          zhHant: '使用者 ID 已複製',
                          en: 'User ID copied',
                          ja: 'ユーザーIDをコピーしました',
                          ko: '사용자 ID 복사됨',
                        ));
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accountBgColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: accountBorderColor),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                              child: Text(
                            displayUserId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: weakTextColor,
                              fontSize: 14,
                            ),
                          )),
                          const SizedBox(width: 8),
                          Icon(Icons.copy_outlined,
                              size: 15, color: weakTextColor)
                        ]),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  signature,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: weakTextColor,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (!ProfilePageNav.isSelfUser(widget.userID))
            ListenableBuilder(
              listenable: StarredFriendProvider.shared,
              builder: (context, _) {
                final starred =
                    StarredFriendProvider.shared.isStarred(widget.userID);
                return StarBurstButton(
                  starred: starred,
                  tooltip: AppI18n.of(context).t(
                      zhHans: starred ? '取消特别关注' : '设为特别关注',
                      zhHant: starred ? '取消特別關注' : '設為特別關注',
                      en: starred ? 'Unstar' : 'Star',
                      ja: 'スター',
                      ko: '즐겨찾기'),
                  onPressed: _handleToggleStarFriend,
                  backgroundColor: accountBgColor,
                  color: starred ? AppTokens.warning : weakTextColor,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Color textColor,
    required VoidCallback onTap,
    required Color background,
  }) {
    return Expanded(
        child: Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
            child: Column(children: [
              Icon(icon, color: iconColor, size: 25),
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: textColor, fontSize: 14, height: 1.3)),
            ])),
      ),
    ));
  }

  Widget _buildMobileActionArea(
      BuildContext context, V2TimConversation conversation, TUITheme theme) {
    final i18n = AppI18n.of(context);
    final card = theme.conversationItemBgColor ?? Colors.white;
    final text = theme.darkTextColor ?? Colors.black87;
    final canCall = !PlatformUtils().isWeb && !PlatformUtils().isDesktop;
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
        child: Row(children: [
          if (canCall) ...[
            _buildQuickActionItem(
                icon: Icons.call_rounded,
                label: i18n.t(
                    zhHans: '语音通话',
                    zhHant: '語音通話',
                    en: 'Voice Call',
                    ja: '音声通話',
                    ko: '음성 통화'),
                iconColor: text,
                textColor: text,
                background: card,
                onTap: () => _itemClick('audioCall', context, conversation)),
            const SizedBox(width: 8),
            _buildQuickActionItem(
                icon: Icons.videocam_rounded,
                label: i18n.t(
                    zhHans: '视频通话',
                    zhHant: '視訊通話',
                    en: 'Video Call',
                    ja: 'ビデオ通話',
                    ko: '영상 통화'),
                iconColor: text,
                textColor: text,
                background: card,
                onTap: () => _itemClick('videoCall', context, conversation)),
            const SizedBox(width: 8),
          ],
          _buildQuickActionItem(
              icon: Icons.chat_bubble_rounded,
              label: i18n.t(
                  zhHans: '发送消息',
                  zhHant: '傳送訊息',
                  en: 'Send Message',
                  ja: 'メッセージ',
                  ko: '메시지'),
              iconColor: Colors.white,
              textColor: Colors.white,
              background: theme.primaryColor ?? AppTokens.accent,
              onTap: () => _itemClick('sendMsg', context, conversation)),
        ]));
  }

  Widget _mobileSettingsCard(TUITheme theme, List<Widget> children) {
    final dark = ThemeData.estimateBrightnessForColor(
            theme.conversationItemBgColor ?? Colors.white) ==
        Brightness.dark;
    final rows = <Widget>[
      for (final child in children)
        if (child is Column) ...child.children else child,
    ]..removeWhere(
        (child) => child is SizedBox && child.width == 0 && child.height == 0);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: dark ? const Color(0xFF1D2027) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              Divider(
                  height: 1,
                  thickness: .5,
                  indent: 16,
                  endIndent: 16,
                  color:
                      dark ? const Color(0xFF343842) : const Color(0xFFE9ECF1)),
            rows[index],
          ],
        ]),
      ),
    );
  }

  Widget _buildChatBackgroundEntry(
    BuildContext context,
    V2TimConversation conversation,
  ) {
    return TIMUIKitProfileWidget.operationItem(
      operationName: AppI18n.of(context).t(
        zhHans: '设置当前聊天背景',
        zhHant: '設定目前聊天背景',
        en: 'Set Chat Background',
        ja: 'チャット背景を設定',
        ko: '채팅 배경 설정',
      ),
      operationText: "",
      type: "text",
      isEmpty: true,
      smallCardMode: false,
    );
  }

  Widget _buildBlacklistSwitch(BuildContext context) {
    return ListenableBuilder(
      listenable: BlockLocalStore.instance,
      builder: (context, _) {
        final blocked = BlockLocalStore.instance.isBlocked(widget.userID);
        return TIMUIKitProfileWidget.operationItem(
          operationName: AppI18n.of(context).t(
            zhHans: '加入黑名单',
            zhHant: '加入黑名單',
            en: 'Block User',
            ja: 'ブロック',
            ko: '차단',
          ),
          type: 'switch',
          operationValue: blocked,
          isEmpty: false,
          smallCardMode: false,
          onSwitchChange: (value) =>
              unawaited(_handleToggleBlackList(shouldAdd: value)),
        );
      },
    );
  }

  Widget _buildMomentsEntry(BuildContext context) {
    return TIMUIKitProfileWidget.operationItem(
      operationName: AppI18n.of(context).t(
        zhHans: '朋友圈',
        zhHant: '朋友圈',
        en: 'Moments',
        ja: 'モーメンツ',
        ko: '모멘트',
      ),
      operationText: "",
      type: "text",
      isEmpty: true,
      smallCardMode: false,
    );
  }

  Future<void> _loadMomentsPrivacy() async {
    final peerId = ChatIdFormat.rawUserUid(widget.userID);
    if (peerId.isEmpty ||
        ProfilePageNav.isSelfUser(peerId) ||
        !_resolveInMyFriendList()) {
      if (mounted) {
        setState(() {
          _blockMyMoments = false;
          _hideTheirMoments = false;
        });
      }
      return;
    }
    final block = await MomentsSettingsService.instance.isBlockedViewer(peerId);
    final hide = await MomentsSettingsService.instance.isHiddenAuthor(peerId);
    if (!mounted) {
      return;
    }
    setState(() {
      _blockMyMoments = block;
      _hideTheirMoments = hide;
    });
  }

  Future<void> _setBlockMyMoments(bool value) async {
    final peerId = ChatIdFormat.rawUserUid(widget.userID);
    if (peerId.isEmpty) {
      return;
    }
    setState(() => _blockMyMoments = value);
    final ok =
        await MomentsSettingsService.instance.setBlockedViewer(peerId, value);
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() => _blockMyMoments = !value);
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '设置失败',
        zhHant: '設置失敗',
        en: 'Failed to update',
        ja: '設定に失敗しました',
        ko: '설정에 실패했습니다',
      ));
    }
  }

  Future<void> _setHideTheirMoments(bool value) async {
    final peerId = ChatIdFormat.rawUserUid(widget.userID);
    if (peerId.isEmpty) {
      return;
    }
    setState(() => _hideTheirMoments = value);
    final ok =
        await MomentsSettingsService.instance.setHiddenAuthor(peerId, value);
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() => _hideTheirMoments = !value);
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '设置失败',
        zhHant: '設置失敗',
        en: 'Failed to update',
        ja: '設定に失敗しました',
        ko: '설정에 실패했습니다',
      ));
    }
  }

  Widget _buildMomentsPrivacySwitches(BuildContext context) {
    final i18n = AppI18n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TIMUIKitProfileWidget.operationItem(
          operationName: i18n.t(
            zhHans: '不让他看我的朋友圈',
            zhHant: '不讓他看我的朋友圈',
            en: 'Hide My Posts From Them',
            ja: '相手に自分の投稿を見せない',
            ko: '상대에게 내 게시물 숨기기',
          ),
          type: 'switch',
          operationValue: _blockMyMoments,
          isEmpty: false,
          smallCardMode: false,
          onSwitchChange: (value) => unawaited(_setBlockMyMoments(value)),
        ),
        TIMUIKitProfileWidget.operationItem(
          operationName: i18n.t(
            zhHans: '不看他的朋友圈',
            zhHant: '不看他的朋友圈',
            en: 'Hide Their Posts',
            ja: '相手の投稿を見ない',
            ko: '상대 게시물 보지 않기',
          ),
          type: 'switch',
          operationValue: _hideTheirMoments,
          isEmpty: false,
          smallCardMode: false,
          onSwitchChange: (value) => unawaited(_setHideTheirMoments(value)),
        ),
      ],
    );
  }

  Future<void> _openFriendMoments(V2TimFriendInfo friendInfo) async {
    final authorId = ChatIdFormat.rawUserUid(
      friendInfo.userID.trim().isNotEmpty ? friendInfo.userID : widget.userID,
    );
    if (authorId.isEmpty) {
      return;
    }
    if (DesktopSideColumnScope.maybeOf(context) != null) {
      await Navigator.push(
        context,
        DesktopSideColumnRoute<void>(
          title: AppI18n.of(context).t(
            zhHans: '朋友圈',
            zhHant: '朋友圈',
            en: 'Moments',
            ja: 'モーメンツ',
            ko: '모멘트',
          ),
          builder: (_) => MomentsPage(
            authorId: authorId,
            profileName: _resolveProfileDisplayName(friendInfo),
            profileAvatarUrl: friendInfo.userProfile?.faceUrl?.trim(),
            showCoverHeader: true,
            embedded: true,
          ),
        ),
      );
      return;
    }
    if (_isDesktopFormFactor) {
      _openWideMoments(
        authorId: authorId,
        profileName: _resolveProfileDisplayName(friendInfo),
        profileAvatarUrl: friendInfo.userProfile?.faceUrl?.trim(),
      );
      return;
    }
    await Navigator.push(
      context,
      AppMaterialPageRoute(
        builder: (_) => MomentsPage(
          authorId: authorId,
          profileName: _resolveProfileDisplayName(friendInfo),
          profileAvatarUrl: friendInfo.userProfile?.faceUrl?.trim(),
          showCoverHeader: true,
        ),
      ),
    );
  }

  Future<void> _openChatBackgroundPage(
    BuildContext context,
    V2TimConversation conversation,
  ) async {
    final conversationId = conversation.conversationID?.trim() ?? '';
    if (conversationId.isEmpty) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '当前无法设置聊天背景',
        zhHant: '目前無法設定聊天背景',
        en: 'Cannot set chat background now',
        ja: '今は背景を設定できません',
        ko: '지금은 배경 설정 불가',
      ));
      return;
    }
    final conversationName = _getDisplayName(
      _getProfileModel()?.userProfile?.friendInfo?.userProfile,
    ).trim().isNotEmpty
        ? _getDisplayName(
            _getProfileModel()?.userProfile?.friendInfo?.userProfile,
          )
        : (conversation.showName ?? widget.userID);
    if (DesktopSideColumnScope.maybeOf(context) != null) {
      await Navigator.push(
        context,
        DesktopSideColumnRoute<void>(
          title: AppI18n.of(context).t(
            zhHans: '聊天背景',
            zhHant: '聊天背景',
            en: 'Chat Background',
            ja: 'チャット背景',
            ko: '채팅 배경',
          ),
          builder: (context) => ChatBackgroundPage(
            conversationId: conversationId,
            conversationName: conversationName,
            embedded: true,
          ),
        ),
      );
      return;
    }
    if (_isDesktopFormFactor) {
      _openWideChatBackground(
        conversationId: conversationId,
        conversationName: conversationName,
      );
      return;
    }
    await Navigator.push(
      context,
      AppMaterialPageRoute(
        builder: (context) => ChatBackgroundPage(
          conversationId: conversationId,
          conversationName: conversationName,
        ),
      ),
    );
  }

  Future<void> _loadCommonGroupCount() async {
    if (ProfilePageNav.isSelfUser(widget.userID)) return;
    final peerId = ChatIdFormat.rawUserUid(widget.userID);
    if (peerId.isEmpty) return;
    try {
      final groups = await CommonGroupChatsService.instance
          .loadCommonGroupsPage(peerId, limit: 1);
      if (!mounted) return;
      setState(() => _commonGroupCount = groups.total);
    } catch (_) {}
  }

  void _openCommonGroupsPage() {
    final peerId = ChatIdFormat.rawUserUid(widget.userID);
    if (DesktopSideColumnScope.maybeOf(context) != null) {
      Navigator.of(context).push(
        DesktopSideColumnRoute<void>(
          title: AppI18n.of(context).t(
            zhHans: '共同的群聊',
            zhHant: '共同的群聊',
            en: 'Common Groups',
            ja: '共通のグループ',
            ko: '공통 그룹',
          ),
          builder: (_) => CommonGroupChatsPage(
            peerUserId: peerId,
            peerDisplayName: _friendRemarkHintBaseline(),
            embedded: true,
          ),
        ),
      );
      return;
    }
    if (_isDesktopFormFactor) {
      _openWideCommonGroups();
      return;
    }
    Navigator.of(context).push(
      AppMaterialPageRoute(
        builder: (_) => CommonGroupChatsPage(
          peerUserId: peerId,
          peerDisplayName: _friendRemarkHintBaseline(),
        ),
      ),
    );
  }

  Future<void> _openC2cComplaint(BuildContext context) async {
    final reportedUserId = ChatIdFormat.rawUserUid(widget.userID);
    if (reportedUserId.isEmpty || ProfilePageNav.isSelfUser(reportedUserId)) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '不能投诉自己',
        zhHant: '不能投訴自己',
        en: 'You cannot report yourself.',
        ja: '自分自身を通報できません。',
        ko: '자신을 신고할 수 없습니다.',
      ));
      return;
    }
    await ComplaintReasonPage.openC2c(
      context,
      reportedUserId: reportedUserId,
      reportedUserName: _friendRemarkHintBaseline(),
    );
  }

  Future<void> _showMoreActions(
    BuildContext context,
    TUITheme theme, {
    Offset? anchor,
  }) async {
    final canMessage = _resolveIsFriend();
    final inMyFriendList = _resolveInMyFriendList();
    final peerId = ChatIdFormat.rawUserUid(widget.userID);
    final i18n = AppI18n.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;

    Future<void> runAction(String action) async {
      switch (action) {
        case 'share':
          await _handleShareContact(context, theme);
          break;
        case 'complaint':
          await _openC2cComplaint(context);
          break;
        case 'deleteFriend':
          await _handleMoreAction('deleteFriend');
          break;
        case 'addFriend':
          await _handleMoreAction('addFriend');
          break;
        case 'toggleBlackList':
          await _handleToggleBlackList();
          break;
      }
    }

    if (isDesktop) {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final RelativeRect position;
      if (anchor != null) {
        position = RelativeRect.fromRect(
          Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0),
          Offset.zero & overlay.size,
        );
      } else {
        final size = MediaQuery.sizeOf(context);
        position = RelativeRect.fromLTRB(
          size.width - 220,
          96,
          24,
          size.height - 96,
        );
      }

      final items = <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'share',
          child: Text(
            i18n.t(
              zhHans: '分享联系人',
              zhHant: '分享聯絡人',
              en: 'Share Contact',
              ja: '連絡先を共有',
              ko: '연락처 공유',
            ),
          ),
        ),
      ];
      if (!ProfilePageNav.isSelfUser(peerId)) {
        items.add(
          PopupMenuItem<String>(
            value: 'complaint',
            child: Text(
              i18n.t(
                zhHans: '投诉',
                zhHant: '投訴',
                en: 'Complaint',
                ja: '通報',
                ko: '신고',
              ),
            ),
          ),
        );
      }
      if (inMyFriendList) {
        items.add(
          PopupMenuItem<String>(
            value: 'deleteFriend',
            child: Text(
              i18n.t(
                zhHans: '删除好友',
                zhHant: '刪除好友',
                en: 'Delete Friend',
                ja: '友達を削除',
                ko: '친구 삭제',
              ),
              style: TextStyle(
                color: theme.cautionColor ?? AppColors.primaryRed,
              ),
            ),
          ),
        );
      }
      if (!canMessage && !inMyFriendList) {
        items.add(
          PopupMenuItem<String>(
            value: 'addFriend',
            child: Text(
              i18n.t(
                zhHans: '加为好友',
                zhHant: '加為好友',
                en: 'Add Friend',
                ja: '友達を追加',
                ko: '친구 추가',
              ),
            ),
          ),
        );
      }
      if (!ProfilePageNav.isSelfUser(peerId)) {
        final blocked = BlockLocalStore.instance.isBlocked(widget.userID);
        items.add(
          PopupMenuItem<String>(
            value: 'toggleBlackList',
            child: Text(
              blocked
                  ? i18n.t(
                      zhHans: '移出黑名单',
                      zhHant: '移出黑名單',
                      en: 'Unblock',
                      ja: 'ブロック解除',
                      ko: '차단 해제',
                    )
                  : i18n.t(
                      zhHans: '加入黑名单',
                      zhHant: '加入黑名單',
                      en: 'Block User',
                      ja: 'ブロック',
                      ko: '차단',
                    ),
              style: blocked
                  ? null
                  : TextStyle(
                      color: theme.cautionColor ?? AppColors.primaryRed,
                    ),
            ),
          ),
        );
      }

      final selected = await showMenu<String>(
        context: context,
        position: position,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        color: AppColors.card(dark: dark),
        items: items,
      );
      if (selected == null || !mounted) {
        return;
      }
      await runAction(selected);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        Widget actionTile({
          required String title,
          required VoidCallback onTap,
          bool destructive = false,
          bool showDivider = true,
        }) {
          final color = destructive
              ? (theme.cautionColor ?? AppColors.primaryRed)
              : (theme.primaryColor ?? AppColors.primaryBlue);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: showDivider
                      ? Border(
                          bottom: BorderSide(
                            color: AppColors.line(dark: dark),
                            width: 0.7,
                          ),
                        )
                      : null,
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.card(dark: dark),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      actionTile(
                        title: i18n.t(
                          zhHans: '分享联系人',
                          zhHant: '分享聯絡人',
                          en: 'Share Contact',
                          ja: '連絡先を共有',
                          ko: '연락처 공유',
                        ),
                        showDivider: !ProfilePageNav.isSelfUser(peerId) ||
                            inMyFriendList ||
                            (!canMessage && !inMyFriendList),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await runAction('share');
                        },
                      ),
                      if (!ProfilePageNav.isSelfUser(peerId))
                        actionTile(
                          title: i18n.t(
                            zhHans: '投诉',
                            zhHant: '投訴',
                            en: 'Complaint',
                            ja: '通報',
                            ko: '신고',
                          ),
                          showDivider: true,
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await runAction('complaint');
                          },
                        ),
                      if (inMyFriendList)
                        actionTile(
                          title: i18n.t(
                            zhHans: '删除好友',
                            zhHant: '刪除好友',
                            en: 'Delete Friend',
                            ja: '友達を削除',
                            ko: '친구 삭제',
                          ),
                          destructive: true,
                          showDivider: true,
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await runAction('deleteFriend');
                          },
                        ),
                      if (!canMessage && !inMyFriendList)
                        actionTile(
                          title: i18n.t(
                            zhHans: '加为好友',
                            zhHant: '加為好友',
                            en: 'Add Friend',
                            ja: '友達を追加',
                            ko: '친구 추가',
                          ),
                          showDivider: true,
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await runAction('addFriend');
                          },
                        ),
                      if (!ProfilePageNav.isSelfUser(peerId))
                        actionTile(
                          title:
                              BlockLocalStore.instance.isBlocked(widget.userID)
                                  ? i18n.t(
                                      zhHans: '移出黑名单',
                                      zhHant: '移出黑名單',
                                      en: 'Unblock',
                                      ja: 'ブロック解除',
                                      ko: '차단 해제',
                                    )
                                  : i18n.t(
                                      zhHans: '加入黑名单',
                                      zhHant: '加入黑名單',
                                      en: 'Block User',
                                      ja: 'ブロック',
                                      ko: '차단',
                                    ),
                          destructive: !BlockLocalStore.instance
                              .isBlocked(widget.userID),
                          showDivider: false,
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await runAction('toggleBlackList');
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.card(dark: dark),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: actionTile(
                    title: i18n.t(
                      zhHans: '取消',
                      zhHant: '取消',
                      en: 'Cancel',
                      ja: 'キャンセル',
                      ko: '취소',
                    ),
                    showDivider: false,
                    onTap: () => Navigator.pop(sheetContext),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _ensureCallPermissions(BuildContext context, bool isVideo) {
    return PermissionGuard.call(context, video: isVideo);
  }

  _itemClick(
      String id, BuildContext context, V2TimConversation conversation) async {
    switch (id) {
      case "sendMsg":
        // This button is only rendered for a confirmed friend profile. Use it
        // as a short-lived first-frame hint so the chat input does not flicker
        // between checking/blocked/allowed while relation is verified again in
        // the background.
        C2cFriendMessageGuard.trustCanSendHint(
          widget.userID,
          source: 'friend_profile_send_message',
        );
        if (widget.onClickSendMessage != null) {
          widget.onClickSendMessage!(conversation);
        } else {
          openOrReuseAppChat(
            context,
            conversation,
            initialC2cCanMessage: true,
            c2cPermissionHintSource: 'friend_profile_send_message',
          );
        }
        break;
      case "deleteFriend":
        await _handleDeleteFriend();
        break;
      case "audioCall":
        await CallLauncher.startBridgeC2C(
          context,
          userId: widget.userID,
          video: false,
        );
        break;
      case "videoCall":
        await CallLauncher.startBridgeC2C(
          context,
          userId: widget.userID,
          video: true,
        );
        break;
    }
  }

  Color _wideProfileCardColor(TUITheme theme) {
    return theme.conversationItemBgColor ??
        theme.wideBackgroundColor ??
        Colors.white;
  }

  Color _wideProfileBorderColor(TUITheme theme) {
    return theme.weakDividerColor ?? AppTokens.borderLight;
  }

  Widget _buildWideSettingRow({
    required TUITheme theme,
    required String title,
    String? value,
    VoidCallback? onTap,
    bool showChevron = true,
    Widget? trailing,
    bool copyable = false,
    VoidCallback? onCopy,
  }) {
    final titleColor = theme.weakTextColor ?? AppTokens.textSecondaryLight;
    final valueColor = theme.darkTextColor ?? AppTokens.textPrimaryLight;
    final displayValue = (value != null && value.isNotEmpty)
        ? value
        : (onTap == null
            ? ''
            : AppI18n.of(context).t(
                zhHans: '未填写',
                zhHant: '未填寫',
                en: 'Not set',
                ja: '未設定',
                ko: '미입력',
              ));
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: titleColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    color: valueColor,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else if (copyable && onCopy != null)
            IconButton(
              onPressed: onCopy,
              tooltip: AppI18n.of(context).t(
                zhHans: '复制',
                zhHant: '複製',
                en: 'Copy',
                ja: 'コピー',
                ko: '복사',
              ),
              icon: Icon(
                Icons.copy_rounded,
                size: 18,
                color: theme.primaryColor ?? AppTokens.accent,
              ),
            )
          else if (onTap != null && showChevron)
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: titleColor.withValues(alpha: 0.7),
            ),
        ],
      ),
    );
    if (onTap == null) {
      return content;
    }
    return InkWell(onTap: onTap, child: content);
  }

  Widget _buildWideSwitchRow({
    required TUITheme theme,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = ThemeData.estimateBrightnessForColor(
          _wideProfileCardColor(theme),
        ) ==
        Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                height: 1.25,
                color: theme.darkTextColor ?? AppTokens.textPrimaryLight,
              ),
            ),
          ),
          SizedBox(
            height: 31,
            child: CupertinoSwitch(
              value: value,
              onChanged: (next) {
                if (next == value) {
                  return;
                }
                onChanged(next);
              },
              activeTrackColor: theme.primaryColor ?? AppTokens.accent,
              inactiveTrackColor:
                  isDark ? const Color(0xFF39393D) : const Color(0xFFE9E9EB),
              thumbColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _wideNotSetLabel() {
    return AppI18n.of(context).t(
      zhHans: '未设置',
      zhHant: '未設定',
      en: 'Not set',
      ja: '未設定',
      ko: '설정 안 됨',
    );
  }

  String _wideGenderLabel(int? gender) {
    switch (gender) {
      case 1:
        return AppI18n.of(context).t(
          zhHans: '男',
          zhHant: '男',
          en: 'Male',
          ja: '男性',
          ko: '남성',
        );
      case 2:
        return AppI18n.of(context).t(
          zhHans: '女',
          zhHant: '女',
          en: 'Female',
          ja: '女性',
          ko: '여성',
        );
      default:
        return _wideNotSetLabel();
    }
  }

  String _wideSignaturePlaceholder() {
    return AppI18n.of(context).t(
      zhHans: '这个人很懒，什么都没写~',
      zhHant: '這個人很懶，什麼都沒寫~',
      en: 'Nothing here yet~',
      ja: 'まだ何も書いていません~',
      ko: '아직 아무것도 적지 않았어요~',
    );
  }

  Widget _buildWideWeChatRow({
    required TUITheme theme,
    required String title,
    required String value,
    VoidCallback? onTap,
    Widget? trailing,
    bool showChevron = false,
    Color? valueColor,
  }) {
    final titleColor = theme.darkTextColor ?? AppTokens.textPrimaryLight;
    final resolvedValueColor =
        valueColor ?? theme.weakTextColor ?? AppTokens.textSecondaryLight;
    final iconColor = (theme.weakTextColor ?? AppTokens.textSecondaryLight)
        .withValues(alpha: 0.7);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                height: 1.25,
                color: titleColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                height: 1.25,
                color: resolvedValueColor,
              ),
            ),
          ),
          if (trailing != null)
            trailing
          else if (showChevron)
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: iconColor,
            ),
        ],
      ),
    );
    if (onTap == null) {
      return content;
    }
    return InkWell(onTap: onTap, child: content);
  }

  Widget _buildWideWeChatSection(TUITheme theme, List<Widget> children) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final divider = theme.weakDividerColor ?? AppTokens.borderLight;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(
          height: 1,
          thickness: 0.6,
          indent: 20,
          color: divider,
        ));
      }
    }
    return ColoredBox(
      color: _wideProfileCardColor(theme),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  Widget _buildWideHeaderChip({
    required TUITheme theme,
    required Widget child,
    required VoidCallback onTap,
  }) {
    final bg = theme.weakBackgroundColor ?? const Color(0xFFF2F3F5);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: child,
        ),
      ),
    );
  }

  Widget _buildWideProfileHeader(
    V2TimUserFullInfo? userInfo,
    TUITheme theme,
  ) {
    final friendInfo = _getProfileModel()?.userProfile?.friendInfo;
    final name = friendInfo != null
        ? _resolveProfileDisplayName(friendInfo)
        : _getDisplayName(userInfo);
    final signature = TencentUtils.checkString(userInfo?.selfSignature) ??
        _wideSignaturePlaceholder();
    final genderIcon = _buildGenderIcon(userInfo?.gender);
    final displayUserId = ChatIdFormat.display(widget.userID);
    final titleColor = theme.darkTextColor ?? AppTokens.textPrimaryLight;
    final weakColor = theme.weakTextColor ?? AppTokens.textSecondaryLight;

    return ColoredBox(
      color: _wideProfileCardColor(theme),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: _buildProfileAvatar(
                    userInfo,
                    theme,
                    size: 72,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (genderIcon != null) genderIcon,
                        ],
                      ),
                      if (displayUserId.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          displayUserId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.primaryColor ?? AppTokens.accent,
                            height: 1.25,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        signature,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: weakColor,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildWideHeaderChip(
                  theme: theme,
                  onTap: () => _openFriendRemarkEdit(context),
                  child: Text(
                    AppI18n.of(context).t(
                      zhHans: '编辑资料',
                      zhHant: '編輯資料',
                      en: 'Edit',
                      ja: '編集',
                      ko: '편집',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: titleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (buttonContext) {
                    return _buildWideHeaderChip(
                      theme: theme,
                      onTap: () {
                        final box =
                            buttonContext.findRenderObject() as RenderBox?;
                        final anchor = box == null
                            ? null
                            : box.localToGlobal(
                                Offset(box.size.width, box.size.height),
                              );
                        _showMoreActions(context, theme, anchor: anchor);
                      },
                      child: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: titleColor,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.6,
            color: theme.weakDividerColor ?? AppTokens.borderLight,
          ),
        ],
      ),
    );
  }

  Widget _buildWideProfileSettings(
    BuildContext context,
    TUITheme theme,
    V2TimFriendInfo friendInfo,
    V2TimConversation conversation,
  ) {
    final i18n = AppI18n.of(context);
    final remark = _resolvedFriendRemark(imRemark: friendInfo.friendRemark);
    final remarkDisplay = remark.isEmpty ? _wideNotSetLabel() : remark;
    final showMoments = _resolveIsFriend() || _resolveInMyFriendList();
    final displayUserId = ChatIdFormat.display(widget.userID);
    final iconColor = (theme.weakTextColor ?? AppTokens.textSecondaryLight)
        .withValues(alpha: 0.75);

    Future<void> copyUserId() async {
      if (displayUserId.isEmpty) {
        return;
      }
      await ClipboardGuard.copy(displayUserId);
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '用户ID已复制',
        zhHant: '使用者 ID 已複製',
        en: 'User ID copied',
        ja: 'ユーザーIDをコピーしました',
        ko: '사용자 ID 복사됨',
      ));
    }

    final rows = <Widget>[
      _buildWideWeChatRow(
        theme: theme,
        title: i18n.t(
          zhHans: '备注',
          zhHant: '備註',
          en: 'Remark',
          ja: '備考',
          ko: '별명',
        ),
        value: remarkDisplay,
        onTap: () => _openFriendRemarkEdit(context),
        trailing: Icon(Icons.edit_outlined, size: 18, color: iconColor),
      ),
      if (displayUserId.isNotEmpty)
        _buildWideWeChatRow(
          theme: theme,
          title: i18n.t(
            zhHans: '99Chat ID',
            zhHant: '99Chat ID',
            en: '99Chat ID',
            ja: '99Chat ID',
            ko: '99Chat ID',
          ),
          value: displayUserId,
          valueColor: theme.primaryColor ?? AppTokens.accent,
          onTap: copyUserId,
          trailing: IconButton(
            onPressed: copyUserId,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: i18n.t(
              zhHans: '复制',
              zhHant: '複製',
              en: 'Copy',
              ja: 'コピー',
              ko: '복사',
            ),
            icon: Icon(Icons.copy_outlined, size: 16, color: iconColor),
          ),
        ),
      _buildWideWeChatRow(
        theme: theme,
        title: i18n.t(
          zhHans: '性别',
          zhHant: '性別',
          en: 'Gender',
          ja: '性別',
          ko: '성별',
        ),
        value: _wideGenderLabel(friendInfo.userProfile?.gender),
      ),
      if (showMoments)
        _buildWideWeChatRow(
          theme: theme,
          title: i18n.t(
            zhHans: '朋友圈',
            zhHant: '朋友圈',
            en: 'Moments',
            ja: 'モーメンツ',
            ko: '모멘트',
          ),
          value: '',
          showChevron: true,
          onTap: () => _openFriendMoments(friendInfo),
        ),
      if (showMoments && _resolveInMyFriendList()) ...[
        _buildWideSwitchRow(
          theme: theme,
          title: i18n.t(
            zhHans: '不让他看我的朋友圈',
            zhHant: '不讓他看我的朋友圈',
            en: 'Hide My Posts From Them',
            ja: '相手に自分の投稿を見せない',
            ko: '상대에게 내 게시물 숨기기',
          ),
          value: _blockMyMoments,
          onChanged: (value) => unawaited(_setBlockMyMoments(value)),
        ),
        _buildWideSwitchRow(
          theme: theme,
          title: i18n.t(
            zhHans: '不看他的朋友圈',
            zhHant: '不看他的朋友圈',
            en: 'Hide Their Posts',
            ja: '相手の投稿を見ない',
            ko: '상대 게시물 보지 않기',
          ),
          value: _hideTheirMoments,
          onChanged: (value) => unawaited(_setHideTheirMoments(value)),
        ),
      ],
      if (!ProfilePageNav.isSelfUser(widget.userID))
        _buildWideWeChatRow(
          theme: theme,
          title: i18n.t(
            zhHans: '共同的群聊',
            zhHant: '共同的群聊',
            en: 'Common Groups',
            ja: '共通のグループ',
            ko: '공통 그룹',
          ),
          value: '',
          onTap: _openCommonGroupsPage,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_commonGroupCount',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.25,
                  color: theme.weakTextColor ?? AppTokens.textSecondaryLight,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: iconColor,
              ),
            ],
          ),
        ),
      ..._buildWideGroupJoinMetaRows(theme),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildWideWeChatSection(theme, rows),
      ],
    );
  }

  Widget _buildWideFooterActionButton({
    required String label,
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: SizedBox(
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideActionFooter(
    BuildContext context,
    V2TimConversation conversation,
    TUITheme theme,
  ) {
    final canMessage = !ProfilePageNav.isSelfUser(widget.userID);
    final canCall = canMessage && !PlatformUtils().isWeb;
    final muted = theme.weakTextColor ?? AppTokens.textSecondaryLight;
    final isDark = ThemeData.estimateBrightnessForColor(
          _wideProfileCardColor(theme),
        ) ==
        Brightness.dark;
    final secondaryBg =
        isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F3F5);
    final sendBlue = theme.primaryColor ?? AppTokens.accent;

    return ColoredBox(
      color: _wideProfileCardColor(theme),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        child: Row(
          children: [
            _buildWideFooterActionButton(
              label: AppI18n.of(context).t(
                zhHans: '发消息',
                zhHant: '發訊息',
                en: 'Message',
                ja: 'メッセージ',
                ko: '메시지',
              ),
              icon: Icons.chat_bubble,
              background: sendBlue,
              foreground: Colors.white,
              onTap: canMessage
                  ? () => _itemClick('sendMsg', context, conversation)
                  : null,
            ),
            const SizedBox(width: 10),
            _buildWideFooterActionButton(
              label: AppI18n.of(context).t(
                zhHans: '语音通话',
                zhHant: '語音通話',
                en: 'Voice Call',
                ja: '音声通話',
                ko: '음성 통화',
              ),
              icon: Icons.call,
              background: secondaryBg,
              foreground: muted,
              onTap: canCall
                  ? () => _itemClick('audioCall', context, conversation)
                  : null,
            ),
            const SizedBox(width: 10),
            _buildWideFooterActionButton(
              label: AppI18n.of(context).t(
                zhHans: '视频通话',
                zhHant: '視訊通話',
                en: 'Video Call',
                ja: 'ビデオ通話',
                ko: '영상 통화',
              ),
              icon: Icons.videocam,
              background: secondaryBg,
              foreground: muted,
              onTap: canCall
                  ? () => _itemClick('videoCall', context, conversation)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  _buildBottomOperationList(
      BuildContext context, V2TimConversation conversation, theme) {
    final isWideScreen =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;

    List operationList = [
      {
        "label": AppI18n.of(context).t(
          zhHans: '发送消息',
          zhHant: '傳送訊息',
          en: 'Send Message',
          ja: 'メッセージを送信',
          ko: '메시지 보내기',
        ),
        "id": "sendMsg",
      },
      {
        "label": AppI18n.of(context).t(
          zhHans: '语音通话',
          zhHant: '語音通話',
          en: 'Voice Call',
          ja: '音声通話',
          ko: '음성 통화',
        ),
        "id": "audioCall",
      },
      {
        "label": AppI18n.of(context).t(
          zhHans: '视频通话',
          zhHant: '視訊通話',
          en: 'Video Call',
          ja: 'ビデオ通話',
          ko: '영상 통화',
        ),
        "id": "videoCall",
      },
    ];

    if (PlatformUtils().isWeb || PlatformUtils().isDesktop) {
      operationList = [
        {
          "label": AppI18n.of(context).t(
            zhHans: '发送消息',
            zhHant: '傳送訊息',
            en: 'Send Message',
            ja: 'メッセージを送信',
            ko: '메시지 보내기',
          ),
          "id": "sendMsg",
        }
      ];
    }

    return operationList.map((e) {
      return isWideScreen
          ? TIMUIKitProfileWidget.wideButton(
              smallCardMode: false,
              onPressed: () => _itemClick(e["id"] ?? "", context, conversation),
              text: e["label"] ?? "",
              color: e["id"] != "deleteFriend"
                  ? theme.primaryColor
                  : theme.cautionColor)
          : InkWell(
              onTap: () => _itemClick(e["id"] ?? "", context, conversation),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: theme.weakBackgroundColor ?? Colors.white,
                  border:
                      Border(bottom: BorderSide(color: theme.weakDividerColor)),
                ),
                child: Text(
                  e["label"] ?? "",
                  style: TextStyle(
                      color: e["id"] != "deleteFriend"
                          ? theme.primaryColor
                          : theme.cautionColor,
                      fontSize: 17),
                ),
              ),
            );
    }).toList();
  }

  void _onPrivilegedGameAccessChanged() {
    if (!mounted) {
      return;
    }
    final next = PrivilegedGameUserService.instance.isPrivileged;
    if (next != _isPrivilegedGameUser) {
      setState(() => _isPrivilegedGameUser = next);
    }
  }

  void _refreshPrivilegedGameAccess() {
    unawaited(PrivilegedGameUserService.instance.refreshFromNetwork());
  }

  String _resolveProfileDisplayName(V2TimFriendInfo friendInfo) {
    final remark = friendInfo.friendRemark?.trim() ?? '';
    if (remark.isNotEmpty) {
      return remark;
    }
    final nick = friendInfo.userProfile?.nickName?.trim() ?? '';
    if (nick.isNotEmpty) {
      return nick;
    }
    return friendInfo.userID.trim();
  }

  Widget _buildGameAdminPanel(V2TimFriendInfo friendInfo) {
    if (!_isPrivilegedGameUser ||
        ProfilePageNav.isSelfUser(widget.userID.trim()) ||
        !SangongMyConfigService.instance.config.configured) {
      return const SizedBox.shrink();
    }
    _ledgerDisplayName = _resolveProfileDisplayName(friendInfo);
    final panel = UserProfileGameAdminPanel(
      targetUserId: widget.userID.trim(),
      displayName: _ledgerDisplayName,
    );
    if (TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop) {
      return panel;
    }
    return _mobileSettingsCard(
        Provider.of<DefaultThemeData>(context).theme, [panel]);
  }

  bool _shouldShowGameLedgerFloat() {
    return _isPrivilegedGameUser &&
        !ProfilePageNav.isSelfUser(widget.userID.trim()) &&
        SangongMyConfigService.instance.config.configured;
  }

  bool _shouldShowPrivilegeSideColumn({
    required bool isWideScreen,
    required bool inSideColumn,
  }) {
    return isWideScreen && !inSideColumn && _shouldShowGameLedgerFloat();
  }

  String _privilegeDisplayName() {
    final friendInfo = _getProfileModel()?.userProfile?.friendInfo;
    if (friendInfo != null) {
      return _resolveProfileDisplayName(friendInfo);
    }
    if (_ledgerDisplayName.trim().isNotEmpty) {
      return _ledgerDisplayName;
    }
    return widget.userID.trim();
  }

  Widget _buildGameLedgerFloatingEntry(TUITheme theme) {
    return UserProfileGameLedgerFloatingEntry(
      theme: theme,
      onOpenLedger: _openGameLedger,
    );
  }

  void _openGameLedger() {
    final imUserId = widget.userID.trim();
    if (imUserId.isEmpty) {
      return;
    }
    unawaited(
      UserProfileGameLedgerSheet.show(
        context,
        imUserId: imUserId,
        displayName: _ledgerDisplayName,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    DesktopEscBack.register(_onDesktopEscBack);
    unawaited(_ensureGroupProfileCanView());
    unawaited(_loadFriendRelation());
    unawaited(_loadCommonGroupCount());
    unawaited(BlockLocalStore.instance.ensureLoaded());
    BlockLocalStore.instance.addListener(_onBlockStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadGroupMemberJoinMeta());
      }
    });
    _isPrivilegedGameUser = PrivilegedGameUserService.instance.isPrivileged;
    PrivilegedGameUserService.instance.gameEnabled
        .addListener(_onPrivilegedGameAccessChanged);
    _refreshPrivilegedGameAccess();
    PeerProfileRefreshBus.instance.revision.addListener(_onPeerProfileRefresh);
    if (_isPrivilegedGameUser) {
      unawaited(_bootstrapSangongTenantForProfile());
    }
  }

  Future<void> _bootstrapSangongTenantForProfile() async {
    await SangongMyConfigService.instance.activateSession();
    final ok = await SangongGameHttp.setTenantFromMyConfig(force: true);
    if (!ok || !mounted) return;
    setState(() {}); // 触发子组件 rebuild,使面板拿到正确 tenant
  }

  Future<void> _loadGroupMemberJoinMeta() async {
    final gid = _viewGroupId;
    if (gid == null || gid.isEmpty) {
      if (mounted) {
        setState(() => _groupJoinMetaRecord = null);
      }
      return;
    }
    final record = await GroupMemberJoinMetaLoader.loadVisible(
      groupId: gid,
      userId: widget.userID,
    );
    if (!mounted) {
      return;
    }
    setState(() => _groupJoinMetaRecord = record);
  }

  Widget _buildGroupMemberJoinMetaBlock({bool smallCardMode = false}) {
    final gid = _viewGroupId;
    final record = _groupJoinMetaRecord;
    if (gid == null ||
        gid.isEmpty ||
        record == null ||
        !GroupMemberJoinMeta.hasAnyDisplayRow(record)) {
      return const SizedBox.shrink();
    }
    if (TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop) {
      return GroupMemberJoinMetaOperationBlock(
          groupId: gid, record: record, smallCardMode: smallCardMode);
    }
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final i18n = AppI18n.of(context);
    final joined =
        GroupMemberJoinMeta.formatJoinedAt(record.joinedAt, i18n: i18n);
    final source = GroupMemberJoinMeta.formatJoinSource(record, i18n: i18n);
    final tappable = GroupMemberJoinMeta.inviterTappable(record);
    Widget row(String title, String value, {VoidCallback? onTap}) => ListTile(
          visualDensity: const VisualDensity(vertical: -2),
          minVerticalPadding: 6,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16),
          title: Text(title,
              style: TextStyle(color: theme.darkTextColor, fontSize: 16)),
          subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(value,
                  style: TextStyle(
                      color: theme.weakTextColor, fontSize: 14, height: 1.4))),
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: theme.weakTextColor),
          onTap: onTap,
        );
    return _mobileSettingsCard(theme, [
      if (joined != null)
        row(
            i18n.t(
                zhHans: '入群时间',
                zhHant: '入群時間',
                en: 'Joined at',
                ja: '参加日時',
                ko: '가입 시간'),
            joined),
      if (source != null)
        row(GroupMemberJoinMeta.joinSourceTitle(record, i18n: i18n), source,
            onTap: tappable
                ? () => ProfilePageNav.openUserProfileOrAddFriend(context,
                    userID: record.invitedByUserId,
                    nickname: record.invitedByNickname,
                    addSource: FriendAddSource.card,
                    groupId: gid)
                : null),
    ]);
  }

  List<Widget> _buildWideGroupJoinMetaRows(TUITheme theme) {
    final gid = _viewGroupId;
    final record = _groupJoinMetaRecord;
    if (gid == null ||
        gid.isEmpty ||
        record == null ||
        !GroupMemberJoinMeta.hasAnyDisplayRow(record)) {
      return const <Widget>[];
    }
    final i18n = AppI18n.of(context);
    final joined = GroupMemberJoinMeta.formatJoinedAt(
      record.joinedAt,
      i18n: i18n,
    );
    final source = GroupMemberJoinMeta.formatJoinSource(record, i18n: i18n);
    final tappable = GroupMemberJoinMeta.inviterTappable(record);
    final rows = <Widget>[];
    if (joined != null) {
      rows.add(
        _buildWideSettingRow(
          theme: theme,
          title: i18n.t(
            zhHans: '入群时间',
            zhHant: '入群時間',
            en: 'Joined at',
            ja: '参加日時',
            ko: '가입 시간',
          ),
          value: joined,
          showChevron: false,
        ),
      );
    }
    if (source != null) {
      rows.add(
        _buildWideSettingRow(
          theme: theme,
          title: GroupMemberJoinMeta.joinSourceTitle(record, i18n: i18n),
          value: source,
          showChevron: tappable,
          onTap: tappable
              ? () {
                  ProfilePageNav.openUserProfileOrAddFriend(
                    context,
                    userID: record.invitedByUserId,
                    nickname: record.invitedByNickname,
                    addSource: FriendAddSource.card,
                    groupId: gid,
                  );
                }
              : null,
        ),
      );
    }
    return rows;
  }

  String? get _viewGroupId {
    final fromWidget = widget.groupId?.trim() ?? '';
    if (fromWidget.isNotEmpty) return fromWidget;
    return null;
  }

  Future<void> _ensureGroupProfileCanView() async {
    final gid = _viewGroupId;
    if (gid == null || gid.isEmpty) return;
    if (ProfilePageNav.isSelfUser(widget.userID)) return;

    final blocked = await GroupPrivacyGuard.blockedGroupProfileHint(
      groupId: gid,
      targetUserId: widget.userID,
    );
    if (blocked == null || !mounted) return;
    ToastUtils.toast(blocked);
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Widget _buildCommonGroupsEntry(BuildContext context) {
    if (ProfilePageNav.isSelfUser(widget.userID)) {
      return const SizedBox.shrink();
    }
    return InkWell(
      onTap: _openCommonGroupsPage,
      child: TIMUIKitProfileWidget.operationItem(
        operationName: AppI18n.of(context).t(
          zhHans: '共同的群聊',
          zhHant: '共同的群聊',
          en: 'Common Groups',
          ja: '共通のグループ',
          ko: '공통 그룹',
        ),
        operationText: "",
        type: "text",
        isEmpty: true,
        smallCardMode: false,
      ),
    );
  }

  Widget _buildWideDetailPane(TUITheme theme, Color pageBackgroundColor) {
    final i18n = AppI18n.of(context);
    final String title;
    switch (_wideDetail) {
      case _WideProfileDetail.commonGroups:
        title = i18n.t(
          zhHans: '共同的群聊',
          zhHant: '共同的群聊',
          en: 'Common Groups',
          ja: '共通のグループ',
          ko: '공통 그룹',
        );
        break;
      case _WideProfileDetail.moments:
        title = i18n.t(
          zhHans: '朋友圈',
          zhHant: '朋友圈',
          en: 'Moments',
          ja: 'モーメンツ',
          ko: '모멘트',
        );
        break;
      case _WideProfileDetail.chatBackground:
        title = i18n.t(
          zhHans: '聊天背景',
          zhHant: '聊天背景',
          en: 'Chat Background',
          ja: 'チャット背景',
          ko: '채팅 배경',
        );
        break;
      case _WideProfileDetail.none:
        title = '';
        break;
    }

    final close = _closeWideDetail;
    final Widget body;
    switch (_wideDetail) {
      case _WideProfileDetail.commonGroups:
        body = CommonGroupChatsPage(
          peerUserId: ChatIdFormat.rawUserUid(widget.userID),
          peerDisplayName: _friendRemarkHintBaseline(),
          embedded: true,
          onClose: close,
        );
        break;
      case _WideProfileDetail.moments:
        body = MomentsPage(
          authorId: _wideMomentsAuthorId,
          profileName: _wideMomentsName,
          profileAvatarUrl: _wideMomentsAvatar,
          showCoverHeader: true,
          embedded: true,
          onClose: close,
        );
        break;
      case _WideProfileDetail.chatBackground:
        body = ChatBackgroundPage(
          conversationId: _wideBgConversationId ?? '',
          conversationName: _wideBgConversationName ?? widget.userID,
          embedded: true,
          onClose: close,
        );
        break;
      case _WideProfileDetail.none:
        body = const SizedBox.shrink();
        break;
    }

    return Material(
      color: pageBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: theme.appbarBgColor ?? theme.wideBackgroundColor,
              border: Border(
                bottom: BorderSide(
                  color: theme.weakDividerColor ?? const Color(0xFFE7E7E7),
                  width: 0.6,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: i18n.t(
                    zhHans: '返回',
                    zhHant: '返回',
                    en: 'Back',
                    ja: '戻る',
                    ko: '뒤로',
                  ),
                  onPressed: close,
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: theme.primaryColor ?? AppTokens.accent,
                    size: 18,
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.darkTextColor,
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: i18n.t(
                      zhHans: '关闭',
                      zhHant: '關閉',
                      en: 'Close',
                      ja: '閉じる',
                      ko: '닫기',
                    ),
                    onPressed: () {
                      _closeWideDetail();
                      widget.onClose!();
                    },
                    icon: Icon(
                      Icons.close,
                      color: theme.darkTextColor,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  @override
  void dispose() {
    DesktopEscBack.unregister(_onDesktopEscBack);
    BlockLocalStore.instance.removeListener(_onBlockStoreChanged);
    PrivilegedGameUserService.instance.gameEnabled
        .removeListener(_onPrivilegedGameAccessChanged);
    PeerProfileRefreshBus.instance.revision
        .removeListener(_onPeerProfileRefresh);
    super.dispose();
  }

  bool _onDesktopEscBack() {
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        !_isDesktopFormFactor) {
      return false;
    }
    if (_wideDetail != _WideProfileDetail.none) {
      _closeWideDetail();
      return true;
    }
    if (widget.onClose != null) {
      widget.onClose!();
      return true;
    }
    return false;
  }

  void _onBlockStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onPeerProfileRefresh() {
    if (_profileEnrichmentInFlight ||
        _publishingProfile ||
        !PeerProfileRefreshBus.instance.matchesLatest(widget.userID)) {
      return;
    }
    unawaited(_reloadProfileAfterFriendChange());
  }

  Future<void> _reloadProfileAfterFriendChange() async {
    if (!mounted) {
      return;
    }
    try {
      _timuiKitProfileController.loadData(widget.userID);
    } catch (_) {}
    await _loadFriendRelation();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final inSideColumn = DesktopSideColumnScope.maybeOf(context) != null;
    final isWideScreen =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final showPrivilegeSide = _shouldShowPrivilegeSideColumn(
      isWideScreen: isWideScreen,
      inSideColumn: inSideColumn,
    );
    final isDark = ThemeData.estimateBrightnessForColor(
          theme.weakBackgroundColor ?? AppColors.background(dark: false),
        ) ==
        Brightness.dark;
    final pageBackgroundColor = isWideScreen
        ? theme.wideBackgroundColor ??
            theme.conversationItemBgColor ??
            Colors.white
        : (isDark ? const Color(0xFF111318) : const Color(0xFFF5F6F8));
    final appBarBackgroundColor = pageBackgroundColor;
    return TencentPage(
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: pageBackgroundColor,
          appBar: isWideScreen
              ? null
              : AppBar(
                  centerTitle: true,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  shadowColor: theme.weakDividerColor,
                  surfaceTintColor: Colors.transparent,
                  title: Text(
                    AppI18n.of(context).t(
                      zhHans: '详细资料',
                      zhHant: '詳細資料',
                      en: 'Profile Details',
                      ja: '詳細',
                      ko: '상세 정보',
                    ),
                    style: TextStyle(
                      color: theme.appbarTextColor ?? theme.darkTextColor,
                      fontSize: 16,
                    ),
                  ),
                  backgroundColor: appBarBackgroundColor,
                  iconTheme: IconThemeData(
                    color: AppColors.text(dark: isDark),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    color: AppColors.primaryBlue,
                    onPressed: () {
                      Navigator.pop(context, newUserMARK);
                    },
                  ),
                  actions: [
                    Builder(
                      builder: (buttonContext) {
                        return IconButton(
                          tooltip: AppI18n.of(context).t(
                            zhHans: '更多',
                            zhHant: '更多',
                            en: 'More',
                            ja: 'その他',
                            ko: '더보기',
                          ),
                          onPressed: () {
                            final box =
                                buttonContext.findRenderObject() as RenderBox?;
                            final anchor = box == null
                                ? null
                                : box.localToGlobal(
                                    Offset(0, box.size.height),
                                  );
                            _showMoreActions(
                              context,
                              theme,
                              anchor: anchor,
                            );
                          },
                          icon: Icon(
                            Icons.more_horiz,
                            color: AppColors.text(dark: isDark),
                          ),
                        );
                      },
                    ),
                  ],
                ),
          body: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                            child: ProfilePageKeyboard.dismissScope(
                                child: Container(
                          color: pageBackgroundColor,
                          child: isWideScreen &&
                                  !inSideColumn &&
                                  _wideDetail != _WideProfileDetail.none
                              ? _buildWideDetailPane(theme, pageBackgroundColor)
                              : isWideScreen
                                  ? TIMUIKitProfile(
                                      showLoadingAnimation: false,
                                      lifeCycle: ProfileLifeCycle(
                                        didGetFriendInfo: (V2TimFriendInfo?
                                            friendInfo) async {
                                          return _enrichFriendInfoFromBackend(
                                              friendInfo);
                                        },
                                        didRemarkUpdated:
                                            (String newRemark) async {
                                          _applyFriendRemarkLocally(newRemark);
                                          final friendModel = serviceLocator<
                                              TUIFriendShipViewModel>();
                                          final conversationModel =
                                              serviceLocator<
                                                  TUIConversationViewModel>();
                                          unawaited(
                                            conversationModel
                                                .refreshConversationItem(
                                              'c2c_${widget.userID}',
                                            ),
                                          );
                                          unawaited(friendModel
                                              .loadContactListData());
                                          ConversationRefreshBus.instance
                                              .requestRefresh(
                                            reason: 'friend_remark_updated',
                                          );
                                          return true;
                                        },
                                      ),
                                      userID: widget.userID,
                                      profileWidgetBuilder:
                                          ProfileWidgetBuilder(
                                        customBuilderOne: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          return _buildWideActionFooter(
                                            context,
                                            conversation,
                                            theme,
                                          );
                                        },
                                        customBuilderThree: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          return _buildWideProfileSettings(
                                            context,
                                            theme,
                                            friendInfo,
                                            conversation,
                                          );
                                        },
                                        userInfoCard:
                                            (V2TimUserFullInfo? userInfo) {
                                          return _buildWideProfileHeader(
                                              userInfo, theme);
                                        },
                                        remarkBar: (String remark,
                                            Function()? handleTap) {
                                          return TIMUIKitProfileWidget
                                              .remarkBar(
                                            context,
                                            _resolvedFriendRemark(
                                                imRemark: remark),
                                            (
                                                {Offset? offset,
                                                String? initText}) {
                                              _openFriendRemarkEdit(context);
                                            },
                                            true,
                                          );
                                        },
                                        customBuilderTwo: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildGroupMemberJoinMetaBlock(),
                                              _buildCommonGroupsEntry(context),
                                              InkWell(
                                                onTap: () =>
                                                    _openChatBackgroundPage(
                                                        context, conversation),
                                                child:
                                                    _buildChatBackgroundEntry(
                                                        context, conversation),
                                              ),
                                            ],
                                          );
                                        },
                                        customBuilderFour: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          return _buildGameAdminPanel(
                                              friendInfo);
                                        },
                                        customBuilderFive: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          final showMoments = isFriend ||
                                              _resolveInMyFriendList();
                                          if (!showMoments) {
                                            return const SizedBox.shrink();
                                          }
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                onTap: () => _openFriendMoments(
                                                    friendInfo),
                                                child:
                                                    _buildMomentsEntry(context),
                                              ),
                                              if (_resolveInMyFriendList())
                                                _buildMomentsPrivacySwitches(
                                                    context),
                                            ],
                                          );
                                        },
                                      ),
                                      controller: _timuiKitProfileController,
                                      profileWidgetsOrder: showPrivilegeSide
                                          ? const [
                                              ProfileWidgetEnum.userInfoCard,
                                              ProfileWidgetEnum
                                                  .customBuilderThree,
                                              ProfileWidgetEnum
                                                  .customBuilderOne,
                                            ]
                                          : const [
                                              ProfileWidgetEnum.userInfoCard,
                                              ProfileWidgetEnum
                                                  .customBuilderFour,
                                              ProfileWidgetEnum
                                                  .customBuilderThree,
                                              ProfileWidgetEnum
                                                  .customBuilderOne,
                                            ],
                                    )
                                  : TIMUIKitProfile(
                                      showLoadingAnimation: false,
                                      lifeCycle: ProfileLifeCycle(
                                        didGetFriendInfo: (V2TimFriendInfo?
                                            friendInfo) async {
                                          return _enrichFriendInfoFromBackend(
                                              friendInfo);
                                        },
                                        didRemarkUpdated:
                                            (String newRemark) async {
                                          _applyFriendRemarkLocally(newRemark);
                                          final friendModel = serviceLocator<
                                              TUIFriendShipViewModel>();
                                          final conversationModel =
                                              serviceLocator<
                                                  TUIConversationViewModel>();
                                          unawaited(
                                            conversationModel
                                                .refreshConversationItem(
                                              'c2c_${widget.userID}',
                                            ),
                                          );
                                          unawaited(friendModel
                                              .loadContactListData());
                                          ConversationRefreshBus.instance
                                              .requestRefresh(
                                            reason: 'friend_remark_updated',
                                          );
                                          return true;
                                        },
                                      ),
                                      userID: widget.userID,
                                      profileWidgetBuilder:
                                          ProfileWidgetBuilder(
                                        customBuilderOne: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          return _buildMobileActionArea(
                                            context,
                                            conversation,
                                            theme,
                                          );
                                        },
                                        customBuilderThree: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          return const SizedBox.shrink();
                                        },
                                        userInfoCard:
                                            (V2TimUserFullInfo? userInfo) {
                                          return _buildMobileProfileHeader(
                                              userInfo, theme);
                                        },
                                        remarkBar: (String remark,
                                            Function()? handleTap) {
                                          return TIMUIKitProfileWidget
                                              .remarkBar(
                                            context,
                                            _resolvedFriendRemark(
                                                imRemark: remark),
                                            (
                                                {Offset? offset,
                                                String? initText}) {
                                              _openFriendRemarkEdit(context);
                                            },
                                            false,
                                          );
                                        },
                                        customBuilderTwo: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          return Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _buildGroupMemberJoinMetaBlock(),
                                                _mobileSettingsCard(theme, [
                                                  _buildCommonGroupsEntry(
                                                      context),
                                                  InkWell(
                                                      onTap: () =>
                                                          _openChatBackgroundPage(
                                                              context,
                                                              conversation),
                                                      child:
                                                          _buildChatBackgroundEntry(
                                                              context,
                                                              conversation)),
                                                ]),
                                                if (!ProfilePageNav.isSelfUser(
                                                    widget.userID))
                                                  _mobileSettingsCard(theme, [
                                                    _buildBlacklistSwitch(
                                                        context),
                                                    ListTile(
                                                      title: Text(
                                                          AppI18n.of(context).t(
                                                              zhHans: '投诉该用户',
                                                              zhHant: '投訴該用戶',
                                                              en: 'Report User',
                                                              ja: 'ユーザーを通報',
                                                              ko: '사용자 신고'),
                                                          style: TextStyle(
                                                              color: theme
                                                                  .darkTextColor,
                                                              fontSize: 16)),
                                                      trailing: Icon(
                                                          Icons
                                                              .chevron_right_rounded,
                                                          color: theme
                                                              .weakTextColor),
                                                      onTap: () =>
                                                          _openC2cComplaint(
                                                              context),
                                                    ),
                                                  ]),
                                              ]);
                                        },
                                        customBuilderFour: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          return _buildGameAdminPanel(
                                              friendInfo);
                                        },
                                        customBuilderFive: (
                                          bool isFriend,
                                          V2TimFriendInfo friendInfo,
                                          V2TimConversation conversation,
                                        ) {
                                          final showMoments = isFriend ||
                                              _resolveInMyFriendList();
                                          return _mobileSettingsCard(theme, [
                                            ListTile(
                                              title: Text(
                                                  AppI18n.of(context).t(
                                                      zhHans: '备注名',
                                                      zhHant: '備註名',
                                                      en: 'Remark',
                                                      ja: '備考',
                                                      ko: '별명'),
                                                  style: TextStyle(
                                                      color:
                                                          theme.darkTextColor,
                                                      fontSize: 16)),
                                              trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    ConstrainedBox(
                                                        constraints: BoxConstraints(
                                                            maxWidth: MediaQuery
                                                                        .sizeOf(
                                                                            context)
                                                                    .width *
                                                                .35),
                                                        child: Text(
                                                            _resolvedFriendRemark(
                                                                imRemark:
                                                                    friendInfo
                                                                        .friendRemark),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                                color: theme
                                                                    .weakTextColor,
                                                                fontSize: 15))),
                                                    Icon(
                                                        Icons
                                                            .chevron_right_rounded,
                                                        color: theme
                                                            .weakTextColor),
                                                  ]),
                                              onTap: () =>
                                                  _openFriendRemarkEdit(
                                                      context),
                                            ),
                                            if (showMoments) ...[
                                              InkWell(
                                                  onTap: () =>
                                                      _openFriendMoments(
                                                          friendInfo),
                                                  child: _buildMomentsEntry(
                                                      context)),
                                              if (_resolveInMyFriendList())
                                                _buildMomentsPrivacySwitches(
                                                    context),
                                            ],
                                          ]);
                                        },
                                      ),
                                      controller: _timuiKitProfileController,
                                      profileWidgetsOrder: const [
                                        ProfileWidgetEnum.userInfoCard,
                                        ProfileWidgetEnum.customBuilderFour,
                                        ProfileWidgetEnum.customBuilderOne,
                                        ProfileWidgetEnum.customBuilderFive,
                                        ProfileWidgetEnum.customBuilderTwo,
                                      ],
                                    ),
                        ))),
                      ],
                    ),
                  ),
                  if (showPrivilegeSide)
                    UserProfileGamePrivilegeSideColumn(
                      theme: theme,
                      targetUserId: widget.userID.trim(),
                      displayName: _privilegeDisplayName(),
                    ),
                ],
              ),
              if (_shouldShowGameLedgerFloat() && !showPrivilegeSide)
                _buildGameLedgerFloatingEntry(theme),
            ],
          ),
        ),
        name: "friendProfile");
  }
}

class _ShareTarget {
  final String userID;
  final String groupID;

  const _ShareTarget({
    this.userID = "",
    this.groupID = "",
  });
}

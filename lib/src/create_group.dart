import 'package:tencent_cloud_chat_demo/src/pages/wallet/widgets/platform_coin_icon.dart';
import 'package:tencent_cloud_chat_demo/src/api/wallet_api.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_role_crown_icon.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:tencent_cloud_chat_demo/src/pages/privacy/terms_of_service_page.dart';
import 'dart:io';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_pay_pin_guard.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_create_limit_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_quota_limit_error.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/src/api/upload_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/app_gallery_picker.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_type.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/ui/components/app_search_bar.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_create_limit_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_create_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_change_event_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/utils/group_create_limit_message.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/self_hosted_friendship_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/utils/launch_system_ui.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_member_user_ids.dart';
import 'package:tencent_cloud_chat_demo/src/ui/utils/desktop_modal_layout.dart';

enum GroupTypeForUIKit { single, work, chat, meeting, public, community }

/// 普通群（Work / Public / Meeting）初始成员上限。
const int kStandardGroupMemberLimit = 6000;

/// 超级大群（Community）初始成员上限。
const int kSuperGroupMemberLimit = 100000;

/// 建群自定义消息 `opUser` 的空安全解析。
///
/// UIKit 的 `CoreServicesImpl.loginUserInfo` 只在 UIKit `login()` Future 正常
/// 返回后才被填充；原生已在线而 Dart Future 挂起的设备上它永远为 null，
/// 建群链路不得因此抛异常。按序取第一个非空值：UIKit 昵称 → UIKit userID →
/// 业务侧 [LoginUserInfo] 昵称 → 其 userID → [fallbackUserId] → 空串。
@visibleForTesting
String resolveCreateGroupOpUser({
  V2TimUserFullInfo? coreUser,
  V2TimUserFullInfo? providerUser,
  required String fallbackUserId,
}) {
  final candidates = <String?>[
    coreUser?.nickName,
    coreUser?.userID,
    providerUser?.nickName,
    providerUser?.userID,
    fallbackUserId,
  ];
  for (final candidate in candidates) {
    final value = candidate?.trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

GlobalKey<_CreateGroup> createGroupKey = GlobalKey();

/// Keep the channel member picker and its confirmation step inside one sheet.
Future<void> showCreateChannelSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x800A1526),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => CreateGroup(
                convType: GroupTypeForUIKit.community,
                channelMode: true,
                onDesktopClose: () => Navigator.of(sheetContext).pop(),
              ),
            ),
          ),
        ),
      ),
    );

class CreateGroup extends StatefulWidget {
  final GroupTypeForUIKit convType;
  final bool channelMode;
  final ValueChanged<V2TimConversation>? directToChat;

  /// 进入选人页时预勾选的好友 ID（如单聊设置页当前对方）。
  final List<String>? initialSelectedUserIds;

  /// 选完好友后进入通用群类型页 [CreateGroupIntroduction]，再进确认创建。
  final bool selectGroupTypeAfterMembers;

  /// Web / 桌面弹窗关闭（嵌入 WidePopup 且无外层标题时使用）。
  final VoidCallback? onDesktopClose;

  /// 宽屏设置列内：窄列选人，不用桌面双栏。
  final bool embeddedInSideColumn;

  const CreateGroup({
    Key? key,
    required this.convType,
    this.channelMode = false,
    this.directToChat,
    this.initialSelectedUserIds,
    this.selectGroupTypeAfterMembers = false,
    this.onDesktopClose,
    this.embeddedInSideColumn = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CreateGroup();
}

class _CreateGroup extends State<CreateGroup> {
  _CreateGroupDraft? _pendingGroupDraft;
  final V2TIMManager _sdkInstance = TIMUIKitCore.getSDKInstance();
  final MessageService _messageService = serviceLocator<MessageService>();
  final CoreServicesImpl _coreInstance = TIMUIKitCore.getInstance();
  final TUIFriendShipViewModel _friendshipViewModel =
      serviceLocator<TUIFriendShipViewModel>();
  final TextEditingController _searchController = TextEditingController();
  List<V2TimFriendInfo> friendList = [];
  List<V2TimFriendInfo> selectedFriendList = [];
  String _searchKeyword = "";
  Timer? _friendListRefreshTimer;
  int _friendListRequestGen = 0;
  bool _presenceLoadScheduled = false;
  bool _creatingGroup = false;
  int _contactListGeneration = 0;
  bool _loadingContacts = true;
  final GlobalKey<ContactListState> _contactListKey = GlobalKey();

  String _dioMsg(DioError e) => DioErrorMessage.forApp(e);

  void _safeSetState(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(fn);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(fn);
      }
    });
  }

  void _schedulePresenceLoad(
      PresenceProvider presence, Iterable<String> userIds) {
    if (!mounted || _presenceLoadScheduled) {
      return;
    }
    final ids = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    _presenceLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presenceLoadScheduled = false;
      if (!mounted) {
        return;
      }
      presence.ensure(ids);
    });
  }

  Future<void> _getConversationList({bool refreshConfirmed = false}) async {
    final requestGen = ++_friendListRequestGen;
    if (refreshConfirmed) {
      _safeSetState(() => _loadingContacts = true);
    }
    try {
      // The one-shot snapshot may already be marked complete after an empty
      // local projection or a swallowed protocol error. On entry/retry, ask
      // the authoritative contacts sync to catch up instead of trusting that
      // phase as proof that the friend list is current.
      if (SelfHostedFriendshipBridge.enabled) {
        if (refreshConfirmed) {
          await ImSdkRelationshipReconcileService.instance
              .refreshConfirmedFriends(reason: 'create_group');
        }
      } else {
        await ImSdkRelationshipReconcileService.instance
            .requestFirstSnapshot(reason: 'create_group');
      }
      if (!mounted || requestGen != _friendListRequestGen) return;
      _safeSetState(() {
        friendList = const <V2TimFriendInfo>[];
        if (selectedFriendList.isNotEmpty) {
          final directory = ImSdkRelationshipDirectory.instance;
          selectedFriendList = [
            for (final friend in selectedFriendList)
              if (directory.friend(friend.userID.trim()) != null)
                directory.friend(friend.userID.trim())!.toV2TimFriendInfo(),
          ];
        } else {
          final initials = widget.initialSelectedUserIds ?? const <String>[];
          if (initials.isNotEmpty) {
            final directory = ImSdkRelationshipDirectory.instance;
            selectedFriendList = [
              for (final raw in initials)
                if (directory.friend(raw.trim()) != null)
                  directory.friend(raw.trim())!.toV2TimFriendInfo(),
            ];
            _contactListGeneration++;
          }
        }
      });
    } catch (_) {
      if (!mounted || requestGen != _friendListRequestGen) return;
      // Keep the last projected contacts and selection if refresh fails.
    } finally {
      if (refreshConfirmed && mounted) {
        _safeSetState(() => _loadingContacts = false);
      }
    }
  }

  void _scheduleFriendListRefresh() {
    _friendListRefreshTimer?.cancel();
    _friendListRefreshTimer = Timer(const Duration(milliseconds: 120), () {
      unawaited(_getConversationList());
    });
  }

  _createSingleConversation() async {
    final userID = selectedFriendList.first.userID;
    final conversationID = "c2c_$userID";
    final res = await _sdkInstance
        .getConversationManager()
        .getConversation(conversationID: conversationID);
    if (!mounted) return;

    if (res.code == 0) {
      final V2TimConversation conversation = res.data ??
          V2TimConversation(
              conversationID: conversationID, userID: userID, type: 1);
      if (widget.directToChat != null) {
        widget.directToChat!(conversation);
      } else {
        Navigator.pushReplacement(context, appChatRoute(conversation));
      }
    }
  }

  _getShowName(V2TimFriendInfo item) {
    final friendRemark = item.friendRemark ?? "";
    final nickName = item.userProfile?.nickName ?? "";
    final userID = item.userID;
    final showName = nickName != "" ? nickName : userID;
    return friendRemark != "" ? friendRemark : showName;
  }

  List<V2TimFriendInfo> _getFilteredFriendList() {
    final directory = ImSdkRelationshipDirectory.instance;
    final keyword = _searchKeyword.trim().toLowerCase();
    final ids = directory.friendOrderedIds;
    final out = <V2TimFriendInfo>[];
    for (final id in ids) {
      final entry = directory.friend(id);
      if (entry == null) {
        continue;
      }
      if (keyword.isNotEmpty) {
        final name = entry.displayName.toLowerCase();
        if (!name.contains(keyword) && !id.toLowerCase().contains(keyword)) {
          continue;
        }
      }
      out.add(entry.toV2TimFriendInfo());
    }
    return out;
  }

  bool get _showsMemberSelectionLimit =>
      widget.selectGroupTypeAfterMembers ||
      (widget.convType != GroupTypeForUIKit.single &&
          widget.convType != GroupTypeForUIKit.chat);

  int get _memberSelectionMaxCount {
    if (widget.selectGroupTypeAfterMembers) {
      // 类型未定时按普通群上限；选 Community 后确认页不再扩选。
      return kStandardGroupMemberLimit;
    }
    if (widget.convType == GroupTypeForUIKit.community) {
      return kSuperGroupMemberLimit;
    }
    if (widget.convType == GroupTypeForUIKit.single) {
      return 1;
    }
    return kStandardGroupMemberLimit;
  }

  String get _memberSelectionCountLabel =>
      '${selectedFriendList.length}/$_memberSelectionMaxCount';

  Widget _buildMemberSelectionCountText(TUITheme theme) {
    return Text(
      _memberSelectionCountLabel,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: theme.weakTextColor ??
            theme.appbarTextColor?.withValues(alpha: 0.65) ??
            const Color(0xFF999999),
      ),
    );
  }

  Future<void> _openCreateGroupConfirmPage() async {
    final showSelector = !widget.channelMode &&
        (widget.convType == GroupTypeForUIKit.community ||
            widget.convType == GroupTypeForUIKit.public);
    await _openCreateGroupConfirmPageForType(
      widget.convType,
      showGroupTypeSelector: showSelector,
    );
  }

  Future<void> _openCreateGroupConfirmPageForType(
    GroupTypeForUIKit uiType, {
    bool showGroupTypeSelector = false,
  }) async {
    final groupType = _sdkGroupTypeOf(uiType);
    if (groupType == null) {
      return;
    }
    final allowTypeSwitch = showGroupTypeSelector &&
        (uiType == GroupTypeForUIKit.community ||
            uiType == GroupTypeForUIKit.public);
    final confirmPage = _CreateGroupConfirmPage(
      members: selectedFriendList,
      channelMode: widget.channelMode,
      showGroupTypeSelector: allowTypeSwitch,
      initialGroupType: allowTypeSwitch
          ? (_pendingGroupDraft?.groupType ?? GroupType.Public)
          : groupType,
      initialDraft: _pendingGroupDraft,
      embeddedInDesktopPopup:
          widget.embeddedInSideColumn || DesktopModalLayout.isDesktop(context),
      onCreate: (draft) async {
        String? avatarFaceUrl = draft.faceUrl;
        final hasLocalAvatar = draft.localAvatarPath.isNotEmpty ||
            (draft.localAvatarBytes != null &&
                draft.localAvatarBytes!.isNotEmpty);
        if (hasLocalAvatar) {
          try {
            final GroupAvatarUploadResult uploadResult;
            if (draft.localAvatarBytes != null &&
                draft.localAvatarBytes!.isNotEmpty) {
              uploadResult =
                  await UploadApi.instance.uploadPendingGroupAvatarBytes(
                bytes: draft.localAvatarBytes!,
              );
            } else if (kIsWeb) {
              final bytes = await XFile(draft.localAvatarPath).readAsBytes();
              uploadResult = await UploadApi.instance
                  .uploadPendingGroupAvatarBytes(bytes: bytes);
            } else {
              uploadResult = await UploadApi.instance.uploadPendingGroupAvatar(
                file: File(draft.localAvatarPath),
              );
            }
            avatarFaceUrl = uploadResult.thumbUrl;
            debugPrint(
                "pending group avatar thumbUrl: ${uploadResult.thumbUrl}");
          } on DioError catch (e) {
            if (!mounted) return;
            ToastUtils.toast(_dioMsg(e));
            return;
          } catch (e) {
            debugPrint("upload pending group avatar failed: $e");
            if (!mounted) return;
            ToastUtils.toast(DioErrorMessage.forApp(e));
            return;
          }
        }
        await _createGroup(
          draft.groupType,
          customGroupName: draft.groupName,
          introduction: draft.introduction,
          faceUrl: avatarFaceUrl,
          memberUserIds: draft.memberUserIds,
          payPin: draft.payPin,
          clientRequestId: draft.clientRequestId,
          expectedPriceCurrency: draft.expectedPriceCurrency,
          expectedPriceMinor: draft.expectedPriceMinor,
          channel: widget.channelMode,
        );
      },
    );
    if (DesktopModalLayout.isDesktop(context)) {
      // 桌面选人已在 WidePopup 内：用同窗 Navigator 推进确认页，
      // 才能露出与移动端一致的「普通群 / 超级大群」切换；
      // 勿再开第二层 WidePopup（isShow 互斥会直接吞掉）。
      await Navigator.of(context).push(
        AppMaterialPageRoute(builder: (context) => confirmPage),
      );
    } else {
      final draft = await Navigator.push<_CreateGroupDraft>(
        context,
        AppMaterialPageRoute(builder: (context) => confirmPage),
      );
      if (mounted && draft != null) {
        _pendingGroupDraft = draft;
      }
    }
  }

  String? _sdkGroupTypeOf(GroupTypeForUIKit uiType) {
    switch (uiType) {
      case GroupTypeForUIKit.community:
        return GroupType.Community;
      case GroupTypeForUIKit.meeting:
        return GroupType.Meeting;
      case GroupTypeForUIKit.work:
        return GroupType.Work;
      case GroupTypeForUIKit.public:
        return GroupType.Public;
      case GroupTypeForUIKit.single:
      case GroupTypeForUIKit.chat:
        return null;
    }
  }

  /// 选完好友后直接进「新建群聊」确认页（普通群 / 超级大群切换）。
  Future<void> _submitThenChooseGroupType() async {
    if (selectedFriendList.isEmpty) {
      return;
    }
    await _openCreateGroupConfirmPageForType(
      GroupTypeForUIKit.public,
      showGroupTypeSelector: true,
    );
  }

  bool _isCreateLimitGroupType(String groupType) {
    return groupType == GroupType.Work ||
        groupType == GroupType.Public ||
        groupType == GroupType.Community;
  }

  Future<bool> _ensureCanCreateGroupType(String groupType) async {
    if (!_isCreateLimitGroupType(groupType)) {
      return true;
    }
    try {
      final limits = await GroupCreateLimitApi.instance.fetch();
      if (!limits.canStartCreateAsOwner(groupType)) {
        if (!mounted) {
          return false;
        }
        ToastUtils.toastForce(
          GroupCreateLimitMessage.blockedForCreateOwner(
            groupType: groupType,
            limits: limits,
          ),
          context: context,
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('fetch group create limits failed: $e');
      return true;
    }
  }

  Future<void> _createGroup(
    String groupType, {
    String? customGroupName,
    String? introduction,
    String? faceUrl,
    List<String> memberUserIds = const <String>[],
    String? payPin,
    String? clientRequestId,
    String? expectedPriceCurrency,
    int? expectedPriceMinor,
    bool channel = false,
  }) async {
    if (_creatingGroup || GroupCreateService.instance.isCreating) {
      return;
    }
    // 后端已确认建群成功后才赋值；外层 catch 据此区分「建群失败」与
    // 「群已建好但后续跳转失败」，避免用户零反馈地停留在创建页。
    String createdGroupId = '';
    try {
      final trimmedGroupName = customGroupName?.trim() ?? "";
      if (trimmedGroupName.isEmpty) {
        if (!mounted) return;
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '请输入群名称',
          zhHant: '請輸入群名稱',
          en: 'Enter group name',
          ja: 'グループ名を入力',
          ko: '그룹 이름 입력',
        ));
        return;
      }
      final String groupName = trimmedGroupName;
      if (!await _ensureCanCreateGroupType(groupType)) {
        return;
      }
      final memberIds = memberUserIds
          .map(ChatIdFormat.rawUserUid)
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      final flowGeneration = GroupCreateService.instance.beginCreateFlow();
      _creatingGroup = true;
      GroupCreateOutcome? outcome;
      Object? createError;
      DioError? dioError;
      try {
        outcome = await GroupCreateService.instance.createWithRecovery(
          GroupCreateParams(
            groupType: groupType,
            groupName: groupName,
            introduction: introduction,
            memberUserIds: memberIds,
            avatarUrl: faceUrl,
            payPin: payPin,
            clientRequestId: clientRequestId,
            expectedPriceCurrency: expectedPriceCurrency,
            expectedPriceMinor: expectedPriceMinor,
            channel: channel,
          ),
        );
      } on DioError catch (e) {
        createError = e;
        dioError = e;
      } catch (e) {
        createError = e;
      }

      if (outcome == null || outcome.record.groupId.trim().isEmpty) {
        outcome = await GroupCreateService.instance.recoverAfterFailure();
      }

      if (!mounted) return;
      if (!GroupCreateService.instance.isLatestCreateFlow(flowGeneration)) {
        return;
      }
      final record = outcome?.record;
      final isNewGroup = outcome?.isNewGroup ?? false;
      if (record != null && record.groupId.trim().isNotEmpty) {
        if (!isNewGroup) {
          ToastUtils.toast(AppI18n.of(context).t(
            zhHans: '创建失败，请稍后重试',
            zhHant: '建立失敗，請稍後重試',
            en: 'Create failed. Please try again later.',
            ja: '作成に失敗しました。しばらくしてから再試行してください。',
            ko: '생성 실패. 잠시 후 다시 시도해 주세요.',
          ));
          return;
        }
        createdGroupId = record.groupId.trim();
        if (dioError != null &&
            memberIds.isNotEmpty &&
            record.memberCount < 1 + memberIds.length) {
          ToastUtils.toast(AppI18n.of(context).t(
            zhHans: '群已创建，部分成员可能未加入，请在群资料中重新邀请',
            zhHant: '群已建立，部分成員可能未加入，請在群資料中重新邀請',
            en: 'Group created, but some members may not have joined. Re-invite from group profile.',
            ja: 'グループは作成されましたが、一部のメンバーが参加していない可能性があります。グループ情報から再招待してください。',
            ko: '그룹이 생성되었지만 일부 멤버가 참가하지 않았을 수 있습니다. 그룹 정보에서 다시 초대하세요.',
          ));
        }
        await _sendMessageToNewlyCreatedGroup(groupType, record.groupId.trim());
        if (!mounted) return;
        if (!GroupCreateService.instance.isLatestCreateFlow(flowGeneration)) {
          return;
        }
        await _finishCreatedGroup(
          flowGeneration: flowGeneration,
          record: record,
          groupType: groupType,
          groupName: groupName,
          faceUrl: faceUrl,
        );
        return;
      }

      if (dioError != null) {
        final code = MeGroupApi.readDioCode(dioError);
        if (code == 'COMMUNITY_PRICE_CHANGED') {
          ToastUtils.toastForce(
            AppI18n.of(context).t(
              zhHans: '超级大群价格已更新，请重新确认',
              zhHant: '超級大群價格已更新，請重新確認',
              en: 'The super group price changed. Please confirm again.',
              ja: '料金が変更されました。再確認してください。',
              ko: '슈퍼 그룹 가격이 변경되었습니다. 다시 확인해 주세요.',
            ),
            context: context,
          );
          return;
        }
        final quotaError =
            GroupQuotaLimitError.tryParse(dioError.response?.data);
        final limitMessage = quotaError != null
            ? GroupCreateLimitMessage.fromQuotaError(
                quotaError,
                groupType: groupType,
              )
            : GroupCreateLimitMessage.fromApiCode(
                code: code,
                groupType: groupType,
              );
        if (limitMessage != null) {
          ToastUtils.toastForce(limitMessage, context: context);
        } else {
          ToastUtils.toast(
            DioErrorMessage.sanitizeUserText(
              code,
              fallback: AppI18n.of(context).t(
                zhHans: '创建失败，请稍后重试',
                zhHant: '建立失敗，請稍後重試',
                en: 'Create failed. Please try again later.',
                ja: '作成に失敗しました。しばらくしてから再試行してください。',
                ko: '생성 실패. 잠시 후 다시 시도해 주세요.',
              ),
            ),
          );
        }
        debugPrint('createGroup REST failed: code=$code');
        return;
      }
      if (createError != null) {
        debugPrint('createGroup REST exception: $createError');
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '创建失败，请稍后重试',
          zhHant: '建立失敗，請稍後重試',
          en: 'Create failed. Please try again later.',
          ja: '作成に失敗しました。しばらくしてから再試行してください。',
          ko: '생성 실패. 잠시 후 다시 시도해 주세요.',
        ));
      }
    } catch (e) {
      debugPrint("createGroup exception: $e");
      if (mounted) {
        if (createdGroupId.isNotEmpty) {
          ToastUtils.toast(AppI18n.of(context).t(
            zhHans: '群已创建，请在群聊列表中打开',
            zhHant: '群已建立，請在群聊列表中開啟',
            en: 'Group created. Open it from the group list.',
            ja: 'グループを作成しました。グループ一覧から開いてください。',
            ko: '그룹이 생성되었습니다. 그룹 목록에서 열어 주세요.',
          ));
        } else {
          ToastUtils.toast(AppI18n.of(context).t(
            zhHans: '创建失败，请稍后重试',
            zhHant: '建立失敗，請稍後重試',
            en: 'Create failed. Please try again later.',
            ja: '作成に失敗しました。しばらくしてから再試行してください。',
            ko: '생성 실패. 잠시 후 다시 시도해 주세요.',
          ));
        }
      }
    } finally {
      _creatingGroup = false;
    }
  }

  Future<void> _finishCreatedGroup({
    required int flowGeneration,
    required MeGroupRecord record,
    required String groupType,
    required String groupName,
    String? faceUrl,
  }) async {
    // The create response can omit the current member role/channel marker.
    // We know this account just created the channel, so publish that identity
    // before opening chat instead of letting the first frame treat it as muted.
    if (widget.channelMode) {
      record = record.copyWith(
        isChannel: true,
        myRole: kGroupCreateOwnerRole,
        ownerUserId: _resolveCreateGroupOpUser(),
      );
    }
    _safeSetState(() {
      selectedFriendList = [];
      _contactListGeneration++;
    });
    await GroupMembershipSyncService.instance.upsertCreatedGroup(record);
    if (!mounted) return;
    final groupID = record.groupId.trim();
    if (groupID.isEmpty) {
      return;
    }
    final resolvedFaceUrl =
        record.avatarUrl.isNotEmpty ? record.avatarUrl : faceUrl;
    final conversationID = "group_$groupID";
    final convRes = await _sdkInstance
        .getConversationManager()
        .getConversation(conversationID: conversationID);
    if (!mounted) return;
    final conversation = (convRes.code == 0 && convRes.data != null)
        ? convRes.data!
        : V2TimConversation(
            conversationID: conversationID,
            type: 2,
            showName: groupName,
            groupType: groupType,
            groupID: groupID);
    // 建群 REST 返回的 groupId 为准；SDK getConversation 的 groupID 可能滞后，
    // 聊天页按 groupID 拉历史，不校正会标题是新群名、消息却是旧群。
    conversation.conversationID = conversationID;
    conversation.groupID = groupID;
    conversation.type = 2;
    conversation.groupType = groupType;
    conversation.showName = groupName;
    if (resolvedFaceUrl != null && resolvedFaceUrl.isNotEmpty) {
      conversation.faceUrl = resolvedFaceUrl;
    }

    conversation.unreadCount = 0;
    final orderKey = conversation.orderkey ?? 0;
    if (orderKey <= 0) {
      conversation.orderkey = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    await ConversationSyncService.instance.commitCreatedConversation(
      conversation,
    );
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'group_created',
      conversationId: conversationID,
    );

    if (!GroupCreateService.instance.isLatestCreateFlow(flowGeneration)) {
      return;
    }

    // 创建页键盘未收起就跳转时，聊天页会误读 viewInsets，输入栏悬空。
    FocusManager.instance.primaryFocus?.unfocus();

    if (widget.directToChat != null) {
      widget.directToChat!(conversation);
    } else {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!GroupCreateService.instance.isLatestCreateFlow(flowGeneration)) {
        return;
      }
      final navigator = widget.channelMode
          ? Navigator.of(context, rootNavigator: true)
          : Navigator.of(context);
      navigator.pushAndRemoveUntil(
          appChatRoute(conversation), ModalRoute.withName("/homePage"));
    }
  }

  String _resolveCreateGroupOpUser() {
    V2TimUserFullInfo? providerUser;
    try {
      providerUser =
          Provider.of<LoginUserInfo>(context, listen: false).loginUserInfo;
    } catch (_) {
      providerUser = null;
    }
    return resolveCreateGroupOpUser(
      coreUser: _coreInstance.loginUserInfo,
      providerUser: providerUser,
      fallbackUserId:
          ChatIdFormat.rawUserUid(ContactSocialCacheStore.safeLoginUserId()),
    );
  }

  /// 建群消息是副作用：群已在后端创建，任何失败都不得阻断 `_finishCreatedGroup`。
  Future<void> _sendMessageToNewlyCreatedGroup(
    String groupType,
    String groupID,
  ) async {
    try {
      V2TimMsgCreateInfoResult? res = await _messageService.createCustomMessage(
          data: json.encode({
        "businessID": "group_create",
        "version": 4,
        "opUser": _resolveCreateGroupOpUser(),
        "channel": widget.channelMode,
        "content": widget.channelMode
            ? AppI18n.of(context).t(
                zhHans: '创建频道',
                zhHant: '建立頻道',
                en: 'Created channel',
                ja: 'チャンネルを作成',
                ko: '채널 생성',
              )
            : groupType == GroupType.Community
                ? AppI18n.of(context).t(
                    zhHans: '创建社群',
                    zhHant: '建立社群',
                    en: 'Created community',
                    ja: 'コミュニティを作成',
                    ko: '커뮤니티 생성',
                  )
                : AppI18n.of(context).t(
                    zhHans: '创建群组',
                    zhHant: '建立群組',
                    en: 'Created group',
                    ja: 'グループを作成',
                    ko: '그룹 생성',
                  ),
        "cmd": groupType == GroupType.Community ? 1 : 0
      }));
      if (res != null) {
        final sent = await ChatExternalMessageSender.sendCreatedMessage(
          messageInfo: res.messageInfo,
          receiverUserId: '',
          groupId: groupID,
          reason: 'group_create_message_sent',
          isExcludedFromUnreadCount: true,
        );
        if (sent) {
          unawaited(
            GroupChangeEventSyncService.instance.syncForGroup(
              groupID,
              reason: 'group_create',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('createGroup message send failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _friendshipViewModel.addListener(_onFriendListChanged);
    ImSdkRelationshipDirectory.instance.addListener(_onFriendDirectoryChange);
    PeerProfileRefreshBus.instance.revision.addListener(_onPeerProfileRefresh);
    unawaited(_getConversationList(refreshConfirmed: true));
  }

  void _onFriendDirectoryChange(RelationshipDirectoryChange change) {
    if (!mounted || change.kind != RelationshipListKind.friends) return;
    final directory = ImSdkRelationshipDirectory.instance;
    _safeSetState(() {
      selectedFriendList = <V2TimFriendInfo>[
        for (final selected in selectedFriendList)
          if (directory.friend(selected.userID.trim()) case final current?)
            current.toV2TimFriendInfo(),
      ];
    });
  }

  void _onFriendListChanged() {
    _scheduleFriendListRefresh();
  }

  void _onPeerProfileRefresh() {
    _scheduleFriendListRefresh();
  }

  @override
  void dispose() {
    _friendListRequestGen++;
    _friendListRefreshTimer?.cancel();
    _friendshipViewModel.removeListener(_onFriendListChanged);
    ImSdkRelationshipDirectory.instance
        .removeListener(_onFriendDirectoryChange);
    PeerProfileRefreshBus.instance.revision
        .removeListener(_onPeerProfileRefresh);
    _searchController.dispose();
    super.dispose();
  }

  void onSubmit() {
    if (widget.selectGroupTypeAfterMembers) {
      unawaited(_submitThenChooseGroupType());
      return;
    }
    final isCommunity = widget.convType == GroupTypeForUIKit.community;
    if (!isCommunity && selectedFriendList.isEmpty) return;
    switch (widget.convType) {
      case GroupTypeForUIKit.single:
        _createSingleConversation();
        break;
      case GroupTypeForUIKit.chat:
        break;
      case GroupTypeForUIKit.community:
        _openCreateGroupConfirmPage();
        break;
      case GroupTypeForUIKit.meeting:
        _openCreateGroupConfirmPage();
        break;
      case GroupTypeForUIKit.work:
        _openCreateGroupConfirmPage();
        break;
      case GroupTypeForUIKit.public:
        _openCreateGroupConfirmPage();
        break;
    }
  }

  Widget _buildDesktopPopupHeader(TUITheme theme) {
    final i18n = AppI18n.of(context);
    final titleColor = theme.darkTextColor ?? const Color(0xFF111827);
    final weak = theme.weakTextColor ?? const Color(0xFF9CA3AF);
    final divider = theme.weakDividerColor ?? const Color(0xFFE8EAED);
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      decoration: BoxDecoration(
        color: theme.wideBackgroundColor ?? Colors.white,
        border: Border(
          bottom: BorderSide(color: divider.withValues(alpha: 0.85)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              i18n.t(
                zhHans: '创建群聊',
                zhHant: '建立群聊',
                en: 'Create Group',
                ja: 'グループを作成',
                ko: '그룹 만들기',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onDesktopClose,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.close_rounded, size: 22, color: weak),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSearchBar(TUITheme theme) {
    final fillColor = theme.inputFillColor ?? const Color(0xFFF3F4F6);
    final iconColor = theme.weakTextColor ?? const Color(0xFF9CA3AF);
    final textColor = theme.darkTextColor ?? const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(22),
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(fontSize: 14, color: textColor, height: 1.2),
          decoration: InputDecoration(
            isDense: true,
            hintText: AppI18n.of(context).t(
              zhHans: '搜索',
              zhHant: '搜尋',
              en: 'Search',
              ja: '検索',
              ko: '검색',
            ),
            hintStyle: TextStyle(color: iconColor, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: iconColor),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 44, minHeight: 44),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (value) {
            _safeSetState(() {
              _searchKeyword = value.trim();
            });
          },
        ),
      ),
    );
  }

  Widget _buildDesktopSelectedPanel(TUITheme theme) {
    final dividerColor = theme.weakDividerColor ?? const Color(0xFFE8EAED);
    final weakText = theme.weakTextColor ?? const Color(0xFF9CA3AF);
    final titleColor = theme.darkTextColor ?? const Color(0xFF111827);

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: theme.selectPanelBgColor ??
            theme.inputFillColor?.withValues(alpha: 0.35) ??
            const Color(0xFFF9FAFB),
        border: Border(
          left: BorderSide(color: dividerColor.withValues(alpha: 0.85)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  AppI18n.of(context).t(
                    zhHans: '已选成员',
                    zhHant: '已選成員',
                    en: 'Selected',
                    ja: '選択済み',
                    ko: '선택됨',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                const Spacer(),
                if (_showsMemberSelectionLimit)
                  Text(
                    _memberSelectionCountLabel,
                    style: TextStyle(fontSize: 12, color: weakText),
                  ),
              ],
            ),
          ),
          Expanded(
            child: selectedFriendList.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        AppI18n.of(context).t(
                          zhHans: '从左侧列表选择成员',
                          zhHant: '從左側列表選擇成員',
                          en: 'Select members from the list',
                          ja: '左のリストから選択',
                          ko: '왼쪽 목록에서 선택',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: weakText,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: selectedFriendList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final friend = selectedFriendList[index];
                      final showName = _getShowName(friend);
                      final faceUrl = friend.userProfile?.faceUrl ?? '';
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            _contactListKey.currentState
                                ?.deselectByUserId(friend.userID);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Avatar(
                                    faceUrl: faceUrl,
                                    showName: showName,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    showName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: titleColor,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: weakText,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton(
                onPressed: () {
                  final isCommunity =
                      widget.convType == GroupTypeForUIKit.community;
                  if (!isCommunity &&
                      !widget.selectGroupTypeAfterMembers &&
                      selectedFriendList.isEmpty) {
                    return;
                  }
                  onSubmit();
                },
                style: FilledButton.styleFrom(
                  backgroundColor:
                      theme.primaryColor ?? const Color(0xFF1E90FF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  widget.convType == GroupTypeForUIKit.single
                      ? AppI18n.of(context).t(
                          zhHans: '确定',
                          zhHant: '確定',
                          en: 'OK',
                          ja: 'OK',
                          ko: '확인',
                        )
                      : AppI18n.of(context).t(
                          zhHans: '下一步',
                          zhHant: '下一步',
                          en: 'Next',
                          ja: '次へ',
                          ko: '다음',
                        ),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList({
    required TUITheme theme,
    required bool isDarkBackground,
    required bool isWideScreen,
    required List<V2TimFriendInfo> filteredFriendList,
    required PresenceProvider presence,
    required TUIFriendShipViewModel friendship,
  }) {
    return ContactList(
      key: isWideScreen ? _contactListKey : ValueKey(_contactListGeneration),
      bgColor: isDarkBackground
          ? (isWideScreen
              ? theme.wideBackgroundColor
              : theme.weakBackgroundColor)
          : Colors.white,
      contactList: filteredFriendList,
      selectionContactList: filteredFriendList,
      isCanSelectMemberItem: true,
      maxSelectNum: _memberSelectionMaxCount,
      initialSelectedUserIds: selectedFriendList
          .map((friend) => friend.userID.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      isShowOnlineStatus: true,
      presenceListenable: presence,
      presenceLabelBuilder: (userId, imOnline) => presence.listLabelFor(
        userId: userId,
        imOnline: imOnline,
        isMutualFriend: friendCanMessage(friendship, userId),
      ),
      presenceLoadingChecker: (userId, imOnline) =>
          presence.isLastSeenLoading(userId: userId, imOnline: imOnline),
      onContactListLoaded: (userIds) {
        _schedulePresenceLoad(presence, userIds);
      },
      emptyBuilder: (context) {
        if (_loadingContacts && _searchKeyword.trim().isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final i18n = AppI18n.of(context);
        final searching = _searchKeyword.trim().isNotEmpty;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                searching
                    ? i18n.t(
                        zhHans: '未找到相关联系人',
                        zhHant: '未找到相關聯絡人',
                        en: 'No matching contacts',
                        ja: '該当する連絡先が見つかりません',
                        ko: '관련 연락처를 찾을 수 없습니다',
                      )
                    : i18n.t(
                        zhHans: '暂无联系人',
                        zhHant: '暫無聯絡人',
                        en: 'No contacts',
                        ja: '連絡先がありません',
                        ko: '연락처 없음',
                      ),
                style: TextStyle(color: theme.weakTextColor ?? Colors.grey),
              ),
              if (!searching) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => unawaited(
                    _getConversationList(refreshConfirmed: true),
                  ),
                  child: Text(i18n.t(
                    zhHans: '重新加载',
                    zhHant: '重新載入',
                    en: 'Retry',
                    ja: '再読み込み',
                    ko: '다시 불러오기',
                  )),
                ),
              ],
            ],
          ),
        );
      },
      onSelectedMemberItemChange: (selectedMember) {
        _safeSetState(() {
          selectedFriendList = selectedMember;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final appBarBaseColor =
        theme.appbarBgColor ?? theme.wideBackgroundColor ?? Colors.white;
    final isDarkBackground =
        ThemeData.estimateBrightnessForColor(appBarBaseColor) ==
            Brightness.dark;
    final isWideScreen = !widget.embeddedInSideColumn &&
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final filteredFriendList = _getFilteredFriendList();
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    final friendship = serviceLocator<TUIFriendShipViewModel>();

    Widget buildSearchBar() {
      return buildAppSearchBarInset(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        minHeight: 44,
        fontSize: 15,
        context: context,
        controller: _searchController,
        hint: AppI18n.of(context).t(
          zhHans: '搜索',
          zhHant: '搜尋',
          en: 'Search',
          ja: '検索',
          ko: '검색',
        ),
        onChanged: (value) {
          _safeSetState(() {
            _searchKeyword = value;
          });
        },
      );
    }

    Widget chooseMembers() {
      return Column(
        children: [
          if (isWideScreen) _buildDesktopSearchBar(theme) else buildSearchBar(),
          Expanded(
            child: _buildContactList(
              theme: theme,
              isDarkBackground: isDarkBackground,
              isWideScreen: isWideScreen,
              filteredFriendList: filteredFriendList,
              presence: presence,
              friendship: friendship,
            ),
          ),
        ],
      );
    }

    if (widget.embeddedInSideColumn) {
      return ColoredBox(
        color: theme.wideBackgroundColor ?? Colors.white,
        child: chooseMembers(),
      );
    }

    return TUIKitScreenUtils.getDeviceWidget(
        context: context,
        desktopWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onDesktopClose != null) _buildDesktopPopupHeader(theme),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: chooseMembers()),
                  _buildDesktopSelectedPanel(theme),
                ],
              ),
            ),
          ],
        ),
        defaultWidget: Scaffold(
          appBar: AppBar(
              centerTitle: true,
              leading: widget.channelMode && widget.onDesktopClose != null
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: theme.primaryColor ?? const Color(0xFF1E90FF),
                      onPressed: widget.onDesktopClose,
                    )
                  : AppBackButton(
                      color: theme.primaryColor ?? const Color(0xFF1E90FF),
                    ),
              title: _showsMemberSelectionLimit
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          AppI18n.of(context).t(
                            zhHans: '选择联系人',
                            zhHant: '選擇聯絡人',
                            en: 'Select Contacts',
                            ja: '連絡先を選択',
                            ko: '연락처 선택',
                          ),
                          style: TextStyle(
                            color: theme.appbarTextColor ??
                                theme.darkTextColor ??
                                Colors.black,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _buildMemberSelectionCountText(theme),
                      ],
                    )
                  : Text(
                      AppI18n.of(context).t(
                        zhHans: '选择联系人',
                        zhHant: '選擇聯絡人',
                        en: 'Select Contacts',
                        ja: '連絡先を選択',
                        ko: '연락처 선택',
                      ),
                      style: TextStyle(
                        color: theme.appbarTextColor ??
                            theme.darkTextColor ??
                            Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
              shadowColor: theme.weakDividerColor,
              backgroundColor: theme.appbarBgColor ??
                  theme.weakBackgroundColor ??
                  Colors.white,
              surfaceTintColor: Colors.transparent,
              actions: [
                TextButton(
                  onPressed: onSubmit,
                  child: Text(
                    widget.convType == GroupTypeForUIKit.single
                        ? AppI18n.of(context).t(
                            zhHans: '确定',
                            zhHant: '確定',
                            en: 'OK',
                            ja: 'OK',
                            ko: '확인',
                          )
                        : AppI18n.of(context).t(
                            zhHans: '下一步',
                            zhHant: '下一步',
                            en: 'Next',
                            ja: '次へ',
                            ko: '다음',
                          ),
                    style: TextStyle(
                      color: theme.appbarTextColor ??
                          theme.darkTextColor ??
                          Colors.black,
                      fontSize: 16,
                    ),
                  ),
                )
              ],
              iconTheme: IconThemeData(
                color: theme.primaryColor ?? const Color(0xFF1E90FF),
              )),
          body: chooseMembers(),
        ));
  }
}

class _CreateGroupDraft {
  final String groupName;
  final String? introduction;
  final String faceUrl;
  final String localAvatarPath;
  final Uint8List? localAvatarBytes;
  final String groupType;
  final List<String> memberUserIds;
  final String? payPin;
  final String? clientRequestId;
  final String? expectedPriceCurrency;
  final int? expectedPriceMinor;

  const _CreateGroupDraft({
    required this.groupName,
    this.introduction,
    required this.faceUrl,
    required this.localAvatarPath,
    this.localAvatarBytes,
    required this.groupType,
    required this.memberUserIds,
    this.payPin,
    this.clientRequestId,
    this.expectedPriceCurrency,
    this.expectedPriceMinor,
  });
}

class _CreateGroupConfirmPage extends StatefulWidget {
  final List<V2TimFriendInfo> members;
  final bool channelMode;
  final bool showGroupTypeSelector;
  final String initialGroupType;
  final _CreateGroupDraft? initialDraft;
  final Future<void> Function(_CreateGroupDraft draft) onCreate;

  /// Web 弹窗内嵌：单层顶栏，避免与外层弹窗标题叠成双头。
  final bool embeddedInDesktopPopup;

  const _CreateGroupConfirmPage({
    required this.members,
    this.channelMode = false,
    required this.showGroupTypeSelector,
    required this.initialGroupType,
    this.initialDraft,
    required this.onCreate,
    this.embeddedInDesktopPopup = false,
  });

  @override
  State<_CreateGroupConfirmPage> createState() =>
      _CreateGroupConfirmPageState();
}

class _CreateGroupConfirmPageState extends State<_CreateGroupConfirmPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _introController;
  late final FocusNode _nameFocusNode;
  late String _selectedGroupType;
  String _selectedAvatarUrl = "";
  String _selectedLocalAvatarPath = "";
  Uint8List? _selectedLocalAvatarBytes;

  bool _submitting = false;
  bool _nameFocused = false;
  GroupCreateLimitsResponse? _createLimits;
  final String _communityRequestId = const Uuid().v4();

  bool get _isCommunitySelected => _selectedGroupType == GroupType.Community;

  bool get _hasChannelAvatar =>
      _selectedAvatarUrl.trim().isNotEmpty ||
      _selectedLocalAvatarPath.isNotEmpty ||
      (_selectedLocalAvatarBytes?.isNotEmpty ?? false);

  bool _shouldTrackCreateLimits() {
    if (widget.channelMode) return false;
    return widget.showGroupTypeSelector ||
        _selectedGroupType == GroupType.Work ||
        _selectedGroupType == GroupType.Public ||
        _selectedGroupType == GroupType.Community;
  }

  GroupTypeCreateLimitInfo? _selectedTypeLimitInfo() {
    return _createLimits?.infoForGroupType(_selectedGroupType);
  }

  GroupTypeCreateLimitInfo? _selectedJoinLimitInfo() {
    return _createLimits?.joinInfoForGroupType(_selectedGroupType);
  }

  bool _canCreateSelectedType() {
    return _createLimits?.canStartCreateAsOwner(_selectedGroupType) ?? true;
  }

  @override
  void initState() {
    super.initState();
    _selectedGroupType = widget.initialGroupType;
    _nameController =
        TextEditingController(text: widget.initialDraft?.groupName ?? '');
    _introController =
        TextEditingController(text: widget.initialDraft?.introduction ?? '');
    _selectedAvatarUrl = widget.initialDraft?.faceUrl ?? '';
    _selectedLocalAvatarPath = widget.initialDraft?.localAvatarPath ?? '';
    _selectedLocalAvatarBytes = widget.initialDraft?.localAvatarBytes;
    _nameFocusNode = FocusNode()..addListener(_onNameFocusChanged);
    _nameController.addListener(_onNameTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyImmersiveSystemUi();
      if (_shouldTrackCreateLimits()) {
        _loadCreateLimits();
      }
    });
    GroupCreateLimitRefreshBus.instance.revision
        .addListener(_onCreateLimitsRefresh);
  }

  void _onCreateLimitsRefresh() {
    if (!_shouldTrackCreateLimits()) {
      return;
    }
    unawaited(_loadCreateLimits());
  }

  Future<void> _loadCreateLimits() async {
    try {
      final limits = await GroupCreateLimitApi.instance.fetch();
      if (!mounted) {
        return;
      }
      setState(() => _createLimits = limits);
    } catch (e) {
      debugPrint('load group create limits failed: $e');
    }
  }

  @override
  void dispose() {
    GroupCreateLimitRefreshBus.instance.revision
        .removeListener(_onCreateLimitsRefresh);
    LaunchSystemUi.restoreFromContext(context);
    _nameController.removeListener(_onNameTextChanged);
    _introController.dispose();
    _nameFocusNode.removeListener(_onNameFocusChanged);
    _nameFocusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _applyImmersiveSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  SystemUiOverlayStyle _buildPageOverlayStyle({
    required bool isDarkBackground,
    required Color pageBackgroundColor,
  }) {
    final navigationBarIsDark =
        ThemeData.estimateBrightnessForColor(pageBackgroundColor) ==
            Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: pageBackgroundColor,
      statusBarIconBrightness:
          isDarkBackground ? Brightness.light : Brightness.dark,
      statusBarBrightness:
          isDarkBackground ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness:
          navigationBarIsDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  void _onNameFocusChanged() {
    final focused = _nameFocusNode.hasFocus;
    if (focused != _nameFocused && mounted) {
      setState(() => _nameFocused = focused);
    }
  }

  void _onNameTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearGroupName() {
    _nameController.clear();
    _nameFocusNode.requestFocus();
  }

  String _getShowName(V2TimFriendInfo item) {
    final friendRemark = item.friendRemark ?? "";
    final nickName = item.userProfile?.nickName ?? "";
    final userID = item.userID;
    final showName = nickName.isNotEmpty ? nickName : userID;
    return friendRemark.isNotEmpty ? friendRemark : showName;
  }

  Future<void> _pickAvatarFromGallery() async {
    final file = await AppGalleryPicker.pickSingleImage(context);
    final picked = file == null ? null : XFile(file.path);
    if (picked == null || !mounted) {
      return;
    }
    await _applyPickedAvatarFile(picked);
  }

  Future<void> _pickAvatarFromCamera() async {
    final allowed = await PermissionGuard.cameraForPhoto(context);
    if (!allowed || !mounted) {
      return;
    }
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null || !mounted) {
      return;
    }
    await _applyPickedAvatarFile(picked);
  }

  /// Web / 桌面：跳过手机 ActionSheet，直接打开系统文件选择。
  Future<void> _pickAvatarFromDesktopOrWeb() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1920,
      maxHeight: 1920,
      requestFullMetadata: false,
    );
    if (picked == null || !mounted) {
      return;
    }
    await _applyPickedAvatarFile(picked);
  }

  Future<void> _applyPickedAvatarFile(XFile picked) async {
    final path = picked.path;
    Uint8List? bytes;
    if (kIsWeb || path.isEmpty) {
      bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedLocalAvatarPath = path;
      _selectedLocalAvatarBytes = bytes;
      _selectedAvatarUrl = "";
    });
  }

  Future<void> _onTapGroupAvatar(TUITheme theme) async {
    // Web / 宽屏：不要套 iOS ActionSheet（拍照 / 从手机相册）。
    if (kIsWeb || DesktopModalLayout.isDesktop(context)) {
      await _pickAvatarFromDesktopOrWeb();
      return;
    }
    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context, "cancel");
            },
            child: Text(AppI18n.of(context).t(
              zhHans: '取消',
              zhHant: '取消',
              en: 'Cancel',
              ja: 'キャンセル',
              ko: '취소',
            )),
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context, "camera");
              },
              child: Text(
                AppI18n.of(context).t(
                  zhHans: '拍照',
                  zhHant: '拍照',
                  en: 'Take Photo',
                  ja: '写真を撮る',
                  ko: '사진 촬영',
                ),
                style: TextStyle(color: theme.primaryColor),
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context, "gallery");
              },
              child: Text(
                AppI18n.of(context).t(
                  zhHans: '从手机相册选择',
                  zhHant: '從手機相簿選擇',
                  en: 'Choose from Gallery',
                  ja: 'ギャラリーから選択',
                  ko: '갤러리에서 선택',
                ),
                style: TextStyle(color: theme.primaryColor),
              ),
            ),
          ],
        );
      },
    );
    if (result == "camera") {
      await _pickAvatarFromCamera();
    } else if (result == "gallery") {
      await _pickAvatarFromGallery();
    }
  }

  Widget _buildLocalAvatarImage() {
    if (_selectedLocalAvatarBytes != null &&
        _selectedLocalAvatarBytes!.isNotEmpty) {
      return Image.memory(
        _selectedLocalAvatarBytes!,
        fit: BoxFit.cover,
      );
    }
    final path = _selectedLocalAvatarPath;
    if (path.isEmpty) {
      return const SizedBox.shrink();
    }
    if (kIsWeb ||
        path.startsWith('blob:') ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }

  Widget _buildGroupAvatar(TUITheme theme) {
    return InkWell(
      onTap: () => _onTapGroupAvatar(theme),
      child: Row(
        children: [
          Text(
            AppI18n.of(context).t(
              zhHans: '群头像',
              zhHant: '群頭像',
              en: 'Group Avatar',
              ja: 'グループアイコン',
              ko: '그룹 프로필',
            ),
            style: TextStyle(
              fontSize: 16,
              color: theme.darkTextColor ?? Colors.black,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 52,
            height: 52,
            child: (_selectedLocalAvatarPath.isNotEmpty ||
                    (_selectedLocalAvatarBytes?.isNotEmpty ?? false))
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: _buildLocalAvatarImage(),
                  )
                : Avatar(
                    faceUrl: _selectedAvatarUrl,
                    showName: _nameController.text.trim(),
                    type: 2,
                    borderRadius: BorderRadius.circular(26),
                    isFromLocalAsset: _selectedAvatarUrl.startsWith("assets/"),
                  ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.keyboard_arrow_right,
            color: theme.weakTextColor,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupNameInput(TUITheme theme) {
    final fillColor = theme.inputFillColor ??
        theme.selectPanelBgColor ??
        const Color(0xFFF1F2F6);
    final hintColor = theme.weakTextColor ?? const Color(0xFF999999);
    final hintText = _isCommunitySelected
        ? AppI18n.of(context).t(
            zhHans: '请输入群聊名称',
            zhHant: '請輸入群聊名稱',
            en: 'Enter group chat name',
            ja: 'グループチャット名を入力',
            ko: '그룹 채팅 이름 입력',
          )
        : AppI18n.of(context).t(
            zhHans: '请输入群名称',
            zhHant: '請輸入群名稱',
            en: 'Enter group name',
            ja: 'グループ名を入力',
            ko: '그룹 이름 입력',
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppI18n.of(context).t(
            zhHans: '群名称',
            zhHant: '群名稱',
            en: 'Group Name',
            ja: 'グループ名',
            ko: '그룹 이름',
          ),
          style: TextStyle(
            fontSize: 16,
            color: theme.darkTextColor ?? Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  maxLength: 20,
                  decoration: InputDecoration(
                    counterText: "",
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: hintColor,
                      fontSize: 15,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: theme.darkTextColor ?? Colors.black,
                  ),
                ),
              ),
              if (_nameFocused)
                GestureDetector(
                  onTap: _clearGroupName,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.cancel,
                      size: 18,
                      color: hintColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedGroupTypeDescription(TUITheme theme) {
    final limitsEnabled = _createLimits?.enabled ?? false;
    final info = _selectedTypeLimitInfo();
    final joinInfo = _selectedJoinLimitInfo();
    final baseDescription = GroupCreateLimitMessage.selectedTypeDescription(
      groupType: _selectedGroupType,
      limitsEnabled: limitsEnabled,
      info: info,
      joinInfo: joinInfo,
    );
    final price = _createLimits?.communityCreatePrice;
    final description = _isCommunitySelected && !widget.channelMode
        ? price != null && price.isValid
            ? '$baseDescription\n${AppI18n.of(context).t(zhHans: '创建费用', zhHant: '建立費用', en: 'Creation fee', ja: '作成料金', ko: '생성 비용')}：${price.displayAmount} ${price.currency}'
            : baseDescription
        : '$baseDescription\n${AppI18n.of(context).t(zhHans: '免费创建', zhHant: '免費建立', en: 'Free to create', ja: '無料で作成', ko: '무료 생성')}';
    final createBlocked =
        limitsEnabled && info != null && info.max > 0 && info.remaining <= 0;
    final joinBlocked = limitsEnabled &&
        joinInfo != null &&
        joinInfo.max > 0 &&
        joinInfo.remaining <= 0;
    final isBlocked = createBlocked || joinBlocked;
    final fillColor = theme.inputFillColor ??
        theme.selectPanelBgColor ??
        const Color(0xFFF7F8FA);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        description,
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: isBlocked
              ? (theme.cautionColor ?? const Color(0xFFE54545))
              : (theme.weakTextColor ?? const Color(0xFF666666)),
        ),
      ),
    );
  }

  Widget _buildCreateGroupDeclaration(TUITheme theme) {
    return Text(
      GroupCreateLimitMessage.createGroupDeclaration(),
      style: TextStyle(
        fontSize: 12,
        height: 1.45,
        color: theme.weakTextColor ?? const Color(0xFF999999),
      ),
    );
  }

  Widget _buildCreateLimitHint(TUITheme theme) {
    return _buildSelectedGroupTypeDescription(theme);
  }

  Widget _buildMemberItem(V2TimFriendInfo item, TUITheme theme) {
    final showName = _getShowName(item);
    return SizedBox(
      width: 60,
      child: Column(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Avatar(
              faceUrl: item.userProfile?.faceUrl ?? "",
              showName: showName,
              type: 1,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            showName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: theme.weakTextColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showQuotaBlockedNotice(BuildContext context) {
    final limits = _createLimits;
    ToastUtils.toastForce(
      limits == null
          ? GroupCreateLimitMessage.blockedJoinMessage(_selectedGroupType)
          : GroupCreateLimitMessage.blockedForCreateOwner(
              groupType: _selectedGroupType,
              limits: limits,
            ),
      context: context,
    );
  }

  Future<void> _handleCreatePressed(BuildContext pageContext) async {
    if (_submitting) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final groupName = _nameController.text.trim();
    if (groupName.isEmpty) {
      ToastUtils.toastForce(
        _isCommunitySelected
            ? AppI18n.of(pageContext).t(
                zhHans: '请输入群聊名称',
                zhHant: '請輸入群聊名稱',
                en: 'Enter group chat name',
                ja: 'グループチャット名を入力',
                ko: '그룹 채팅 이름 입력',
              )
            : AppI18n.of(pageContext).t(
                zhHans: '请输入群名称',
                zhHant: '請輸入群名稱',
                en: 'Enter group name',
                ja: 'グループ名を入力',
                ko: '그룹 이름 입력',
              ),
        context: pageContext,
      );
      return;
    }
    if (widget.channelMode && !_hasChannelAvatar) {
      ToastUtils.toastForce(
        AppI18n.of(pageContext).t(
          zhHans: '请先设置频道头像',
          zhHant: '請先設定頻道頭像',
          en: 'Choose a channel avatar first',
          ja: 'チャンネルのアイコンを設定してください',
          ko: '채널 프로필 사진을 설정해 주세요',
        ),
        context: pageContext,
      );
      return;
    }
    if (!_canCreateSelectedType()) {
      _showQuotaBlockedNotice(pageContext);
      return;
    }
    CommunityCreatePrice? price;
    String? payPin;
    if (_isCommunitySelected && !widget.channelMode) {
      try {
        final latest = await GroupCreateLimitApi.instance.fetch();
        if (!mounted) return;
        setState(() => _createLimits = latest);
        if (!latest.canStartCreateAsOwner(_selectedGroupType)) {
          _showQuotaBlockedNotice(context);
          return;
        }
        price = latest.communityCreatePrice;
      } catch (e) {
        debugPrint('load Community creation price failed: $e');
      }
      if (price == null || !price.isValid) {
        ToastUtils.toastForce(
          AppI18n.of(context).t(
              zhHans: '暂时无法获取超级大群价格，请重试',
              zhHant: '暫時無法取得超級大群價格，請重試',
              en: 'Unable to load the super group price. Please retry.',
              ja: '料金を取得できません。再試行してください。',
              ko: '가격을 불러올 수 없습니다. 다시 시도해 주세요.'),
          context: context,
        );
        return;
      }
      if (!await WalletPayPinGuard.ensureSet(context) || !mounted) return;
      payPin = await _promptCommunityPayPin(context, price);
      if (payPin == null || !mounted) return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onCreate(
        _CreateGroupDraft(
          groupName: groupName,
          introduction:
              widget.channelMode ? _introController.text.trim() : null,
          faceUrl: _selectedAvatarUrl,
          localAvatarPath: _selectedLocalAvatarPath,
          localAvatarBytes: _selectedLocalAvatarBytes,
          groupType: _selectedGroupType,
          memberUserIds: normalizeMemberUserIds(widget.members),
          payPin: payPin,
          clientRequestId: _isCommunitySelected && !widget.channelMode
              ? _communityRequestId
              : null,
          expectedPriceCurrency: price?.currency,
          expectedPriceMinor: price?.amountMinor,
        ),
      );
      if (_isCommunitySelected && mounted) await _loadCreateLimits();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _formatCommunityPrice(CommunityCreatePrice price) {
    final parts = price.displayAmount.split('.');
    final fraction = parts.length > 1 ? parts[1] : '';
    return '${parts[0]}.${fraction.padRight(2, '0')}';
  }

  bool _openingCommunityPayPin = false;

  Future<String?> _promptCommunityPayPin(
      BuildContext context, CommunityCreatePrice price) async {
    if (_openingCommunityPayPin) return null;
    _openingCommunityPayPin = true;
    String? pin;
    final i18n = AppI18n.of(context);
    try {
      var balanceText = i18n.t(
          zhHans: '余额暂不可用',
          zhHant: '餘額暫不可用',
          en: 'Balance unavailable',
          ja: '残高を取得できません',
          ko: '잔액 확인 불가');
      String? logoUrl;
      try {
        final wallet = await WalletApi.instance.getCurrencies();
        final coin = wallet.currencies.firstWhere(
            (item) => item.code.toUpperCase() == price.currency.toUpperCase());
        final expectedDecimals = price.currency == '99' ? 2 : 6;
        if (coin.decimals != expectedDecimals)
          throw StateError('Currency scale mismatch');
        final available = CommunityCreatePrice(
                currency: price.currency, amountMinor: coin.availableAmount)
            .displayAmount;
        balanceText =
            '${i18n.t(zhHans: '可用余额', zhHant: '可用餘額', en: 'Available balance', ja: '利用可能残高', ko: '사용 가능 잔액')}：$available ${price.currency}';
        logoUrl = coin.logoUrl;
      } catch (_) {
        // A failed balance request must not display a fabricated zero.
      }
      if (!context.mounted) return null;
      final confirmed = await PayPasswordPrompt.show(
        context,
        title: i18n.t(
            zhHans: '创建超级大群',
            zhHant: '建立超級大群',
            en: 'Create super group',
            ja: 'スーパーグループを作成',
            ko: '슈퍼 그룹 생성'),
        amountText: _formatCommunityPrice(price),
        amountCoin: price.currency,
        payText: i18n.t(
            zhHans: '钱包余额',
            zhHant: '錢包餘額',
            en: 'Wallet balance',
            ja: 'ウォレット残高',
            ko: '지갑 잔액'),
        payCoinCode: price.currency,
        payLogoUrl: logoUrl,
        walletSubtitle: balanceText,
        onSubmit: (value) async {
          pin = value;
          return null;
        },
      );
      return confirmed == true ? pin : null;
    } finally {
      _openingCommunityPayPin = false;
    }
  }

  String _pageTitle(AppI18n i18n) {
    if (widget.channelMode) {
      return i18n.t(
          zhHans: '创建频道',
          zhHant: '建立頻道',
          en: 'Create Channel',
          ja: 'チャンネルを作成',
          ko: '채널 만들기');
    }
    return _isCommunitySelected
        ? i18n.t(
            zhHans: '新建社群',
            zhHant: '新建社群',
            en: 'New Community',
            ja: 'コミュニティを作成',
            ko: '커뮤니티 만들기',
          )
        : i18n.t(
            zhHans: '新建群聊',
            zhHant: '新建群聊',
            en: 'New Group',
            ja: 'グループを作成',
            ko: '그룹 만들기',
          );
  }

  Widget _buildMobileCard(Widget child) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  void _returnToMemberPicker() {
    Navigator.of(context).pop(_CreateGroupDraft(
      groupName: _nameController.text,
      faceUrl: _selectedAvatarUrl,
      localAvatarPath: _selectedLocalAvatarPath,
      localAvatarBytes: _selectedLocalAvatarBytes,
      groupType: _selectedGroupType,
      memberUserIds: normalizeMemberUserIds(widget.members),
    ));
  }

  Widget _buildMobileTypeChoice({
    required String type,
    required String label,
    required String subtitle,
    required String description,
    required Color color,
  }) {
    final selected = _selectedGroupType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedGroupType = type),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.07) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E9F4),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: type == GroupType.Community
                          ? GroupRoleCrownIcon(
                              color: color, highlightColor: color, size: 23)
                          : Icon(Icons.people_alt_rounded,
                              color: color, size: 23),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 18),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: selected
                                      ? color
                                      : const Color(0xFF192134),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(subtitle,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                color: selected
                                    ? color.withValues(alpha: 0.8)
                                    : const Color(0xFF64728B),
                              )),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(description,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: Color(0xFF75839C),
                              )),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 17,
                  color: selected ? color : const Color(0xFFB7C4D7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileDetailLine(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, height: 1.35, color: Color(0xFF576985))),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTypeDetails(
      {required bool community, required AppI18n i18n}) {
    const blue = Color(0xFF1677EE);
    const orange = Color(0xFFFF710A);
    final color = community ? orange : blue;
    final joinInfo = community
        ? _createLimits?.communityJoinGroups
        : _createLimits?.joinGroups;
    final price = _createLimits?.communityCreatePrice;
    final currencyLabel = price?.currency == '99'
        ? i18n.t(
            zhHans: '99币',
            zhHant: '99幣',
            en: '99 coins',
            ja: '99コイン',
            ko: '99 코인')
        : price?.currency ?? '';
    final priceText = price != null && price.isValid
        ? i18n.format(
            zhHans: price.currency == '99'
                ? '{amount}个 {currency}'
                : '{amount} {currency}',
            zhHant: price.currency == '99'
                ? '{amount}個 {currency}'
                : '{amount} {currency}',
            en: '{amount} {currency}',
            ja: '{amount} {currency}',
            ko: '{amount} {currency}',
            vars: {
                'amount': _formatCommunityPrice(price),
                'currency': currencyLabel
              })
        : i18n.t(
            zhHans: '价格加载中',
            zhHant: '價格載入中',
            en: 'Loading price',
            ja: '料金を読み込み中',
            ko: '가격 불러오는 중');
    return Column(
      children: [
        Align(
          alignment: Alignment(community ? 0.5 : -0.5, 0),
          child: SizedBox(
            width: 24,
            height: 10,
            child: ClipRect(
              child: Stack(children: [
                Positioned(
                  top: 4,
                  left: 4,
                  child: Transform.rotate(
                    angle: 0.7853981634,
                    child: Container(
                      width: 16,
                      height: 16,
                      color: community
                          ? const Color(0xFFFFF2DE)
                          : const Color(0xFFEDF5FF),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(12, 10, 12, community ? 10 : 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: community
                  ? const [Color(0xFFFFF2DE), Color(0xFFFFF8EF)]
                  : const [Color(0xFFEDF5FF), Color(0xFFF2F8FF)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            children: [
              if (community)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRect(
                      child: Stack(children: [
                        Positioned(
                          right: -90,
                          bottom: 10,
                          child: Transform.rotate(
                            angle: -0.5,
                            child: Container(
                              width: 260,
                              height: 140,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(100),
                                color: const Color(0xFFFFD79A)
                                    .withValues(alpha: 0.14),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 62,
                          child: GroupRoleCrownIcon(
                            size: 100,
                            color:
                                const Color(0xFFFFCD82).withValues(alpha: 0.23),
                            highlightColor:
                                const Color(0xFFFFCD82).withValues(alpha: 0.23),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.10),
                        ),
                        child: Center(
                          child: community
                              ? GroupRoleCrownIcon(
                                  color: color, highlightColor: color, size: 19)
                              : Icon(Icons.people_alt_rounded,
                                  size: 19, color: color),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        fit: community ? FlexFit.loose : FlexFit.tight,
                        child: Text(
                          community
                              ? i18n.t(
                                  zhHans: '超级大群',
                                  zhHant: '超級大群',
                                  en: 'Super Group',
                                  ja: 'スーパーグループ',
                                  ko: '슈퍼 그룹')
                              : i18n.t(
                                  zhHans: '普通群',
                                  zhHant: '普通群',
                                  en: 'Standard Group',
                                  ja: '通常グループ',
                                  ko: '일반 그룹'),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color:
                                  community ? const Color(0xFF853B10) : color),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          community
                              ? i18n.t(
                                  zhHans: '付费创建',
                                  zhHant: '付費建立',
                                  en: 'Paid creation',
                                  ja: '有料で作成',
                                  ko: '유료 생성')
                              : i18n.t(
                                  zhHans: '免费创建',
                                  zhHant: '免費建立',
                                  en: 'Free to create',
                                  ja: '無料で作成',
                                  ko: '무료 생성'),
                          style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 14, color: color.withValues(alpha: 0.12)),
                  _buildMobileDetailLine(
                    community
                        ? i18n.t(
                            zhHans: '最多可容纳 10 万名成员',
                            zhHant: '最多可容納 10 萬名成員',
                            en: 'Up to 100,000 members',
                            ja: '最大10万人',
                            ko: '최대 10만 명')
                        : i18n.t(
                            zhHans: '最多可容纳 6000 名成员',
                            zhHant: '最多可容納 6000 名成員',
                            en: 'Up to 6,000 members',
                            ja: '最大6,000人',
                            ko: '최대 6,000명'),
                    color,
                  ),
                  _buildMobileDetailLine(
                    community
                        ? i18n.t(
                            zhHans: '适合大型社区、组织等使用',
                            zhHant: '適合大型社區、組織等使用',
                            en: 'For large communities and organizations',
                            ja: '大規模なコミュニティ向け',
                            ko: '대규모 커뮤니티용')
                        : i18n.t(
                            zhHans: '创建数量不限制',
                            zhHant: '建立數量不限制',
                            en: 'Unlimited creation',
                            ja: '作成数に制限なし',
                            ko: '생성 수 제한 없음'),
                    color,
                  ),
                  _buildMobileDetailLine(
                    community
                        ? i18n.t(
                            zhHans: '功能更强大，管理更高效',
                            zhHant: '功能更強大，管理更高效',
                            en: 'More tools for group management',
                            ja: '充実した管理機能',
                            ko: '강력한 관리 기능')
                        : i18n.t(
                            zhHans: '每位用户最多加入 10000 个普通群',
                            zhHant: '每位用戶最多加入 10000 個普通群',
                            en: 'Join up to 10,000 standard groups',
                            ja: '通常グループに最大1万件参加',
                            ko: '일반 그룹 최대 1만 개 참여'),
                    color,
                  ),
                  if (!community &&
                      joinInfo != null &&
                      _createLimits?.enabled == true)
                    _buildMobileDetailLine(
                      i18n.format(
                          zhHans: '还可加入 {option1} 个',
                          zhHant: '還可加入 {option1} 個',
                          en: '{option1} joins remaining',
                          ja: 'あと{option1}件参加できます',
                          ko: '{option1}개 더 참여 가능',
                          vars: {'option1': '${joinInfo.remaining}'}),
                      color,
                    ),
                  if (community) ...[
                    const SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFFFFE7BE),
                          Color(0xFFFFF1E1),
                          Color(0xFFFFE9CB),
                        ]),
                        border: Border.all(color: const Color(0xFFFFD6A4)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        SizedBox(
                          width: 64,
                          height: 48,
                          child: Center(
                            child: Transform.scale(
                                scale: 1.3, child: _buildGroupCreationCoins()),
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 40,
                            color: const Color(0xFFFFC88C)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                i18n.t(
                                    zhHans: '超级大群创建费用：',
                                    zhHant: '超級大群建立費用：',
                                    en: 'Super group creation fee:',
                                    ja: 'スーパーグループ作成料金：',
                                    ko: '슈퍼 그룹 생성 비용:'),
                                maxLines: 1,
                                style: const TextStyle(
                                    color: Color(0xFF853B10),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        price != null &&
                                                price.isValid &&
                                                price.currency == '99'
                                            ? _formatCommunityPrice(price)
                                            : priceText,
                                        maxLines: 1,
                                        style: const TextStyle(
                                            color: Color(0xFFFF5B08),
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            height: 1.15)),
                                    if (price != null &&
                                        price.isValid &&
                                        price.currency == '99') ...[
                                      const SizedBox(width: 6),
                                      Semantics(
                                          label: currencyLabel,
                                          child:
                                              const PlatformCoinIcon(size: 24)),
                                    ],
                                  ]),
                            ),
                          ],
                        )),
                      ]),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupCreationCoins() {
    return Image.asset(
      'assets/img/community_creation_coins.png',
      width: 38,
      height: 38,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }

  Widget _buildMobileFormBody(AppI18n i18n, TUITheme theme) {
    const titleColor = Color(0xFF192134);
    const secondary = Color(0xFF71809A);
    const blue = Color(0xFF1677EE);
    final titleStyle = const TextStyle(
        fontSize: 17, fontWeight: FontWeight.w700, color: titleColor);
    final hasLocalAvatar = _selectedLocalAvatarPath.isNotEmpty ||
        (_selectedLocalAvatarBytes?.isNotEmpty ?? false);
    final priceHint =
        GroupCreateLimitMessage.memberCapacityShortHint(GroupType.Community);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        _buildMobileCard(InkWell(
          onTap: () => _onTapGroupAvatar(theme),
          child: Row(
            children: [
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      i18n.t(
                          zhHans: '群头像',
                          zhHant: '群頭像',
                          en: 'Group Avatar',
                          ja: 'グループアイコン',
                          ko: '그룹 프로필'),
                      style: titleStyle),
                  const SizedBox(height: 6),
                  Text(
                      i18n.t(
                          zhHans: '设置一个有特色的群头像吧',
                          zhHant: '設定一個有特色的群頭像吧',
                          en: 'Give your group a distinctive avatar',
                          ja: 'グループのアイコンを設定',
                          ko: '그룹 프로필을 설정하세요'),
                      style: const TextStyle(fontSize: 12, color: secondary)),
                ],
              )),
              Container(
                width: 58,
                height: 58,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0xFF82A8E8)),
                child: hasLocalAvatar
                    ? _buildLocalAvatarImage()
                    : Avatar(
                        faceUrl: _selectedAvatarUrl,
                        showName: _nameController.text.trim(),
                        type: 2,
                        borderRadius: BorderRadius.circular(29),
                        isFromLocalAsset:
                            _selectedAvatarUrl.startsWith('assets/'),
                      ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: secondary),
            ],
          ),
        )),
        _buildMobileCard(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                i18n.t(
                    zhHans: '群名称',
                    zhHant: '群名稱',
                    en: 'Group Name',
                    ja: 'グループ名',
                    ko: '그룹 이름'),
                style: titleStyle),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF3F6FB),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                    child: TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  maxLength: 30,
                  decoration: InputDecoration(
                    filled: false,
                    fillColor: Colors.transparent,
                    hintText: i18n.t(
                        zhHans: '请输入群名称',
                        zhHant: '請輸入群名稱',
                        en: 'Enter group name',
                        ja: 'グループ名を入力',
                        ko: '그룹 이름 입력'),
                    hintStyle: const TextStyle(color: secondary),
                    border: InputBorder.none,
                    counterText: '',
                  ),
                )),
                Text('${_nameController.text.characters.length}/30',
                    style: const TextStyle(fontSize: 12, color: secondary)),
              ]),
            ),
          ],
        )),
        if (widget.showGroupTypeSelector)
          _buildMobileCard(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  i18n.t(
                      zhHans: '群类型',
                      zhHant: '群類型',
                      en: 'Group Type',
                      ja: 'グループタイプ',
                      ko: '그룹 유형'),
                  style: titleStyle),
              const SizedBox(height: 5),
              Text(
                  i18n.t(
                      zhHans: '选择适合的群类型，满足不同的沟通需求',
                      zhHant: '選擇適合的群類型，滿足不同的溝通需求',
                      en: 'Choose the group type that fits your needs',
                      ja: '用途に合ったグループを選択',
                      ko: '목적에 맞는 그룹 유형을 선택하세요'),
                  style: const TextStyle(fontSize: 12, color: secondary)),
              const SizedBox(height: 10),
              Row(children: [
                _buildMobileTypeChoice(
                    type: GroupType.Public,
                    label: i18n.t(
                        zhHans: '普通群',
                        zhHant: '普通群',
                        en: 'Standard Group',
                        ja: '通常グループ',
                        ko: '일반 그룹'),
                    subtitle: GroupCreateLimitMessage.memberCapacityShortHint(
                        GroupType.Public),
                    description: i18n.t(
                        zhHans: '适合日常群聊与协作',
                        zhHant: '適合日常群聊與協作',
                        en: 'For everyday chat',
                        ja: '日常の会話に',
                        ko: '일상 대화에 적합'),
                    color: blue),
                const SizedBox(width: 8),
                _buildMobileTypeChoice(
                    type: GroupType.Community,
                    label: i18n.t(
                        zhHans: '超级大群',
                        zhHant: '超級大群',
                        en: 'Super Group',
                        ja: 'スーパーグループ',
                        ko: '슈퍼 그룹'),
                    subtitle: priceHint,
                    description: i18n.t(
                        zhHans: '适合大型社区、组织等',
                        zhHant: '適合大型社區、組織等',
                        en: 'For large communities',
                        ja: '大規模なコミュニティに',
                        ko: '대규모 커뮤니티에 적합'),
                    color: const Color(0xFFF47525)),
              ]),
              const SizedBox(height: 4),
              _buildMobileTypeDetails(
                  community: _selectedGroupType == GroupType.Community,
                  i18n: i18n),
            ],
          ))
        else
          _buildMobileCard(_buildCreateLimitHint(theme)),
        _buildMobileCard(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(
                      i18n.format(
                          zhHans: '群成员（{option1}）',
                          zhHant: '群成員（{option1}）',
                          en: 'Members ({option1})',
                          ja: 'メンバー（{option1}）',
                          ko: '멤버 ({option1})',
                          vars: {'option1': '${widget.members.length}'}),
                      style: titleStyle)),
              TextButton.icon(
                onPressed: _returnToMemberPicker,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                label: Text(i18n.t(
                    zhHans: '添加成员',
                    zhHant: '新增成員',
                    en: 'Add members',
                    ja: 'メンバーを追加',
                    ko: '멤버 추가')),
                style: TextButton.styleFrom(
                    foregroundColor: blue, padding: EdgeInsets.zero),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 12, children: [
              ...widget.members.map((item) => _buildMemberItem(item, theme)),
              InkWell(
                onTap: _returnToMemberPicker,
                borderRadius: BorderRadius.circular(30),
                child: SizedBox(
                    width: 60,
                    child: Column(children: [
                      Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFFB7D5FF),
                                  style: BorderStyle.solid)),
                          child: const Icon(Icons.add_rounded, color: blue)),
                      const SizedBox(height: 6),
                      Text(
                          i18n.t(
                              zhHans: '添加成员',
                              zhHant: '新增成員',
                              en: 'Add',
                              ja: '追加',
                              ko: '추가'),
                          maxLines: 1,
                          style:
                              const TextStyle(fontSize: 11, color: secondary)),
                    ])),
              ),
            ]),
            const SizedBox(height: 18),
            InkWell(
              onTap: () => Navigator.of(context).push(AppMaterialPageRoute(
                  builder: (_) => const TermsOfServicePage())),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF3F6FB),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.verified_user_outlined,
                      color: blue, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          GroupCreateLimitMessage.createGroupDeclaration(),
                          style: const TextStyle(
                              fontSize: 11, color: secondary, height: 1.4))),
                  const Icon(Icons.chevron_right_rounded, color: secondary),
                ]),
              ),
            ),
          ],
        )),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildDesktopConfirmChrome({
    required AppI18n i18n,
    required TUITheme theme,
    required Color pageBackgroundColor,
    required Color cardBackgroundColor,
    required Color dividerColor,
  }) {
    final titleColor = theme.darkTextColor ?? const Color(0xFF111827);
    final primary = theme.primaryColor ?? const Color(0xFF1E90FF);
    final weak = theme.weakTextColor ?? const Color(0xFF9CA3AF);

    Widget sectionCard({required Widget child}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: cardBackgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dividerColor.withValues(alpha: 0.7)),
        ),
        child: child,
      );
    }

    final leftPane = AbsorbPointer(
      absorbing: _submitting,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
        children: [
          sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGroupAvatar(theme),
                Divider(height: 28, thickness: 1, color: dividerColor),
                _buildGroupNameInput(theme),
                if (!widget.showGroupTypeSelector) ...[
                  const SizedBox(height: 12),
                  _buildCreateLimitHint(theme),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.format(
                    zhHans: '群成员({option1})',
                    zhHant: '群成員({option1})',
                    en: 'Members ({option1})',
                    ja: 'メンバー({option1})',
                    ko: '멤버({option1})',
                    vars: {'option1': '${widget.members.length}'},
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 14),
                if (widget.members.isEmpty)
                  Text(
                    i18n.t(
                      zhHans: '暂无其他成员，创建后可再邀请',
                      zhHant: '暫無其他成員，建立後可再邀請',
                      en: 'No other members yet. You can invite later.',
                      ja: '他のメンバーはいません。後で招待できます。',
                      ko: '다른 멤버 없음. 나중에 초대할 수 있습니다.',
                    ),
                    style: TextStyle(fontSize: 13, color: weak, height: 1.4),
                  )
                else
                  Wrap(
                    spacing: 14,
                    runSpacing: 12,
                    children: widget.members
                        .map((item) => _buildMemberItem(item, theme))
                        .toList(),
                  ),
                const SizedBox(height: 14),
                _buildCreateGroupDeclaration(theme),
              ],
            ),
          ),
        ],
      ),
    );

    final rightPane = AbsorbPointer(
      absorbing: _submitting,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 16, 20, 20),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: cardBackgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dividerColor.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.t(
                zhHans: '群类型',
                zhHant: '群類型',
                en: 'Group Type',
                ja: 'グループタイプ',
                ko: '그룹 유형',
              ),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              i18n.t(
                zhHans: '创建后类型不可更改，请按规模选择',
                zhHant: '建立後類型不可更改，請按規模選擇',
                en: 'Type can’t be changed later. Pick by size.',
                ja: '作成後は変更できません。規模で選んでください。',
                ko: '생성 후 유형 변경 불가. 규모에 맞게 선택하세요.',
              ),
              style: TextStyle(fontSize: 12, color: weak, height: 1.35),
            ),
            const SizedBox(height: 16),
            if (widget.showGroupTypeSelector)
              _buildDesktopGroupTypeOptions(theme)
            else
              _buildCreateLimitHint(theme),
            const SizedBox(height: 14),
            _buildSelectedGroupTypeDescription(theme),
            const Spacer(),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed:
                    _submitting ? null : () => _handleCreatePressed(context),
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: primary.withValues(alpha: 0.45),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        i18n.t(
                          zhHans: '创建',
                          zhHant: '建立',
                          en: 'Create',
                          ja: '作成',
                          ko: '만들기',
                        ),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );

    return Material(
      color: pageBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.fromLTRB(8, 0, 20, 0),
            decoration: BoxDecoration(
              color: cardBackgroundColor,
              border: Border(
                bottom: BorderSide(color: dividerColor.withValues(alpha: 0.85)),
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
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: primary,
                  ),
                ),
                Expanded(
                  child: Text(
                    _pageTitle(i18n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 11, child: leftPane),
                Container(width: 1, color: dividerColor.withValues(alpha: 0.7)),
                Expanded(flex: 9, child: rightPane),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Web 右侧栏：群类型纵向选项，比手机横排更易扫读。
  Widget _buildDesktopGroupTypeOptions(TUITheme theme) {
    final i18n = AppI18n.of(context);
    return Column(
      children: [
        _buildDesktopGroupTypeOption(
          theme: theme,
          value: GroupType.Public,
          label: i18n.t(
            zhHans: '普通群',
            zhHant: '普通群',
            en: 'Standard Group',
            ja: '通常グループ',
            ko: '일반 그룹',
          ),
          subtitle: GroupCreateLimitMessage.memberCapacityShortHint(
            GroupType.Public,
          ),
        ),
        const SizedBox(height: 10),
        _buildDesktopGroupTypeOption(
          theme: theme,
          value: GroupType.Community,
          label: i18n.t(
            zhHans: '超级大群',
            zhHant: '超級大群',
            en: 'Super Group',
            ja: 'スーパーグループ',
            ko: '슈퍼 그룹',
          ),
          subtitle: GroupCreateLimitMessage.memberCapacityShortHint(
            GroupType.Community,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopGroupTypeOption({
    required TUITheme theme,
    required String value,
    required String label,
    String? subtitle,
  }) {
    final selected = _selectedGroupType == value;
    final primary = theme.primaryColor ?? const Color(0xFF1E90FF);
    final fillColor = theme.inputFillColor ??
        theme.selectPanelBgColor ??
        const Color(0xFFF1F2F6);
    final titleColor = theme.darkTextColor ?? Colors.black;
    final weak = theme.weakTextColor ?? const Color(0xFF999999);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_selectedGroupType == value) {
            return;
          }
          setState(() => _selectedGroupType = value);
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.10) : fillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? primary : titleColor,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color:
                              selected ? primary.withValues(alpha: 0.85) : weak,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 22,
                color: selected ? primary : weak.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelForm(AppI18n i18n, TUITheme theme) {
    const background = Color(0xFFF4F7FD);
    const blue = Color(0xFF2388F0);
    const hint = Color(0xFFB3B7BF);
    final hasLocalAvatar = _selectedLocalAvatarPath.isNotEmpty ||
        (_selectedLocalAvatarBytes?.isNotEmpty ?? false);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 96,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          label: Text(i18n.t(
              zhHans: '返回', zhHant: '返回', en: 'Back', ja: '戻る', ko: '뒤로')),
          style: TextButton.styleFrom(
              foregroundColor: blue, padding: EdgeInsets.zero),
        ),
        title: Text(_pageTitle(i18n),
            style: const TextStyle(
                color: Color(0xFF172033),
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 42, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 94,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  InkWell(
                    key: const ValueKey('channel-avatar'),
                    onTap: () => _onTapGroupAvatar(theme),
                    borderRadius: BorderRadius.circular(38),
                    child: Container(
                      width: 70,
                      height: 70,
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Color(0xFFE9F4FF)),
                      child: hasLocalAvatar
                          ? _buildLocalAvatarImage()
                          : _selectedAvatarUrl.isNotEmpty
                              ? Avatar(
                                  faceUrl: _selectedAvatarUrl,
                                  showName: _nameController.text.trim(),
                                  type: 2,
                                  borderRadius: BorderRadius.circular(35),
                                  isFromLocalAsset:
                                      _selectedAvatarUrl.startsWith('assets/'))
                              : const Icon(Icons.camera_alt_rounded,
                                  color: blue, size: 34),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                    key: const ValueKey('channel-name'),
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    maxLength: 30,
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: i18n.t(
                          zhHans: '频道名称',
                          zhHant: '頻道名稱',
                          en: 'Channel name',
                          ja: 'チャンネル名',
                          ko: '채널 이름'),
                      hintStyle: const TextStyle(color: hint),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    style:
                        const TextStyle(fontSize: 18, color: Color(0xFF172033)),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10)),
                child: TextField(
                  key: const ValueKey('channel-introduction'),
                  controller: _introController,
                  maxLength: 200,
                  decoration: InputDecoration(
                    filled: false,
                    fillColor: Colors.transparent,
                    hintText: i18n.t(
                        zhHans: '频道简介（选填）',
                        zhHant: '頻道簡介（選填）',
                        en: 'Channel description (optional)',
                        ja: 'チャンネルの説明（任意）',
                        ko: '채널 소개 (선택)'),
                    hintStyle: const TextStyle(color: hint),
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                  i18n.t(
                      zhHans: '为频道设置简介',
                      zhHant: '為頻道設定簡介',
                      en: 'Add a description for your channel',
                      ja: 'チャンネルの説明を設定',
                      ko: '채널 소개를 설정하세요'),
                  style:
                      const TextStyle(color: Color(0xFF7A8494), fontSize: 13)),
              const SizedBox(height: 44),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  key: const ValueKey('channel-next'),
                  onPressed: _submitting ||
                          _nameController.text.trim().isEmpty ||
                          !_hasChannelAvatar
                      ? null
                      : () => _handleCreatePressed(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    disabledBackgroundColor: const Color(0xFFDDE0E6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          i18n.t(
                              zhHans: '下一步',
                              zhHant: '下一步',
                              en: 'Next',
                              ja: '次へ',
                              ko: '다음'),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final theme = Provider.of<DefaultThemeData>(context).theme;
    if (widget.channelMode) return _buildChannelForm(i18n, theme);
    final appBarBaseColor =
        theme.appbarBgColor ?? theme.wideBackgroundColor ?? Colors.white;
    final isDarkBackground =
        ThemeData.estimateBrightnessForColor(appBarBaseColor) ==
            Brightness.dark;
    const lightBackgroundColor = Color(0xFFF4F7FD);
    final pageBackgroundColor = isDarkBackground
        ? (theme.weakBackgroundColor ?? appBarBaseColor)
        : lightBackgroundColor;
    final appBarBackgroundColor = isDarkBackground
        ? (theme.appbarBgColor ?? theme.weakBackgroundColor ?? Colors.white)
        : lightBackgroundColor;
    final cardBackgroundColor = isDarkBackground
        ? (theme.conversationItemBgColor ??
            theme.wideBackgroundColor ??
            const Color(0xFF1C1C1E))
        : Colors.white;
    final dividerColor = theme.weakDividerColor ?? const Color(0xFFE5E5E5);
    final overlayStyle = _buildPageOverlayStyle(
      isDarkBackground: isDarkBackground,
      pageBackgroundColor: pageBackgroundColor,
    );

    if (widget.embeddedInDesktopPopup) {
      return _buildDesktopConfirmChrome(
        i18n: i18n,
        theme: theme,
        pageBackgroundColor: pageBackgroundColor,
        cardBackgroundColor: cardBackgroundColor,
        dividerColor: dividerColor,
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: pageBackgroundColor,
        appBar: AppBar(
          systemOverlayStyle: overlayStyle,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: Text(
            widget.channelMode
                ? _pageTitle(i18n)
                : i18n.t(
                    zhHans: '新建群聊',
                    zhHant: '新建群聊',
                    en: 'New Group',
                    ja: 'グループを作成',
                    ko: '그룹 만들기',
                  ),
            style: TextStyle(
              color:
                  theme.appbarTextColor ?? theme.darkTextColor ?? Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          shadowColor: theme.weakDividerColor,
          backgroundColor: appBarBackgroundColor,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(
            color: theme.primaryColor ?? const Color(0xFF1E90FF),
          ),
          leading: AppBackButton(
            color: isDarkBackground
                ? (theme.appbarTextColor ?? Colors.white)
                : const Color(0xFF192134),
          ),
          actions: [
            TextButton(
              onPressed:
                  _submitting ? null : () => _handleCreatePressed(context),
              child: _submitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.primaryColor ?? const Color(0xFF1E90FF),
                      ),
                    )
                  : Text(
                      AppI18n.of(context).t(
                        zhHans: '创建',
                        zhHant: '建立',
                        en: 'Create',
                        ja: '作成',
                        ko: '만들기',
                      ),
                      style: TextStyle(
                        color: theme.primaryColor ?? const Color(0xFF1E90FF),
                        fontSize: 16,
                      ),
                    ),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _submitting,
          child: SingleChildScrollView(
            child: _buildMobileFormBody(i18n, theme),
          ),
        ),
      ),
    );
  }
}

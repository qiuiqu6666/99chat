import 'package:tencent_cloud_chat_uikit/ui/widgets/group_settings_tile.dart';
import 'package:flutter/cupertino.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/language_json/strings.g.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/utils/navigation_routes.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/constants/group_governance_limits.dart';
import 'package:tencent_cloud_chat_demo/utils/group_admin_role_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/tim_uikit_wide_modal_operation_key.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_member_feedback_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_role_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tim_uikit_back_button.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/column_menu.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_ui_group_member_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/wide_popup_layout.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';

Color _groupManageSurfaceColor(TUITheme theme) {
  return theme.conversationItemBgColor ??
      theme.wideBackgroundColor ??
      Colors.white;
}

Color _groupManagePageBackground(TUITheme theme) {
  return theme.chatBgColor ??
      theme.weakBackgroundColor ??
      theme.wideBackgroundColor ??
      Colors.white;
}

/// 群管理危险操作确认：缩放淡入动画 + 震动，降低误触。
Future<bool> _confirmGroupManageAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  bool destructive = true,
}) async {
  if (!context.mounted) {
    return false;
  }
  HapticFeedback.mediumImpact();
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: CupertinoAlertDialog(
            title: Text(title),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(TIM_t('取消')),
              ),
              CupertinoDialogAction(
                isDestructiveAction: destructive,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmText),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curve),
          child: child,
        ),
      );
    },
  );
  return result == true;
}

Future<bool> _confirmEnableMuteAll(BuildContext context) {
  return _confirmGroupManageAction(
    context,
    title: TIM_t('开启全员禁言'),
    message: TIM_t('开启后，普通成员将无法在群内发言。确定开启吗？'),
    confirmText: TIM_t('开启'),
    destructive: true,
  );
}

Future<bool> _confirmDisableMuteAll(BuildContext context) {
  return _confirmGroupManageAction(
    context,
    title: TIM_t('关闭全员禁言'),
    message: TIM_t('关闭后，普通成员可恢复发言。确定关闭吗？'),
    confirmText: TIM_t('关闭'),
    destructive: true,
  );
}

Future<bool> _confirmRemoveAdmin(BuildContext context, String displayName) {
  final name = displayName.trim().isEmpty ? TIM_t('该成员') : displayName.trim();
  return _confirmGroupManageAction(
    context,
    title: TIM_t('取消管理员'),
    message: TIM_t_para(
      '确定取消「{{option1}}」的管理员身份吗？',
      '确定取消「$name」的管理员身份吗？',
    )(option1: name),
    confirmText: TIM_t('取消管理员'),
    destructive: true,
  );
}

GlobalKey<_GroupProfileAddAdminState> groupProfileAddAdminKey = GlobalKey();

class GroupProfileGroupManage extends StatefulWidget {
  const GroupProfileGroupManage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => GroupProfileGroupManageState();
}

class GroupProfileGroupManageState
    extends TIMUIKitState<GroupProfileGroupManage> {
  bool isShowManageBox = false;

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final tr = Translations.of(context);
    final TUITheme theme = value.theme;
    final isDesktopScreen =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final model = Provider.of<TUIGroupProfileModel>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: _groupManageSurfaceColor(theme),
          border: isDesktopScreen
              ? null
              : Border(
                  bottom: BorderSide(
                      color: theme.weakDividerColor ??
                          CommonColor.weakDividerColor))),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              final isDesktopScreen =
                  TUIKitScreenUtils.getFormFactor(context) ==
                      DeviceType.Desktop;
              if (!isDesktopScreen) {
                Navigator.push(
                    context,
                    NavigationRoutes.push(
                        builder: (context) => GroupProfileGroupManagePage(
                              model: model,
                            )));
              } else {
                setState(() {
                  isShowManageBox = !isShowManageBox;
                });
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr.k_038lh6u,
                  style: TextStyle(
                      fontSize: isDesktopScreen ? 14 : 16,
                      color: theme.darkTextColor),
                ),
                AnimatedRotation(
                  turns: isShowManageBox ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_right,
                      color: theme.weakTextColor),
                )
              ],
            ),
          ),
          if (isShowManageBox)
            GroupProfileGroupManagePage(
              model: model,
            )
        ],
      ),
    );
  }
}

/// 管理员设置页面
class GroupProfileGroupManagePage extends StatefulWidget {
  final TUIGroupProfileModel model;

  /// 插在群管理项上方的自定义区块（如加群方式、群隐私保护）。
  final List<Widget>? headerWidgets;

  /// 移动端 AppBar 标题，默认「群管理」。
  final String? appBarTitle;

  final MemberPresenceLabelBuilder? presenceLabelBuilder;
  final MemberPresenceLoadingChecker? presenceLoadingChecker;
  final MemberPresenceOnlineResolver? presenceOnlineResolver;
  final Listenable? presenceListenable;
  final void Function(List<String> userIds)? onMemberPresenceRequested;

  const GroupProfileGroupManagePage({
    Key? key,
    required this.model,
    this.headerWidgets,
    this.appBarTitle,
    this.presenceLabelBuilder,
    this.presenceLoadingChecker,
    this.presenceOnlineResolver,
    this.presenceListenable,
    this.onMemberPresenceRequested,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _GroupProfileGroupManagePageState();
}

class _GroupProfileGroupManagePageState
    extends TIMUIKitState<GroupProfileGroupManagePage> {
  int? serverTime;
  List<V2TimGroupMemberFullInfo> _mutedMembers = const [];

  Future<bool> _muteSelectedMembers(
    BuildContext context,
    List<V2TimGroupMemberFullInfo?> selectedMembers,
  ) async {
    final succeeded = <V2TimGroupMemberFullInfo>[];
    final members = selectedMembers.whereType<V2TimGroupMemberFullInfo>().toList();
    for (final member in members) {
      if (!mounted) return false;
      final result = await widget.model
          .muteGroupMember(member.userID, true, serverTime);
      if (result.code == 0) succeeded.add(member);
    }
    if (!mounted) return false;
    // Failed requests must not appear in the local muted list.
    _upsertMutedMembersFromSelection(succeeded);
    final failed = members.length - succeeded.length;
    if (succeeded.isEmpty) {
      GroupMemberFeedbackBridge.show(TIM_t('设置禁言失败，请重试'));
      return false;
    }
    GroupMemberFeedbackBridge.show(failed == 0
        ? TIM_t('设置禁言成功')
        : '已禁言 ${succeeded.length} 人，$failed 人失败，请重试');
    return failed == 0;
  }

  Future<bool> _unmuteMember(V2TimGroupMemberFullInfo member) async {
    final result = await widget.model
        .muteGroupMember(member.userID, false, serverTime);
    if (!mounted) return false;
    if (result.code != 0) {
      GroupMemberFeedbackBridge.show(TIM_t('解除禁言失败，请重试'));
      return false;
    }
    _removeMutedMemberLocally(member.userID);
    GroupMemberFeedbackBridge.show(TIM_t('解除禁言成功'));
    return true;
  }

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(widget.model.loadManagementMembers));
    unawaited(_bootstrapManagePage());
  }

  Future<void> _bootstrapManagePage() async {
    await _refreshServerTime();
    final groupId = widget.model.groupID.trim();
    if (groupId.isEmpty) {
      return;
    }
    await widget.model.loadGroupInfo(groupId);
    // Ordinary candidates are requested only when the mute picker opens.
    await _refreshMutedMembers();
  }

  Future<void> _refreshServerTime() async {
    final res = await TencentImSDKPlugin.v2TIMManager.getServerTime();
    if (!mounted) {
      return;
    }
    setState(() {
      serverTime = res.data;
    });
  }

  int get _currentCompareTime =>
      serverTime ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  List<V2TimGroupMemberFullInfo> _mergeMutedMembers(
    List<V2TimGroupMemberFullInfo> base,
    List<V2TimGroupMemberFullInfo> incoming,
  ) {
    final map = <String, V2TimGroupMemberFullInfo>{
      for (final member in base)
        if (member.userID.trim().isNotEmpty) member.userID.trim(): member,
    };
    for (final member in incoming) {
      final id = member.userID.trim();
      if (id.isNotEmpty) {
        map[id] = member;
      }
    }
    return map.values.toList(growable: false);
  }

  void _upsertMutedMembersFromSelection(
    List<V2TimGroupMemberFullInfo?> selectedMember,
  ) {
    final now = _currentCompareTime;
    final next =
        selectedMember.whereType<V2TimGroupMemberFullInfo>().map((member) {
      if ((member.muteUntil ?? 0) <= now) {
        member.muteUntil = now + 315360000;
      }
      return member;
    }).toList(growable: false);
    if (next.isEmpty) {
      return;
    }
    setState(() {
      _mutedMembers = _mergeMutedMembers(_mutedMembers, next);
    });
  }

  void _removeMutedMemberLocally(String userId) {
    final id = userId.trim();
    if (id.isEmpty) {
      return;
    }
    setState(() {
      _mutedMembers =
          _mutedMembers.where((member) => member.userID.trim() != id).toList();
    });
  }

  Future<void> _refreshMutedMembers({bool keepExistingOnEmpty = false}) async {
    final groupId = widget.model.groupID.trim();
    if (groupId.isEmpty) {
      return;
    }
    final res = await MeGroupApi.instance.fetchMutedMembers(groupId);
    if (!mounted || res == null) {
      return;
    }
    setState(() {
      widget.model.groupInfo?.isAllMuted = res.isAllMuted;
      final next =
          res.members.map(_mutedRecordToMemberInfo).toList(growable: false);
      if (next.isEmpty && keepExistingOnEmpty && _mutedMembers.isNotEmpty) {
        return;
      }
      _mutedMembers = next;
    });
  }

  V2TimGroupMemberFullInfo _mutedRecordToMemberInfo(
    MutedGroupMemberRecord record,
  ) {
    V2TimGroupMemberFullInfo? localMember;
    for (final member in widget.model.groupMemberList) {
      if (member?.userID.trim() == record.userId) {
        localMember = member;
        break;
      }
    }
    return V2TimGroupMemberFullInfo(
      userID: record.userId,
      muteUntil: record.muteUntilSec,
      nameCard:
          record.nameCard.isNotEmpty ? record.nameCard : localMember?.nameCard,
      nickName: localMember?.nickName,
      friendRemark: localMember?.friendRemark,
      faceUrl: localMember?.faceUrl,
      role: _roleFromApi(record.imRole, fallback: localMember?.role),
    );
  }

  int _roleFromApi(String role, {int? fallback}) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER;
      case 'admin':
        return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN;
      case 'member':
        return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
      default:
        return fallback ?? GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
    }
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: widget.model),
          ChangeNotifierProvider.value(
              value: serviceLocator<TUIThemeViewModel>())
        ],
        builder: (context, w) {
          final tr = Translations.of(context);
          final model = Provider.of<TUIGroupProfileModel>(context);
          final theme = Provider.of<TUIThemeViewModel>(context).theme;
          final isAllMuted = model.groupInfo?.isAllMuted ?? false;
          final groupType = model.groupInfo?.groupType ?? '';
          final bool isAllowSetManager = groupType != GroupType.Work;
          final bool isAllowMuteMember = groupType != GroupType.Work;
          final isDesktopScreen =
              TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
          Widget managePage() {
            if (!model.hasLoadedManagementMembers) {
              return Center(child: model.hasManagementMemberListError
                  ? TextButton(onPressed: model.loadManagementMembers,
                      child: Text(TIM_t('群管理权限加载失败，点击重试')))
                  : const CircularProgressIndicator());
            }
            if (!GroupRolePolicy.isManagerRole(model.backendSelfRole)) {
              return Center(child: Text(TIM_t('只有群主或管理员可以管理群')));
            }
            return Column(
              children: [
                if (widget.headerWidgets != null &&
                    widget.headerWidgets!.isNotEmpty) ...[
                  ...widget.headerWidgets!,
                  if (!isDesktopScreen)
                    Container(
                      height: 8,
                      color: _groupManagePageBackground(theme),
                    ),
                ],
                if (isAllowSetManager) ...[
                  GroupSettingsTile(
                    theme: theme,
                    title: isDesktopScreen ? tr.k_15i9w72 : tr.k_0k5wyiy,
                    trailing: isDesktopScreen
                        ? null
                        : Icon(Icons.keyboard_arrow_right,
                            color: theme.weakTextColor, size: 20),
                    onTap: isDesktopScreen
                        ? null
                        : () {
                            Navigator.push(
                                context,
                                NavigationRoutes.push(
                                  builder: (context) =>
                                      GroupProfileSetManagerPage(
                                    model: widget.model,
                                    presenceLabelBuilder:
                                        widget.presenceLabelBuilder,
                                    presenceLoadingChecker:
                                        widget.presenceLoadingChecker,
                                    presenceOnlineResolver:
                                        widget.presenceOnlineResolver,
                                    presenceListenable:
                                        widget.presenceListenable,
                                    onMemberPresenceRequested:
                                        widget.onMemberPresenceRequested,
                                  ),
                                ));
                          },
                  ),
                  if (isDesktopScreen)
                    GroupProfileSetManagerPage(
                      model: widget.model,
                      presenceLabelBuilder: widget.presenceLabelBuilder,
                      presenceLoadingChecker: widget.presenceLoadingChecker,
                      presenceOnlineResolver: widget.presenceOnlineResolver,
                      presenceListenable: widget.presenceListenable,
                      onMemberPresenceRequested:
                          widget.onMemberPresenceRequested,
                    ),
                ],
                if (!isDesktopScreen)
                  GroupSettingsTile(
                    theme: theme,
                    title: TIM_t("全员禁言"),
                    trailing: GroupSettingsSwitch(
                        value: isAllMuted,
                        onChanged: (value) async {
                          if (value) {
                            final confirmed =
                                await _confirmEnableMuteAll(context);
                            if (!confirmed) {
                              return;
                            }
                          } else {
                            final confirmed =
                                await _confirmDisableMuteAll(context);
                            if (!confirmed) {
                              return;
                            }
                          }
                          await widget.model.setMuteAll(value);
                        },
                        activeColor: theme.primaryColor),
                  ),
                if (isDesktopScreen)
                  GroupSettingsTile(
                    theme: theme,
                    title: tr.k_0goiuwk,
                    subtitle: tr.k_1g889xx,
                    trailing: GroupSettingsSwitch(
                      value: isAllMuted,
                      activeColor: theme.primaryColor,
                      onChanged: (value) async {
                        if (value) {
                          final confirmed =
                              await _confirmEnableMuteAll(context);
                          if (!confirmed) {
                            return;
                          }
                        } else {
                          final confirmed =
                              await _confirmDisableMuteAll(context);
                          if (!confirmed) {
                            return;
                          }
                        }
                        await widget.model.setMuteAll(value);
                      },
                    ),
                  ),
                if (!isDesktopScreen)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 16),
                    color: theme.weakBackgroundColor ??
                        theme.conversationItemPinedBgColor,
                    alignment: Alignment.topLeft,
                    child: Text(
                      tr.k_1g889xx,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.25,
                          color: theme.weakTextColor),
                    ),
                  ),
                if (!isAllMuted && isAllowMuteMember)
                  InkWell(
                    child: GroupSettingsTile(
                        theme: theme,
                        title: tr.k_0wlrefq,
                        leading: Icon(Icons.add_circle_outline,
                            color: theme.primaryColor, size: 20)),
                    onTap: () async {
                      Widget muteMember() {
                        List<V2TimGroupMemberFullInfo?> availableMembers() {
                          return widget.model.groupMemberList.where((element) {
                            final userId = element?.userID.trim() ?? '';
                            final isMute = _mutedMembers.any(
                                (member) => member.userID.trim() == userId);
                            return !isMute &&
                                widget.model.canMuteMember(userId);
                          }).toList();
                        }

                        return GroupProfileAddAdmin(
                          key: groupProfileAddAdminKey,
                          groupID: widget.model.groupID,
                          candidateFilter: (members) {
                            return members.where((element) {
                              final userId = element?.userID.trim() ?? '';
                              final isMute = _mutedMembers.any(
                                  (member) => member.userID.trim() == userId);
                              return !isMute &&
                                  widget.model.canMuteMember(userId);
                            }).toList();
                          },
                          appbarTitle: tr.k_0goox5g,
                          presenceLabelBuilder: widget.presenceLabelBuilder,
                          presenceLoadingChecker: widget.presenceLoadingChecker,
                          presenceOnlineResolver: widget.presenceOnlineResolver,
                          presenceListenable: widget.presenceListenable,
                          onMemberPresenceRequested:
                              widget.onMemberPresenceRequested,
                          memberList: availableMembers(),
                          memberListProvider: availableMembers,
                          memberListListenable: widget.model,
                          loadMembersOnEntry:
                              widget.model.loadMemberPageOnEntry,
                          onReachBottom: () =>
                              widget.model.loadMoreGroupMembers(),
                          selectCompletedHandler: _muteSelectedMembers,
                        );
                      }

                      if (isDesktopScreen) {
                        final popupSize = WidePopupLayout.large(context);
                        TUIKitWidePopup.showPopupWindow(
                            operationKey: TUIKitWideModalOperationKey.setMute,
                            context: context,
                            title: TIM_t("设置禁言"),
                            width: popupSize.width,
                            height: popupSize.height,
                            child: (onClose) => Column(children: [
                                  Expanded(child: muteMember()),
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(onPressed: onClose,
                                            child: Text(TIM_t('取消'))),
                                        const SizedBox(width: 8),
                                        FilledButton(
                                          onPressed: () async {
                                            final picker = groupProfileAddAdminKey.currentState;
                                            final success = await picker?.onSubmit();
                                            if (success == true && mounted &&
                                                picker?.mounted == true) onClose();
                                          },
                                          child: Text(TIM_t('完成')),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]));
                      } else {
                        await Navigator.push(
                            context,
                            NavigationRoutes.push(
                                builder: (context) => muteMember()));
                        await _refreshMutedMembers(keepExistingOnEmpty: true);
                      }
                    },
                  ),
                if (!isAllMuted && isAllowMuteMember)
                  ..._mutedMembers
                      .map((e) => Container(
                            padding: EdgeInsets.zero,
                            child: GestureDetector(
                              onSecondaryTapDown: (details) {
                                TUIKitWidePopup.showPopupWindow(
                                    operationKey:
                                        TUIKitWideModalOperationKey.setUnmute,
                                    isDarkBackground: false,
                                    borderRadius: const BorderRadius.all(
                                        Radius.circular(4)),
                                    context: context,
                                    offset: Offset(
                                        min(
                                            details.globalPosition.dx,
                                            MediaQuery.of(context).size.width -
                                                80),
                                        details.globalPosition.dy),
                                    child: (onClose) => TUIKitColumnMenu(data: [
                                          ColumnMenuItem(
                                              label: TIM_t("解除禁言"),
                                              icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                  size: 16),
                                              onClick: () async {
                                                if (await _unmuteMember(e)) {
                                                  onClose();
                                                }
                                              }),
                                        ]));
                              },
                              child: _buildListItem(
                                context,
                                e,
                                removeText: TIM_t("解除禁言"),
                                onRemove: () async {
                                  await _unmuteMember(e);
                                },
                              ),
                            ),
                          ))
                      .toList()
              ],
            );
          }

          return TUIKitScreenUtils.getDeviceWidget(
              context: context,
              desktopWidget: managePage(),
              defaultWidget: Scaffold(
                backgroundColor: _groupManagePageBackground(theme),
                appBar: AppBar(
                  title: Text(
                    widget.appBarTitle ?? tr.k_038lh6u,
                    style: TextStyle(
                      color: theme.chatHeaderTitleTextColor ??
                          theme.appbarTextColor,
                      fontSize: 17,
                    ),
                  ),
                  backgroundColor:
                      theme.chatHeaderBgColor ?? theme.appbarBgColor,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  shadowColor: theme.weakDividerColor,
                  iconTheme: IconThemeData(
                    color: theme.primaryColor ?? const Color(0xFF1E90FF),
                  ),
                  leading: TIMUIKitBackButton(
                    color: theme.primaryColor ?? const Color(0xFF1E90FF),
                  ),
                ),
                body: SingleChildScrollView(
                  child: managePage(),
                ),
              ));
        });
  }
}

_getShowName(V2TimGroupMemberFullInfo? item) {
  final friendRemark = item?.friendRemark ?? "";
  final nameCard = item?.nameCard ?? "";
  final nickName = item?.nickName ?? "";
  final userID = item?.userID ?? "";
  return friendRemark.isNotEmpty
      ? friendRemark
      : nameCard.isNotEmpty
          ? nameCard
          : nickName.isNotEmpty
              ? nickName
              : userID;
}

Widget _groupManageSectionHeader(TUITheme theme, String title) => Container(
      alignment: Alignment.centerLeft,
      color: theme.weakBackgroundColor ?? theme.wideBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(title,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w500,
              color: theme.weakTextColor)),
    );

Widget _buildListItem(
  BuildContext context,
  V2TimGroupMemberFullInfo memberInfo, {
  VoidCallback? onRemove,
  String? removeText,
}) {
  final theme = Provider.of<TUIThemeViewModel>(context).theme;
  final isDesktopScreen =
      TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
  final removeColor = theme.cautionColor ?? CommonColor.cautionColor;

  return Container(
    color: _groupManageSurfaceColor(theme),
    child: Column(children: [
      ListTile(
        tileColor: _groupManageSurfaceColor(theme),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 0,
        ),
        minTileHeight:
            DirectoryListStyle.rowHeight(context, desktop: isDesktopScreen),
        horizontalTitleGap: 12,
        leading: SizedBox(
          width: DirectoryListStyle.avatarSize(isDesktopScreen),
          height: DirectoryListStyle.avatarSize(isDesktopScreen),
          child: Avatar(
            faceUrl: memberInfo.faceUrl ?? "",
            showName: _getShowName(memberInfo),
            type: 1,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        title: Text(
          _getShowName(memberInfo),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w500,
            color: theme.darkTextColor,
          ),
        ),
        trailing: onRemove == null
            ? null
            : TextButton(
                onPressed: onRemove,
                style: TextButton.styleFrom(
                  foregroundColor: removeColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  removeText ?? TIM_t("删除"),
                  style: TextStyle(fontSize: isDesktopScreen ? 13 : 14),
                ),
              ),
        onTap: () {},
      ),
      Divider(
          thickness: .6,
          indent: 28 + DirectoryListStyle.avatarSize(isDesktopScreen),
          endIndent: onRemove == null ? 0 : 16,
          color: DirectoryListStyle.dividerColor(context),
          height: 0)
    ]),
  );
}

/// 选择管理员
class GroupProfileSetManagerPage extends StatefulWidget {
  final TUIGroupProfileModel model;
  final MemberPresenceLabelBuilder? presenceLabelBuilder;
  final MemberPresenceLoadingChecker? presenceLoadingChecker;
  final MemberPresenceOnlineResolver? presenceOnlineResolver;
  final Listenable? presenceListenable;
  final void Function(List<String> userIds)? onMemberPresenceRequested;

  const GroupProfileSetManagerPage({
    Key? key,
    required this.model,
    this.presenceLabelBuilder,
    this.presenceLoadingChecker,
    this.presenceOnlineResolver,
    this.presenceListenable,
    this.onMemberPresenceRequested,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _GroupProfileSetManagerPageState();
}

class _GroupProfileSetManagerPageState
    extends TIMUIKitState<GroupProfileSetManagerPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_loadMemberData());
  }

  Future<void> _loadMemberData() async {
    await widget.model.loadManagementMembers();
  }

  final TUIChatGlobalModel _chatGlobalModel =
      serviceLocator<TUIChatGlobalModel>();
  final CoreServicesImpl _coreServices = serviceLocator<CoreServicesImpl>();

  List<V2TimGroupMemberFullInfo?> _getAdminMemberList(
      List<V2TimGroupMemberFullInfo?> memberList) {
    return memberList
        .where((member) =>
            member?.role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN)
        .toList();
  }

  List<V2TimGroupMemberFullInfo?> _getOwnerList(
      List<V2TimGroupMemberFullInfo?> memberList) {
    return memberList
        .where((member) =>
            member?.role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER)
        .toList();
  }

  void _appendAdminNotice({
    required V2TimGroupMemberFullInfo memberFullInfo,
    required bool isGrant,
  }) {
    _chatGlobalModel.addGroupSystemNotice(
      GroupSystemNoticeItem(
        id: "${isGrant ? "grant" : "revoke"}|${widget.model.groupID}|${_coreServices.loginInfo.userID}|${memberFullInfo.userID}|${DateTime.now().millisecondsSinceEpoch}",
        groupID: widget.model.groupID,
        groupName: widget.model.groupInfo?.groupName ?? widget.model.groupID,
        groupFaceUrl: widget.model.groupInfo?.faceUrl ?? "",
        type: isGrant
            ? GroupSystemNoticeType.grantAdministrator
            : GroupSystemNoticeType.revokeAdministrator,
        operatorUserID: _coreServices.loginInfo.userID,
        operatorName: _coreServices.loginInfo.loginUser?.nickName ??
            _coreServices.loginInfo.userID,
        targetUserID: memberFullInfo.userID,
        targetName: memberFullInfo.nickName ??
            memberFullInfo.nameCard ??
            memberFullInfo.userID,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<bool> _grantAdministrators(
    List<V2TimGroupMemberFullInfo?> selectedMember,
  ) async {
    if (selectedMember.isEmpty) {
      GroupMemberFeedbackBridge.show(TIM_t('请选择成员'));
      return false;
    }
    final currentAdminCount =
        _getAdminMemberList(widget.model.managementMemberList).length;
    final slotsLeft = GroupGovernanceLimits.maxAdminCount - currentAdminCount;
    if (slotsLeft <= 0) {
      GroupMemberFeedbackBridge.show(GroupAdminRoleMessage.adminLimitReached());
      return false;
    }
    if (selectedMember.length > slotsLeft) {
      GroupMemberFeedbackBridge.show(GroupAdminRoleMessage.adminLimitReached());
      return false;
    }
    final userIDs = selectedMember
        .map((member) => member?.userID?.trim() ?? '')
        .where((userID) => userID.isNotEmpty)
        .toList(growable: false);
    if (userIDs.isEmpty) {
      GroupMemberFeedbackBridge.show(TIM_t('请选择成员'));
      return false;
    }
    final res = await widget.model.setMembersToAdmin(userIDs);
    if (res.code == 0) {
      for (final member in selectedMember) {
        if (member == null || (member.userID?.trim().isEmpty ?? true)) {
          continue;
        }
        _appendAdminNotice(memberFullInfo: member, isGrant: true);
      }
      await widget.model.reloadGroupMembers(widget.model.groupID);
      GroupMemberFeedbackBridge.show(TIM_t('设置管理员成功'));
      return true;
    }
    GroupMemberFeedbackBridge.show(
      res.desc?.trim().isNotEmpty == true
          ? GroupAdminRoleMessage.normalizeFeedback(res.desc!.trim())
          : TIM_t('设置管理员失败'),
    );
    return false;
  }

  List<V2TimGroupMemberFullInfo?> _memberCandidatesForAdmin(
    List<V2TimGroupMemberFullInfo?> memberList,
  ) {
    final managementIds = widget.model.managementMemberList
        .whereType<V2TimGroupMemberFullInfo>()
        .map((member) => member.userID.trim())
        .toSet();
    return memberList.where((element) {
      if (element == null || element.userID.trim().isEmpty) {
        return false;
      }
      return !managementIds.contains(element.userID.trim());
    }).toList();
  }

  _removeAdmin(
      BuildContext context, V2TimGroupMemberFullInfo memberFullInfo) async {
    final displayName = _getShowName(memberFullInfo);
    final confirmed = await _confirmRemoveAdmin(context, displayName);
    if (!confirmed) {
      return;
    }
    final res = await widget.model.setMemberToNormal(memberFullInfo.userID);
    if (res.code == 0) {
      _appendAdminNotice(memberFullInfo: memberFullInfo, isGrant: false);
      onTIMCallback(TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t("成功取消管理员身份"),
          infoCode: 6661003));
      return;
    }
    GroupMemberFeedbackBridge.show(
      res.desc?.trim().isNotEmpty == true ? res.desc!.trim() : TIM_t('设置管理员失败'),
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;
    if (widget.model.groupInfo?.groupType == GroupType.Work) {
      return const SizedBox.shrink();
    }

    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: widget.model)],
      builder: (context, w) {
        final model = Provider.of<TUIGroupProfileModel>(context);
        final memberList = model.groupMemberList;
        final adminList = _getAdminMemberList(model.managementMemberList);
        final ownerList = _getOwnerList(model.managementMemberList);
        final String option2 = adminList.length.toString();
        final String adminLimit =
            GroupGovernanceLimits.maxAdminCount.toString();
        final remainingAdminSlots =
            GroupGovernanceLimits.maxAdminCount - adminList.length;
        final isDesktopScreen =
            TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;

        Widget adminPage() {
          if (model.isManagementMemberListLoading) {
            return const Center(child: CupertinoActivityIndicator());
          }
          Widget retryMessage() => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(TIM_t('管理员列表加载失败')),
                  TextButton(
                    onPressed: model.isManagementMemberListLoading
                        ? null
                        : () => model.loadManagementMembers(),
                    child: Text(TIM_t('重试')),
                  ),
                ]),
              );
          if (!model.hasLoadedManagementMembers ||
              model.hasManagementMemberListError) {
            return Center(
              child: model.hasManagementMemberListError
                  ? retryMessage()
                  : const CupertinoActivityIndicator(),
            );
          }
          if (!GroupRolePolicy.isManagerRole(model.backendSelfRole)) {
            return Center(child: Text(TIM_t('只有群主或管理员可以管理群')));
          }
          return SingleChildScrollView(
              child: Column(
            children: [
              if (model.hasManagementMemberListError) retryMessage(),
              _groupManageSectionHeader(theme, TIM_t("群主")),
              ...ownerList
                  .map(
                    (e) => Container(
                      padding: EdgeInsets.zero,
                      child: _buildListItem(context, e!),
                    ),
                  )
                  .toList(),
              _groupManageSectionHeader(
                  theme,
                  TIM_t_para("管理员 ({{option2}}/{{option1}})",
                          "管理员 ($option2/$adminLimit)")(
                      option2: option2, option1: adminLimit)),
              InkWell(
                child: GroupSettingsTile(
                    theme: theme,
                    title: TIM_t("添加管理员"),
                    leading: Icon(Icons.add_circle_outline,
                        color: theme.primaryColor, size: 20)),
                onTap: () async {
                  if (remainingAdminSlots <= 0) {
                    GroupMemberFeedbackBridge.show(
                      GroupAdminRoleMessage.adminLimitReached(),
                    );
                    return;
                  }
                  final addAdminKey = GlobalKey<_GroupProfileAddAdminState>();
                  if (isDesktopScreen) {
                    final popupSize = WidePopupLayout.large(context);
                    TUIKitWidePopup.showPopupWindow(
                        operationKey: TUIKitWideModalOperationKey.setAdmins,
                        context: context,
                        title: TIM_t("设置管理员"),
                        width: popupSize.width,
                        height: popupSize.height,
                        onCancel: () {},
                        onConfirm: () {
                          addAdminKey.currentState?.onSubmit();
                        },
                        confirmText: TIM_t("完成"),
                        child: (onClose) => GroupProfileAddAdmin(
                              key: addAdminKey,
                              groupID: widget.model.groupID,
                              candidateFilter: _memberCandidatesForAdmin,
                              memberList: _memberCandidatesForAdmin(memberList),
                              memberListProvider: () =>
                                  _memberCandidatesForAdmin(
                                      widget.model.groupMemberList),
                              memberListListenable: widget.model,
                              loadMembersOnEntry:
                                  widget.model.loadMemberPageOnEntry,
                              maxSelectNum: remainingAdminSlots,
                              appbarTitle: TIM_t("设置管理员"),
                              presenceLabelBuilder: widget.presenceLabelBuilder,
                              presenceLoadingChecker:
                                  widget.presenceLoadingChecker,
                              presenceOnlineResolver:
                                  widget.presenceOnlineResolver,
                              presenceListenable: widget.presenceListenable,
                              onMemberPresenceRequested:
                                  widget.onMemberPresenceRequested,
                              onReachBottom: () =>
                                  widget.model.loadMoreGroupMembers(),
                              selectCompletedHandler:
                                  (context, selectedMember) async {
                                return _grantAdministrators(selectedMember);
                              },
                            ));
                  } else {
                    await Navigator.push(
                        context,
                        NavigationRoutes.push(
                            builder: (context) => GroupProfileAddAdmin(
                                  key: addAdminKey,
                                  groupID: widget.model.groupID,
                                  candidateFilter: _memberCandidatesForAdmin,
                                  memberList:
                                      _memberCandidatesForAdmin(memberList),
                                  memberListProvider: () =>
                                      _memberCandidatesForAdmin(
                                          widget.model.groupMemberList),
                                  memberListListenable: widget.model,
                                  loadMembersOnEntry:
                                      widget.model.loadMemberPageOnEntry,
                                  maxSelectNum: remainingAdminSlots,
                                  appbarTitle: TIM_t("设置管理员"),
                                  presenceLabelBuilder:
                                      widget.presenceLabelBuilder,
                                  presenceLoadingChecker:
                                      widget.presenceLoadingChecker,
                                  presenceOnlineResolver:
                                      widget.presenceOnlineResolver,
                                  presenceListenable: widget.presenceListenable,
                                  onMemberPresenceRequested:
                                      widget.onMemberPresenceRequested,
                                  onReachBottom: () =>
                                      widget.model.loadMoreGroupMembers(),
                                  selectCompletedHandler:
                                      (context, selectedMember) async {
                                    return _grantAdministrators(selectedMember);
                                  },
                                )));
                  }
                },
              ),
              ...adminList
                  .map((e) => GestureDetector(
                        onSecondaryTapDown: (details) {
                          TUIKitWidePopup.showPopupWindow(
                              operationKey:
                                  TUIKitWideModalOperationKey.deleteAdmin,
                              isDarkBackground: false,
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(4)),
                              context: context,
                              offset: Offset(
                                  min(details.globalPosition.dx,
                                      MediaQuery.of(context).size.width - 80),
                                  details.globalPosition.dy),
                              child: (onClose) => TUIKitColumnMenu(data: [
                                    ColumnMenuItem(
                                        label: TIM_t("删除"),
                                        icon: const Icon(
                                            Icons.remove_circle_outline,
                                            size: 16),
                                        onClick: () {
                                          _removeAdmin(context, e);
                                          onClose();
                                        }),
                                  ]));
                        },
                        child: Container(
                          padding: EdgeInsets.zero,
                          child: _buildListItem(
                            context,
                            e!,
                            onRemove: () => _removeAdmin(context, e),
                          ),
                        ),
                      ))
                  .toList(),
            ],
          ));
        }

        return TUIKitScreenUtils.getDeviceWidget(
            context: context,
            desktopWidget: adminPage(),
            defaultWidget: Scaffold(
              backgroundColor: _groupManagePageBackground(theme),
              appBar: AppBar(
                title: Text(
                  TIM_t("设置管理员"),
                  style: TextStyle(
                    color:
                        theme.chatHeaderTitleTextColor ?? theme.appbarTextColor,
                    fontSize: 17,
                  ),
                ),
                shadowColor: theme.weakDividerColor,
                backgroundColor: theme.chatHeaderBgColor ?? theme.appbarBgColor,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                iconTheme: IconThemeData(
                  color: theme.primaryColor ?? const Color(0xFF1E90FF),
                ),
                leading: TIMUIKitBackButton(
                  color: theme.primaryColor ?? const Color(0xFF1E90FF),
                ),
              ),
              body: adminPage(),
            ));
      },
    );
  }
}

/// 添加管理员
typedef GroupProfileMemberSelectHandler = Future<bool> Function(
  BuildContext context,
  List<V2TimGroupMemberFullInfo?> selectedMemberList,
);

typedef GroupProfileMemberListProvider = List<V2TimGroupMemberFullInfo?>
    Function();

typedef GroupProfileMemberCandidateFilter = List<V2TimGroupMemberFullInfo?>
    Function(List<V2TimGroupMemberFullInfo?> members);

class GroupProfileAddAdmin extends StatefulWidget {
  final List<V2TimGroupMemberFullInfo?> memberList;
  final String groupID;
  final String appbarTitle;
  final int? maxSelectNum;
  final GroupProfileMemberSelectHandler? selectCompletedHandler;
  final MemberPresenceLabelBuilder? presenceLabelBuilder;
  final MemberPresenceLoadingChecker? presenceLoadingChecker;
  final MemberPresenceOnlineResolver? presenceOnlineResolver;
  final Listenable? presenceListenable;
  final void Function(List<String> userIds)? onMemberPresenceRequested;
  final Future<void> Function()? onReachBottom;
  final GroupProfileMemberListProvider? memberListProvider;
  final Listenable? memberListListenable;
  final GroupProfileMemberCandidateFilter? candidateFilter;
  final Future<void> Function()? loadMembersOnEntry;

  const GroupProfileAddAdmin(
      {Key? key,
      required this.memberList,
      required this.groupID,
      this.selectCompletedHandler,
      required this.appbarTitle,
      this.maxSelectNum,
      this.presenceLabelBuilder,
      this.presenceLoadingChecker,
      this.presenceOnlineResolver,
      this.presenceListenable,
      this.onMemberPresenceRequested,
      this.onReachBottom,
      this.memberListProvider,
      this.memberListListenable,
      this.loadMembersOnEntry,
      this.candidateFilter})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _GroupProfileAddAdminState();
}

class _GroupProfileAddAdminState extends TIMUIKitState<GroupProfileAddAdmin> {
  List<V2TimGroupMemberFullInfo> selectedMemberList = [];
  String _searchKeyword = '';
  bool _submitting = false;
  late final GroupMemberCloudSearchController _cloudSearch;
  bool _entryLoading = false;
  bool _entryError = false;

  @override
  void initState() {
    super.initState();
    _cloudSearch = GroupMemberCloudSearchController(
      groupId: widget.groupID,
      onUpdate: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    _entryLoading = widget.loadMembersOnEntry != null;
    if (_entryLoading) unawaited(Future<void>.microtask(_loadEntry));
  }

  Future<void> _loadEntry() async {
    if (!mounted) return;
    setState(() {
      _entryLoading = true;
      _entryError = false;
    });
    try {
      await widget.loadMembersOnEntry?.call();
      final source = widget.memberListListenable;
      if (source is TUIGroupProfileModel &&
          (source.hasMemberEntryError || source.hasManagementMemberListError)) {
        _entryError = true;
      }
    } catch (_) {
      _entryError = true;
    } finally {
      if (mounted) setState(() => _entryLoading = false);
    }
  }

  @override
  void dispose() {
    _cloudSearch.dispose();
    super.dispose();
  }

  Future<bool> onSubmit() async {
    if (_submitting || _entryLoading || _entryError) {
      return false;
    }
    final members = selectedMemberList
        .map((member) => member as V2TimGroupMemberFullInfo?)
        .toList(growable: false);
    if (members.isEmpty) {
      GroupMemberFeedbackBridge.show(TIM_t('请选择成员'));
      return false;
    }
    final handler = widget.selectCompletedHandler;
    if (handler != null) {
      setState(() {
        _submitting = true;
      });
      try {
        return await handler(
          context,
          members,
        );
      } catch (_) {
        GroupMemberFeedbackBridge.show(TIM_t('操作失败，请重试'));
        return false;
      } finally {
        if (mounted) {
          setState(() {
            _submitting = false;
          });
        }
      }
    }
    return true;
  }

  void _handleSearchGroupMembers(String searchText) {
    final keyword = searchText.trim().toLowerCase();
    if (keyword != _searchKeyword) {
      setState(() => _searchKeyword = keyword);
    }
    _cloudSearch.onKeywordChanged(searchText);
  }

  List<V2TimGroupMemberFullInfo?> _pickerMembers(
    List<V2TimGroupMemberFullInfo?> source,
  ) {
    if (_searchKeyword.isEmpty) {
      return source;
    }
    if (_cloudSearch.usedCloud || _cloudSearch.members.isNotEmpty) {
      final cloud = _cloudSearch.members
          .map<V2TimGroupMemberFullInfo?>((member) => member)
          .toList();
      return widget.candidateFilter?.call(cloud) ?? cloud;
    }
    return filterGroupMembersByKeyword(source, _searchKeyword);
  }

  Widget _memberPickerList() {
    if (_entryLoading) return const Center(child: CircularProgressIndicator());
    if (_entryError)
      return Center(
          child: TextButton(
        onPressed: _loadEntry,
        child: Text(TIM_t('群成员加载失败，点击重试')),
      ));
    Widget buildPicker() {
      final source = widget.memberListProvider?.call() ?? widget.memberList;
      final members = _pickerMembers(source);
      return Stack(
        children: [
          AbsorbPointer(
            absorbing: _submitting,
            child: GroupProfileMemberList(
              customTopArea: GroupMemberSearchTextField(
                onTextChange: _handleSearchGroupMembers,
              ),
              memberList: members,
              canSelectMember: true,
              canSlideDelete: false,
              maxSelectNum: widget.maxSelectNum,
              presenceLabelBuilder: widget.presenceLabelBuilder,
              presenceLoadingChecker: widget.presenceLoadingChecker,
              presenceOnlineResolver: widget.presenceOnlineResolver,
              presenceListenable: widget.presenceListenable,
              onMemberListLoaded: widget.onMemberPresenceRequested,
              onSelectedMemberChange: (selectedMember) {
                selectedMemberList = selectedMember;
              },
              touchBottomCallBack: () async {
                if (_searchKeyword.isEmpty) {
                  final onReachBottom = widget.onReachBottom;
                  if (onReachBottom != null) {
                    await onReachBottom();
                  }
                  return;
                }
                if (_cloudSearch.usedCloud) {
                  await _cloudSearch.loadMore();
                }
              },
            ),
          ),
          if (_submitting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.04),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
        ],
      );
    }

    final listenable = widget.memberListListenable;
    if (listenable == null) return buildPicker();
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) => buildPicker(),
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;

    return TUIKitScreenUtils.getDeviceWidget(
        context: context,
        desktopWidget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _memberPickerList(),
        ),
        defaultWidget: Scaffold(
            backgroundColor: _groupManagePageBackground(theme),
            appBar: AppBar(
              title: Text(
                widget.appbarTitle,
                style: TextStyle(
                  color:
                      theme.chatHeaderTitleTextColor ?? theme.appbarTextColor,
                  fontSize: 17,
                ),
              ),
              shadowColor: theme.weakDividerColor,
              backgroundColor: theme.chatHeaderBgColor ?? theme.appbarBgColor,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              iconTheme: IconThemeData(
                color: theme.primaryColor ?? const Color(0xFF1E90FF),
              ),
              leadingWidth: 80,
              leading: TextButton(
                onPressed: _submitting
                    ? null
                    : () {
                        Navigator.of(context).pop();
                      },
                child: Text(
                  TIM_t("取消"),
                  style: TextStyle(
                    color: theme.primaryColor ?? theme.appbarTextColor,
                    fontSize: 14,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () async {
                          final shouldPop = await onSubmit();
                          if (shouldPop && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  child: _submitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.primaryColor ?? theme.appbarTextColor,
                          ),
                        )
                      : Text(
                          TIM_t("完成"),
                          style: TextStyle(
                            color: theme.primaryColor ?? theme.appbarTextColor,
                            fontSize: 14,
                          ),
                        ),
                )
              ],
            ),
            body: _memberPickerList()));
  }
}

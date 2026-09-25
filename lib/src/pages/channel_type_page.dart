import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_join_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_join_option.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_share_service.dart';
import 'package:tencent_cloud_chat_demo/src/platform/clipboard_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/share_app_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_app_payload.dart';

class ChannelTypePage extends StatefulWidget {
  const ChannelTypePage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<ChannelTypePage> createState() => _ChannelTypePageState();
}

class _ChannelTypePageState extends State<ChannelTypePage> {
  GroupJoinOptions? _options;
  bool _isPublic = true;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _invitationLink;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadLink());
  }

  Future<void> _load() async {
    try {
      final options =
          await GroupJoinApi.instance.fetchJoinOptions(widget.groupId);
      if (!mounted) return;
      setState(() {
        _options = options;
        _isPublic = options.allowJoinByAlias;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = AppI18n.of(context).t(
          zhHans: '频道类型加载失败，请重试',
          zhHant: '頻道類型載入失敗，請重試',
          en: 'Could not load channel type. Try again.',
          ja: 'チャンネル設定を読み込めませんでした。再試行してください。',
          ko: '채널 설정을 불러오지 못했습니다. 다시 시도하세요.',
        );
      });
    }
  }

  Future<void> _loadLink() async {
    final baseUrl = await ShareAppService.instance.resolveQrLandingUrl();
    if (!mounted) return;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return;
    }
    setState(() {
      _invitationLink = QrAppPayload.encode(
        baseUrl: baseUrl,
        type: QrAppPayloadType.group,
        id: widget.groupId,
        name: widget.groupName,
      );
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    final current = _options;
    if (current == null || _saving) return;
    setState(() => _saving = true);
    try {
      await GroupJoinApi.instance.updateJoinOptions(
        widget.groupId,
        current.copyWith(
          allowJoinByAlias: _isPublic,
          allowJoinByQrCode: true,
          applyJoinOption: GroupJoinOption.freeAccess,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message(AppI18n.of(context).t(
        zhHans: '保存失败，请重试',
        zhHant: '儲存失敗，請重試',
        en: 'Could not save. Try again.',
        ja: '保存できませんでした。再試行してください。',
        ko: '저장하지 못했습니다. 다시 시도하세요.',
      ));
    }
  }

  Future<void> _copyLink() async {
    final link = _invitationLink;
    if (link == null) return;
    await ClipboardGuard.copy(link);
    if (!mounted) return;
    _message(AppI18n.of(context).t(
      zhHans: '链接已复制',
      zhHant: '連結已複製',
      en: 'Link copied',
      ja: 'リンクをコピーしました',
      ko: '링크를 복사했습니다',
    ));
  }

  Future<void> _shareLink() async {
    final link = _invitationLink;
    if (link == null) return;
    final result = await WalletShareService().shareSystemText(link);
    if (!mounted) return;
    if (result != WalletSystemShareResult.success) {
      await _copyLink();
    }
  }

  Widget _typeRow(
      {required String title,
      required bool selected,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Row(children: [
          Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 24,
              color:
                  selected ? const Color(0xFF2387EE) : const Color(0xFFC7CDD6)),
          const SizedBox(width: 14),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    const background = Color(0xFFF4F7FD);
    const secondary = Color(0xFF818A99);
    final publicLabel =
        i18n.t(zhHans: '公开', zhHant: '公開', en: 'Public', ja: '公開', ko: '공개');
    final privateLabel =
        i18n.t(zhHans: '私密', zhHant: '私密', en: 'Private', ja: '非公開', ko: '비공개');
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(i18n.t(
            zhHans: '频道类型',
            zhHant: '頻道類型',
            en: 'Channel type',
            ja: 'チャンネルの種類',
            ko: '채널 유형')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: const Color(0xFF2387EE),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _loading || _options == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(i18n.t(
                    zhHans: '保存',
                    zhHant: '儲存',
                    en: 'Save',
                    ja: '保存',
                    ko: '저장')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: TextButton(onPressed: _load, child: Text(_loadError!)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
                  children: [
                    Text(
                        i18n.t(
                            zhHans: '链接',
                            zhHant: '連結',
                            en: 'Link',
                            ja: 'リンク',
                            ko: '링크'),
                        style: const TextStyle(color: secondary, fontSize: 14)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        _typeRow(
                            title: publicLabel,
                            selected: _isPublic,
                            onTap: () => setState(() => _isPublic = true)),
                        const Divider(height: 1, color: Color(0xFFECEFF4)),
                        _typeRow(
                            title: privateLabel,
                            selected: !_isPublic,
                            onTap: () => setState(() => _isPublic = false)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text(
                        _isPublic
                            ? i18n.t(
                                zhHans: '公共频道可以在搜索中找到，任何人都可以加入',
                                zhHant: '公共頻道可以在搜尋中找到，任何人都可以加入',
                                en:
                                    'Anyone can find this channel by its alias and subscribe.',
                                ja: '誰でもチャンネル名で検索して登録できます。',
                                ko: '누구나 채널 별칭으로 검색하고 구독할 수 있습니다.')
                            : i18n.t(
                                zhHans: '私密频道不能通过频道别名加入，可以通过邀请链接加入',
                                zhHant: '私密頻道不能透過頻道別名加入，可以透過邀請連結加入',
                                en: 'Private channels can be subscribed to through an invitation link.',
                                ja: '非公開チャンネルは招待リンクから登録できます。',
                                ko: '비공개 채널은 초대 링크로 구독할 수 있습니다。'),
                        style: const TextStyle(color: secondary, fontSize: 14)),
                    const SizedBox(height: 28),
                    Text(
                        i18n.t(
                            zhHans: '邀请链接',
                            zhHant: '邀請連結',
                            en: 'Invitation link',
                            ja: '招待リンク',
                            ko: '초대 링크'),
                        style: const TextStyle(color: secondary, fontSize: 14)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        Container(
                          height: 54,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF5F7FC),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    _invitationLink ??
                                        i18n.t(
                                            zhHans: '链接暂不可用',
                                            zhHant: '連結暫不可用',
                                            en: 'Link unavailable',
                                            ja: 'リンクを利用できません',
                                            ko: '링크를 사용할 수 없습니다'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16))),
                            IconButton(
                              onPressed:
                                  _invitationLink == null ? null : _copyLink,
                              icon: const Icon(Icons.copy_rounded),
                              color: const Color(0xFF2387EE),
                              tooltip: i18n.t(
                                  zhHans: '复制链接',
                                  zhHant: '複製連結',
                                  en: 'Copy link',
                                  ja: 'リンクをコピー',
                                  ko: '링크 복사'),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed:
                                _invitationLink == null ? null : _shareLink,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2387EE),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            child: Text(
                                i18n.t(
                                    zhHans: '分享链接',
                                    zhHant: '分享連結',
                                    en: 'Share link',
                                    ja: 'リンクを共有',
                                    ko: '링크 공유'),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text(
                        i18n.t(
                            zhHans: '任何人可以通过点击这个链接加入你的频道',
                            zhHant: '任何人可以透過點擊這個連結加入你的頻道',
                            en: 'Anyone with this link can join your channel.',
                            ja: 'リンクを受け取った人はチャンネルに登録できます。',
                            ko: '링크를 받은 사람은 이 채널을 구독할 수 있습니다.'),
                        style: const TextStyle(color: secondary, fontSize: 14)),
                  ],
                ),
    );
  }
}

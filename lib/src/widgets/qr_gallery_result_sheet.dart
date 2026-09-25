import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_app_payload.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_web_login_payload.dart';

/// Multiple decoded targets require an explicit choice before navigation.
class QrGalleryResultSheet extends StatelessWidget {
  const QrGalleryResultSheet({super.key, required this.values});
  final List<String> values;

  static Future<String?> show(BuildContext context, List<String> values) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => QrGalleryResultSheet(values: values),
      );

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final color = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.65),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(children: [
              Expanded(
                  child: Text(
                      i18n.t(
                        zhHans: '选择二维码',
                        zhHant: '選擇 QR 碼',
                        en: 'Choose a QR code',
                        ja: 'QRコードを選択',
                        ko: 'QR 코드 선택',
                      ),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Flexible(
              child: ListView.separated(
            shrinkWrap: true,
            itemCount: values.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
            itemBuilder: (_, index) {
              final raw = values[index];
              final app = QrAppPayload.tryParse(raw);
              final login = QrWebLoginPayload.tryParse(raw);
              final uri = Uri.tryParse(raw);
              final isLink = uri != null &&
                  (uri.scheme == 'https' || uri.scheme == 'http');
              final String type;
              final IconData icon;
              if (app != null) {
                final isUser = app.type == QrAppPayloadType.user;
                type = isUser
                    ? i18n.t(
                        zhHans: '联系人',
                        zhHant: '聯絡人',
                        en: 'Contact',
                        ja: '連絡先',
                        ko: '연락처')
                    : i18n.t(
                        zhHans: '群聊 / 频道',
                        zhHant: '群組 / 頻道',
                        en: 'Group / Channel',
                        ja: 'グループ / チャンネル',
                        ko: '그룹 / 채널');
                icon = isUser
                    ? Icons.person_outline_rounded
                    : Icons.groups_outlined;
              } else if (login != null) {
                type = i18n.t(
                    zhHans: '网页登录',
                    zhHant: '網頁登入',
                    en: 'Web login',
                    ja: 'ウェブログイン',
                    ko: '웹 로그인');
                icon = Icons.computer_rounded;
              } else {
                type = isLink
                    ? i18n.t(
                        zhHans: '网页链接',
                        zhHant: '網頁連結',
                        en: 'Web link',
                        ja: 'ウェブリンク',
                        ko: '웹 링크')
                    : i18n.t(
                        zhHans: '二维码内容',
                        zhHant: 'QR 碼內容',
                        en: 'QR content',
                        ja: 'QRコードの内容',
                        ko: 'QR 코드 내용');
                icon = isLink ? Icons.link_rounded : Icons.qr_code_rounded;
              }
              return ListTile(
                leading: Icon(icon, color: color),
                title: Text(
                    app != null && app.name.isNotEmpty ? app.name : type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    app != null
                        ? '$type · ${app.id}'
                        : login != null
                            ? '${index + 1} · $type'
                            : raw,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, raw),
              );
            },
          )),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/api/kefu_visitor_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/platform_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/moments/moments_video_player_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/settings_widgets.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/kefu_visitor_cable.dart';
import 'package:tencent_cloud_chat_demo/src/services/kefu_visitor_session.dart';
import 'package:tencent_cloud_chat_demo/src/services/system_media_picker.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/utils/dio_factory.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/gallery_save_to_photos.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_save_notice.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

const String _kCategoryFaq = 'faq';
const String _kCategoryAbout = 'about';
const String _kCategorySecurity = 'security';
const String _kCategoryCash = 'cash';
const String _kCategorySocial = 'social';
const String _kCategoryAuth = 'auth';
const String _kCategoryLife = 'life';
const String _kCategoryOther = 'other';

const List<String> _kCategoryIds = <String>[
  _kCategoryFaq,
  _kCategoryAbout,
  _kCategorySecurity,
  _kCategoryCash,
  _kCategorySocial,
  _kCategoryAuth,
  _kCategoryLife,
  _kCategoryOther,
];

const Map<String, List<String>> _kSubtopicIds = <String, List<String>>{
  _kCategoryFaq: <String>[
    'faq_official',
    'faq_notify',
    'faq_send',
    'faq_media',
    'faq_network',
  ],
  _kCategoryAbout: <String>[
    'about_what',
    'about_features',
    'about_moments',
    'about_call',
  ],
  _kCategorySecurity: <String>[
    'security_pin',
    'security_devices',
    'security_password',
    'security_phone',
  ],
  _kCategoryCash: <String>[
    'cash_deposit_time',
    'cash_withdraw_missing',
    'cash_redpacket',
    'cash_transfer',
  ],
  _kCategorySocial: <String>[
    'social_friend',
    'social_create',
    'social_join',
    'social_mute',
  ],
  _kCategoryAuth: <String>[
    'auth_register',
    'auth_forgot',
    'auth_code',
    'auth_disable',
  ],
  _kCategoryLife: <String>[
    'life_entry',
    'life_fail',
    'life_record',
    'life_balance',
  ],
  _kCategoryOther: <String>[
    'other_profile',
    'other_report',
    'other_feedback',
    'other_human',
  ],
};

const Color _kHeaderBlue = Color(0xFF2B7FE0);
const Color _kLightContentBg = Color(0xFFE8F1FB);

enum _CsSentKind { text, image, video, file, system }

class _CsSentItem {
  const _CsSentItem({
    required this.kind,
    required this.name,
    this.path = '',
    this.content = '',
    this.messageType = 0,
    this.echoId = '',
    this.serverId = '',
    this.remoteUrl = '',
    this.thumbUrl = '',
    this.localThumbPath = '',
    this.bytes,
    this.width = 0,
    this.height = 0,
  });

  final _CsSentKind kind;
  final String name;
  final String path;
  final String content;
  final int messageType;
  final String echoId;
  final String serverId;
  final String remoteUrl;
  final String thumbUrl;
  final String localThumbPath;
  final List<int>? bytes;
  final int width;
  final int height;
}

class CustomerServiceStaticPage extends StatefulWidget {
  const CustomerServiceStaticPage({super.key});

  @override
  State<CustomerServiceStaticPage> createState() =>
      _CustomerServiceStaticPageState();
}

class _CustomerServiceStaticPageState extends State<CustomerServiceStaticPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _conversationController = ScrollController();
  final List<_CsSentItem> _sentItems = <_CsSentItem>[];
  late final KefuVisitorCable _cable;
  KefuVisitorSession? _session;
  bool _agentTyping = false;
  String _selectedCategoryId = _kCategoryFaq;
  String? _openSubtopicId;
  bool _faqOpen = false;
  bool _historyReady = false;
  String _officialWebsite = '';

  @override
  void initState() {
    super.initState();
    _cable = KefuVisitorCable(
      onMessage: _onCableMessage,
      onTyping: (typing) {
        if (!mounted) {
          return;
        }
        setState(() {
          _agentTyping = typing;
        });
      },
    );
    unawaited(_bootstrap());
    unawaited(_loadOfficialWebsite());
  }

  @override
  void dispose() {
    _cable.dispose();
    _conversationController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  String _categoryLabel(AppI18n i18n, String id) {
    switch (id) {
      case _kCategoryFaq:
        return i18n.t(
          zhHans: '常见问题',
          zhHant: '常見問題',
          en: 'FAQ',
          ja: 'よくある質問',
          ko: '자주 묻는 질문',
        );
      case _kCategoryAbout:
        return i18n.t(
          zhHans: 'APP简介',
          zhHant: 'APP簡介',
          en: 'About App',
          ja: 'アプリ紹介',
          ko: '앱 소개',
        );
      case _kCategorySecurity:
        return i18n.t(
          zhHans: '安全中心',
          zhHant: '安全中心',
          en: 'Security',
          ja: 'セキュリティ',
          ko: '보안 센터',
        );
      case _kCategoryCash:
        return i18n.t(
          zhHans: '充值提现',
          zhHant: '儲值提現',
          en: 'Deposit & Withdraw',
          ja: '入出金',
          ko: '입출금',
        );
      case _kCategorySocial:
        return i18n.t(
          zhHans: '好友与群',
          zhHant: '好友與群',
          en: 'Friends & Groups',
          ja: '友達とグループ',
          ko: '친구와 그룹',
        );
      case _kCategoryAuth:
        return i18n.t(
          zhHans: '注册登录',
          zhHant: '註冊登入',
          en: 'Sign in',
          ja: '登録とログイン',
          ko: '가입 및 로그인',
        );
      case _kCategoryLife:
        return i18n.t(
          zhHans: '生活缴费',
          zhHant: '生活繳費',
          en: 'Utilities',
          ja: '公共料金',
          ko: '공과금',
        );
      case _kCategoryOther:
      default:
        return i18n.t(
          zhHans: '其他',
          zhHant: '其他',
          en: 'Other',
          ja: 'その他',
          ko: '기타',
        );
    }
  }

  String _subtopicLabel(AppI18n i18n, String id) {
    switch (id) {
      case 'faq_official':
        return i18n.t(
          zhHans: '官方网站',
          zhHant: '官方網站',
          en: 'Official website',
          ja: '公式サイト',
          ko: '공식 웹사이트',
        );
      case 'faq_notify':
        return i18n.t(
          zhHans: '收不到新消息通知',
          zhHant: '收不到新訊息通知',
          en: 'No new message alerts',
          ja: '新着通知が来ない',
          ko: '새 메시지 알림이 없음',
        );
      case 'faq_send':
        return i18n.t(
          zhHans: '消息发不出去',
          zhHant: '訊息發不出去',
          en: 'Cannot send messages',
          ja: 'メッセージが送れない',
          ko: '메시지를 보낼 수 없음',
        );
      case 'faq_media':
        return i18n.t(
          zhHans: '图片或视频发送失败',
          zhHant: '圖片或影片傳送失敗',
          en: 'Photo or video failed',
          ja: '画像・動画が送れない',
          ko: '사진/영상 전송 실패',
        );
      case 'faq_network':
        return i18n.t(
          zhHans: '提示网络异常',
          zhHant: '提示網路異常',
          en: 'Network error',
          ja: 'ネットワークエラー',
          ko: '네트워크 오류',
        );
      case 'about_what':
        return i18n.t(
          zhHans: '99chat 是什么',
          zhHant: '99chat 是什麼',
          en: 'What is 99chat',
          ja: '99chatとは',
          ko: '99chat이란',
        );
      case 'about_features':
        return i18n.t(
          zhHans: '主要功能有哪些',
          zhHant: '主要功能有哪些',
          en: 'Main features',
          ja: '主な機能',
          ko: '주요 기능',
        );
      case 'about_moments':
        return i18n.t(
          zhHans: '朋友圈怎么用',
          zhHant: '朋友圈怎麼用',
          en: 'Moments',
          ja: 'モーメント',
          ko: '모멘트',
        );
      case 'about_call':
        return i18n.t(
          zhHans: '语音视频通话',
          zhHant: '語音視訊通話',
          en: 'Voice & video calls',
          ja: '音声・ビデオ通話',
          ko: '음성/영상 통화',
        );
      case 'security_pin':
        return i18n.t(
          zhHans: '忘记支付密码',
          zhHant: '忘記支付密碼',
          en: 'Forgot payment PIN',
          ja: '決済パスワードを忘れた',
          ko: '결제 비밀번호를 잊음',
        );
      case 'security_devices':
        return i18n.t(
          zhHans: '发现陌生登录设备',
          zhHant: '發現陌生登入裝置',
          en: 'Unknown login device',
          ja: '身に覚えのない端末',
          ko: '모르는 로그인 기기',
        );
      case 'security_password':
        return i18n.t(
          zhHans: '修改登录密码',
          zhHant: '修改登入密碼',
          en: 'Change login password',
          ja: 'ログインパスワード変更',
          ko: '로그인 비밀번호 변경',
        );
      case 'security_phone':
        return i18n.t(
          zhHans: '换绑手机号',
          zhHant: '換綁手機號',
          en: 'Change phone number',
          ja: '電話番号の変更',
          ko: '휴대폰 번호 변경',
        );
      case 'cash_deposit_time':
        return i18n.t(
          zhHans: '充值多久到账',
          zhHant: '儲值多久到帳',
          en: 'When does a deposit arrive',
          ja: '入金はいつ反映される',
          ko: '입금은 언제 들어오나요',
        );
      case 'cash_withdraw_missing':
        return i18n.t(
          zhHans: '提现未到账',
          zhHant: '提現未到帳',
          en: 'Withdrawal not received',
          ja: '出金が届かない',
          ko: '출금이 안 들어옴',
        );
      case 'cash_redpacket':
        return i18n.t(
          zhHans: '红包发不出或领不了',
          zhHant: '紅包發不出或領不了',
          en: 'Red packet failed',
          ja: 'お年玉が送れない・受け取れない',
          ko: '홍바오를 보내거나 받지 못함',
        );
      case 'cash_transfer':
        return i18n.t(
          zhHans: '转账失败',
          zhHant: '轉帳失敗',
          en: 'Transfer failed',
          ja: '送金に失敗した',
          ko: '송금 실패',
        );
      case 'social_friend':
        return i18n.t(
          zhHans: '加好友失败',
          zhHant: '加好友失敗',
          en: 'Cannot add friend',
          ja: '友だち追加できない',
          ko: '친구 추가 실패',
        );
      case 'social_create':
        return i18n.t(
          zhHans: '如何创建群聊',
          zhHant: '如何建立群聊',
          en: 'Create a group',
          ja: 'グループの作り方',
          ko: '그룹 만드는 법',
        );
      case 'social_join':
        return i18n.t(
          zhHans: '进群失败或被踢',
          zhHant: '進群失敗或被踢',
          en: 'Cannot join / kicked',
          ja: '参加できない・退出させられた',
          ko: '그룹 입장 실패/강퇴',
        );
      case 'social_mute':
        return i18n.t(
          zhHans: '群消息太多太吵',
          zhHant: '群訊息太多太吵',
          en: 'Too many group alerts',
          ja: 'グループ通知が多すぎる',
          ko: '그룹 알림이 너무 많음',
        );
      case 'auth_register':
        return i18n.t(
          zhHans: '如何注册',
          zhHant: '如何註冊',
          en: 'How to sign up',
          ja: '登録方法',
          ko: '가입 방법',
        );
      case 'auth_forgot':
        return i18n.t(
          zhHans: '忘记登录密码',
          zhHant: '忘記登入密碼',
          en: 'Forgot login password',
          ja: 'ログインパスワードを忘れた',
          ko: '로그인 비밀번호를 잊음',
        );
      case 'auth_code':
        return i18n.t(
          zhHans: '收不到验证码',
          zhHant: '收不到驗證碼',
          en: 'No SMS code',
          ja: '認証コードが届かない',
          ko: '인증문자가 안 옴',
        );
      case 'auth_disable':
        return i18n.t(
          zhHans: '账号被限制或无法登录',
          zhHant: '帳號被限制或無法登入',
          en: 'Account restricted',
          ja: 'アカウント制限・ログイン不可',
          ko: '계정 제한/로그인 불가',
        );
      case 'life_entry':
        return i18n.t(
          zhHans: '生活缴费入口在哪',
          zhHant: '生活繳費入口在哪',
          en: 'Where is Utilities',
          ja: '公共料金はどこ',
          ko: '공과금 메뉴 위치',
        );
      case 'life_fail':
        return i18n.t(
          zhHans: '缴费失败',
          zhHant: '繳費失敗',
          en: 'Payment failed',
          ja: '支払いに失敗した',
          ko: '납부 실패',
        );
      case 'life_record':
        return i18n.t(
          zhHans: '缴费记录在哪看',
          zhHant: '繳費記錄在哪看',
          en: 'Payment history',
          ja: '支払い履歴',
          ko: '납부 내역',
        );
      case 'life_balance':
        return i18n.t(
          zhHans: '余额不足怎么缴',
          zhHant: '餘額不足怎麼繳',
          en: 'Not enough balance',
          ja: '残高不足',
          ko: '잔액 부족',
        );
      case 'other_profile':
        return i18n.t(
          zhHans: '修改昵称和头像',
          zhHant: '修改暱稱和頭像',
          en: 'Change name and avatar',
          ja: 'ニックネームとアイコン',
          ko: '닉네임과 프로필 사진',
        );
      case 'other_report':
        return i18n.t(
          zhHans: '投诉与举报',
          zhHant: '投訴與檢舉',
          en: 'Report abuse',
          ja: '通報',
          ko: '신고',
        );
      case 'other_feedback':
        return i18n.t(
          zhHans: '意见与建议',
          zhHant: '意見與建議',
          en: 'Feedback',
          ja: 'ご意見',
          ko: '의견 제안',
        );
      case 'other_human':
        return i18n.t(
          zhHans: '联系人工客服',
          zhHant: '聯繫人工客服',
          en: 'Talk to an agent',
          ja: '有人サポート',
          ko: '상담원 연결',
        );
      default:
        return id;
    }
  }

  String _subtopicAnswer(AppI18n i18n, String id) {
    switch (id) {
      case 'faq_official':
        if (_officialWebsite.isEmpty) {
          return i18n.t(
            zhHans: '官方网站可在「我的」-「关于我们」中查看。当前尚未获取到链接，请稍后再试，或在下方发给人工客服。请勿点击陌生人发送的不明网址。',
            zhHant: '官方網站可在「我的」-「關於我們」中查看。目前尚未取得連結，請稍後再試，或在下方發給人工客服。請勿點擊陌生人傳送的不明網址。',
            en: 'The official website is also in Me > About Us. The link is not available yet — try again later or send a message below. Do not open unknown URLs from strangers.',
            ja: '公式サイトは「マイページ > このアプリについて」でも確認できます。まだ取得できない場合は時間をおくか、下の有人サポートへ。見知らぬ人のURLは開かないでください。',
            ko: '공식 사이트는 「내 정보 > 정보」에서도 볼 수 있습니다. 아직 링크를 못 받으면 잠시 후 다시 시도하거나 아래 상담원에게 보내 주세요. 모르는 사람 링크는 열지 마세요.',
          );
        }
        return i18n.t(
          zhHans: '以下为 99chat 官方网站，请只通过该链接访问或下载，不要点击陌生人发送的网址。点链接即可打开。也可在「我的」-「关于我们」中查看。',
          zhHant: '以下為 99chat 官方網站，請只透過該連結訪問或下載，不要點擊陌生人傳送的網址。點連結即可打開。也可在「我的」-「關於我們」中查看。',
          en: 'This is the official 99chat website. Use only this link to visit or download. Do not open URLs from strangers. Tap the link to open it. You can also find it in Me > About Us.',
          ja: '以下が99chat公式サイトです。訪問・ダウンロードはこのリンクのみ使い、見知らぬ人のURLは開かないでください。タップで開けます。「このアプリについて」でも確認できます。',
          ko: '아래가 99chat 공식 사이트입니다. 방문·다운로드는 이 링크만 쓰고, 모르는 사람 주소는 열지 마세요. 눌러서 열 수 있습니다. 「내 정보 > 정보」에서도 볼 수 있습니다.',
        );
      case 'faq_notify':
        return i18n.t(
          zhHans: '请先在系统设置里允许 99chat 通知，再打开「我的」-「设置」确认消息通知已开启。安卓请把 99chat 加入电池优化白名单，并允许后台运行。锁屏后仍无通知，可重启手机后再试。',
          zhHant: '請先在系統設定裡允許 99chat 通知，再開啟「我的」-「設定」確認訊息通知已開啟。安卓請把 99chat 加入電池最佳化白名單，並允許背景執行。鎖屏後仍無通知，可重啟手機後再試。',
          en: 'Allow 99chat notifications in system settings, then confirm alerts in Me > Settings. On Android, exclude 99chat from battery optimization and allow it to run in the background. Restart the phone if lock-screen alerts still fail.',
          ja: 'まずOSで99chatの通知を許可し、「マイページ > 設定」でも通知がオンか確認してください。Androidではバッテリー最適化の対象外にし、バックグラウンド実行を許可してください。ロック画面でも来ない場合は再起動してください。',
          ko: '시스템 설정에서 99chat 알림을 허용한 뒤 「내 정보 > 설정」에서 알림이 켜져 있는지 확인하세요. 안드로이드는 배터리 최적화에서 제외하고 백그라운드를 허용하세요. 잠금 화면에도 없으면 재부팅 후 다시 시도하세요.',
        );
      case 'faq_send':
        return i18n.t(
          zhHans: '请确认网络正常、已登录，且对方未被拉黑。消息旁若出现感叹号，点一下可重发。长时间发不出时，可退出重新登录，或切换网络后再试。群聊被禁言时也无法发言。',
          zhHant: '請確認網路正常、已登入，且對方未被封鎖。訊息旁若出現驚嘆號，點一下可重發。長時間發不出時，可退出重新登入，或切換網路後再試。群聊被禁言時也無法發言。',
          en: 'Check the network, that you are signed in, and that the peer is not blocked. Tap the exclamation mark beside a failed message to resend. If it keeps failing, sign out and back in, or switch networks. You also cannot send in a muted group.',
          ja: 'ネットワーク、ログイン状態、ブロックしていないかを確認してください。失敗マークをタップすると再送できます。続く場合は再ログインか回線切替を試してください。発言禁止のグループでは送れません。',
          ko: '네트워크, 로그인 상태, 차단 여부를 확인하세요. 실패한 메시지 옆 느낌표를 누르면 재전송됩니다. 계속 안 되면 다시 로그인하거나 네트워크를 바꾸세요. 금언된 그룹에서는 보낼 수 없습니다.',
        );
      case 'faq_media':
        return i18n.t(
          zhHans: '请先允许相册和相机权限，并确认图片或视频不要过大。聊天里点加号即可发送。发送失败可点感叹号重试；仍失败请换网络，或把视频压短后再发。',
          zhHant: '請先允許相簿和相機權限，並確認圖片或影片不要過大。聊天裡點加號即可傳送。傳送失敗可點驚嘆號重試；仍失敗請換網路，或把影片壓短後再發。',
          en: 'Allow Photos and Camera access and keep the photo or video within size limits. Use the plus button in chat to send. Tap the exclamation mark to retry. If it still fails, switch networks or send a shorter video.',
          ja: '写真とカメラ権限を許可し、ファイルが大きすぎないか確認してください。チャットの「＋」から送信できます。失敗マークで再送し、続く場合は回線変更か短い動画にしてください。',
          ko: '사진과 카메라 권한을 허용하고 파일이 너무 크지 않은지 확인하세요. 채팅의 더하기로 보냅니다. 실패 시 느낌표로 재시도하고, 계속되면 네트워크를 바꾸거나 영상을 짧게 보내세요.',
        );
      case 'faq_network':
        return i18n.t(
          zhHans: '请先切换 Wi-Fi 和移动网络，或关闭 VPN 后再试。打开应用时如提示线路异常，可在登录或设置里切换节点。仍连不上时，请把当前时间和提示原文发给下方人工客服。',
          zhHant: '請先切換 Wi-Fi 和行動網路，或關閉 VPN 後再試。打開應用時如提示線路異常，可在登入或設定裡切換節點。仍連不上時，請把目前時間和提示原文發給下方人工客服。',
          en: 'Switch between Wi-Fi and mobile data, or turn off VPN. If a node error appears, change the API node in sign-in or settings. If it still fails, send the time and exact error text to the agent below.',
          ja: 'Wi-Fiとモバイル回線を切り替え、VPNをオフにしてください。ノード異常が出る場合はログインまたは設定で回線を切り替えてください。続く場合は時刻とエラー文を下の有人サポートへ送ってください。',
          ko: 'Wi-Fi와 모바일 데이터를 바꾸거나 VPN을 끄세요. 노드 오류가 나오면 로그인/설정에서 노드를 바꾸세요. 계속되면 시간과 오류 문구를 아래 상담원에게 보내 주세요.',
        );
      case 'about_what':
        return i18n.t(
          zhHans: '99chat 是即时通讯应用，支持私聊、群聊、通讯录、朋友圈、音视频通话，以及钱包充值提现、转账、红包、闪兑和生活缴费。',
          zhHant: '99chat 是即時通訊應用，支援私聊、群聊、通訊錄、朋友圈、音視頻通話，以及錢包儲值提現、轉帳、紅包、閃兌和生活繳費。',
          en: '99chat is a messenger for chats, groups, contacts, Moments, voice/video calls, plus wallet deposit/withdraw, transfers, red packets, convert, and utility payments.',
          ja: '99chatはチャット、グループ、連絡先、モーメント、通話に加え、ウォレット入出金、送金、お年玉、交換、公共料金に対応したメッセンジャーです。',
          ko: '99chat은 채팅, 그룹, 연락처, 모멘트, 통화와 지갑 입출금, 송금, 홍바오, 환전, 공과금을 지원하는 메신저입니다.',
        );
      case 'about_features':
        return i18n.t(
          zhHans: '底部可进入消息、通讯录、钱包、我的。聊天支持文字、图片、视频、语音、文件、红包、转账；钱包可充值、提现、闪兑；生活缴费可缴水电燃气和话费。版本以「我的」-「关于我们」为准。',
          zhHant: '底部可進入訊息、通訊錄、錢包、我的。聊天支援文字、圖片、影片、語音、檔案、紅包、轉帳；錢包可儲值、提現、閃兌；生活繳費可繳水電燃氣和話費。版本以「我的」-「關於我們」為準。',
          en: 'The tabs cover Chats, Contacts, Wallet, and Me. Chat supports text, photos, video, voice, files, red packets, and transfers. Wallet handles deposit, withdraw, and convert. Utilities cover electricity, water, gas, and mobile top-up. See Me > About Us for the version.',
          ja: '下部タブはチャット、連絡先、ウォレット、マイページです。チャットは文字・画像・動画・音声・ファイル・お年玉・送金に対応。ウォレットで入出金と交換、公共料金で電気・水道・ガス・チャージができます。バージョンは「このアプリについて」で確認してください。',
          ko: '하단은 채팅, 연락처, 지갑, 내 정보입니다. 채팅은 글·사진·영상·음성·파일·홍바오·송금을 지원합니다. 지갑에서 입출금·환전, 공과금에서 전기·수도·가스·휴대폰 충전을 합니다. 버전은 「내 정보 > 정보」에서 확인하세요.',
        );
      case 'about_moments':
        return i18n.t(
          zhHans: '在「我的」或个人资料里可进入朋友圈，发布图文或视频动态，也可浏览好友动态。发布失败请检查网络和相册权限；不想被别人看到可在朋友圈权限里调整。',
          zhHant: '在「我的」或個人資料裡可進入朋友圈，發佈圖文或影片動態，也可瀏覽好友動態。發佈失敗請檢查網路和相簿權限；不想被別人看到可在朋友圈權限裡調整。',
          en: 'Open Moments from Me or a profile to post photos/video or view friends. If posting fails, check network and photo permission. Adjust Moments privacy if you do not want others to see a post.',
          ja: '「マイページ」またはプロフィールからモーメントを開き、画像・動画を投稿したり友人の投稿を見たりできます。失敗時は回線と写真権限を確認し、公開範囲は権限設定で変更できます。',
          ko: '「내 정보」또는 프로필에서 모멘트로 들어가 사진/영상을 올리거나 친구 글을 봅니다. 실패 시 네트워크와 사진 권한을 확인하고, 공개 범위는 모멘트 권한에서 바꾸세요.',
        );
      case 'about_call':
        return i18n.t(
          zhHans: '在单聊或群聊中可发起语音/视频通话（需麦克风和相机权限）。Web 端暂不支持通话，请用手机 App。打不通时请确认双方在线、权限已开，并检查网络。',
          zhHant: '在單聊或群聊中可發起語音/視訊通話（需麥克風和相機權限）。Web 端暫不支援通話，請用手機 App。打不通時請確認雙方在線、權限已開，並檢查網路。',
          en: 'Start a voice or video call from a chat (microphone and camera permission required). Calls are not available on web; use the mobile app. If it fails, check that both sides are online, permissions are on, and the network is stable.',
          ja: '1対1またはグループから音声/ビデオ通話できます（マイクとカメラ権限が必要）。Webでは非対応のためスマホアプリをご利用ください。つながらない場合は双方のオンライン、権限、回線を確認してください。',
          ko: '1:1 또는 그룹에서 음성/영상 통화를 걸 수 있습니다(마이크·카메라 권한 필요). 웹은 통화를 지원하지 않으니 모바일 앱을 쓰세요. 안 되면 상대 온라인, 권한, 네트워크를 확인하세요.',
        );
      case 'security_pin':
        return i18n.t(
          zhHans: '支付密码用于钱包付款、转账、红包和提现。请到「我的」-「设置」-「账号安全」设置或修改。忘记时按页面短信验证重置。不要把支付密码告诉任何人，客服也不会向你索取。',
          zhHant: '支付密碼用於錢包付款、轉帳、紅包和提現。請到「我的」-「設定」-「帳號安全」設定或修改。忘記時按頁面簡訊驗證重設。不要把支付密碼告訴任何人，客服也不會向你索取。',
          en: 'The payment PIN is used for wallet pay, transfers, red packets, and withdrawals. Set or change it in Me > Settings > Account Security. Reset it with SMS on that page if you forget it. Never share the PIN; support will not ask for it.',
          ja: '決済パスワードは支払い、送金、お年玉、出金に使います。「マイページ > 設定 > アカウントセキュリティ」で設定・変更し、忘れた場合はSMSで再設定できます。他人やサポートに教えてはいけません。',
          ko: '결제 비밀번호는 지갑 결제, 송금, 홍바오, 출금에 쓰입니다. 「내 정보 > 설정 > 계정 보안」에서 설정·변경하고, 잊으면 문자 인증으로 재설정하세요. 상담원을 포함해 누구에게도 알려 주지 마세요.',
        );
      case 'security_devices':
        return i18n.t(
          zhHans: '请到「我的」-「设置」-「账号安全」-「登录设备」查看已登录设备。发现陌生设备请立即退出该设备，并修改登录密码。不要在公共手机上勾选自动登录。',
          zhHant: '請到「我的」-「設定」-「帳號安全」-「登入裝置」查看已登入裝置。發現陌生裝置請立即退出該裝置，並修改登入密碼。不要在公共手機上勾選自動登入。',
          en: 'Review devices in Me > Settings > Account Security > Login devices. Sign out unknown devices and change your password. Do not stay signed in on a shared phone.',
          ja: '「マイページ > 設定 > アカウントセキュリティ > ログイン端末」で確認できます。見知らぬ端末はログアウトし、パスワードを変更してください。共用端末では自動ログインしないでください。',
          ko: '「내 정보 > 설정 > 계정 보안 > 로그인 기기」에서 확인하세요. 모르는 기기는 로그아웃하고 비밀번호를 바꾸세요. 공용 폰에서는 자동 로그인하지 마세요.',
        );
      case 'security_password':
        return i18n.t(
          zhHans: '登录密码在「我的」-「设置」-「账号安全」中修改，通常需要短信验证码。修改后请用新密码重新登录。不要使用过于简单的密码，也不要与支付密码相同。',
          zhHant: '登入密碼在「我的」-「設定」-「帳號安全」中修改，通常需要簡訊驗證碼。修改後請用新密碼重新登入。不要使用過於簡單的密碼，也不要與支付密碼相同。',
          en: 'Change the login password in Me > Settings > Account Security (SMS is usually required). Sign in again with the new password. Avoid simple passwords and do not reuse the payment PIN.',
          ja: 'ログインパスワードは「マイページ > 設定 > アカウントセキュリティ」で変更でき、SMS認証が必要なことがあります。変更後は新しいパスワードで再ログインしてください。簡単なパスワードや決済パスワードの使い回しは避けてください。',
          ko: '로그인 비밀번호는 「내 정보 > 설정 > 계정 보안」에서 바꾸며 보통 문자 인증이 필요합니다. 바꾼 뒤 새 비밀번호로 다시 로그인하세요. 쉬운 비밀번호나 결제 비밀번호와 같게 쓰지 마세요.',
        );
      case 'security_phone':
        return i18n.t(
          zhHans: '手机号用于登录验证和找回密码。请在「账号安全」中绑定或更换。换绑需要原号码或短信验证。收不到验证码时，请确认号码、信号和短信拦截。',
          zhHant: '手機號用於登入驗證和找回密碼。請在「帳號安全」中綁定或更換。換綁需要原號碼或簡訊驗證。收不到驗證碼時，請確認號碼、訊號和簡訊攔截。',
          en: 'The phone number is used for sign-in and password recovery. Bind or change it in Account Security. Changing it requires the old number or SMS. If no code arrives, check the number, signal, and SMS filters.',
          ja: '電話番号はログインとパスワード再設定に使います。アカウントセキュリティで連携・変更できます。変更には元の番号またはSMSが必要です。届かない場合は番号、電波、SMSフィルタを確認してください。',
          ko: '휴대폰 번호는 로그인과 비밀번호 찾기에 쓰입니다. 계정 보안에서 연결하거나 바꾸세요. 변경 시 기존 번호 또는 문자가 필요합니다. 문자가 없으면 번호, 수신, 문자 차단을 확인하세요.',
        );
      case 'cash_deposit_time':
        return i18n.t(
          zhHans: '请在「钱包」发起充值，并核对币种与网络。到账取决于链上确认和当前通道，拥堵时会变慢。完成后余额会更新；可在钱包记录里查看状态。低于最小充值额可能无法入账。',
          zhHant: '請在「錢包」發起儲值，並核對幣種與網路。到帳取決於鏈上確認和目前通道，壅塞時會變慢。完成後餘額會更新；可在錢包記錄裡查看狀態。低於最小儲值額可能無法入帳。',
          en: 'Start a deposit in Wallet and confirm the coin and network. Arrival depends on on-chain confirmations and can slow down when busy. The balance updates when done; check Wallet records. Amounts below the minimum may not credit.',
          ja: 'ウォレットから入金し、通貨とネットワークを確認してください。反映はチェーン確認と混雑状況によります。完了後は残高とウォレット記録を確認してください。最低額未満は入金されないことがあります。',
          ko: '지갑에서 입금하고 코인·네트워크를 확인하세요. 도착은 온체인 확인과 혼잡도에 따라 달라집니다. 완료되면 잔액과 지갑 기록을 보세요. 최소 금액 미만은 입금되지 않을 수 있습니다.',
        );
      case 'cash_withdraw_missing':
        return i18n.t(
          zhHans: '请核对提现地址、网络是否与收款方完全一致，并在钱包记录查看状态。链上确认需要时间。手续费会在提交前展示，请预留余额。长时间未到账请保留交易哈希，在下方发给人工客服。',
          zhHant: '請核對提現地址、網路是否與收款方完全一致，並在錢包記錄查看狀態。鏈上確認需要時間。手續費會在提交前展示，請預留餘額。長時間未到帳請保留交易雜湊，在下方發給人工客服。',
          en: 'Confirm the address and network match the recipient, then check Wallet records. On-chain confirmation takes time. Fees are shown before submit; keep enough balance. If it stays pending, send the tx hash to the agent below.',
          ja: '出金アドレスとネットワークが受取側と一致するか、ウォレット記録を確認してください。チェーン確認には時間がかかります。手数料は申請前に表示されます。長引く場合はTxハッシュを下の有人サポートへ送ってください。',
          ko: '출금 주소와 네트워크가 수취인과 같은지, 지갑 기록을 확인하세요. 온체인 확인에는 시간이 걸립니다. 수수료는 신청 전에 보이니 잔액을 남겨 두세요. 오래 지연되면 Tx 해시를 아래 상담원에게 보내 주세요.',
        );
      case 'cash_redpacket':
        return i18n.t(
          zhHans: '发红包需要钱包余额和支付密码。余额不足、支付密码错误或网络中断都会失败。领取失败可能因为已领完、已过期或你不在该群。请到钱包记录核对，仍异常把时间和会话发给人工客服。',
          zhHant: '發紅包需要錢包餘額和支付密碼。餘額不足、支付密碼錯誤或網路中斷都會失敗。領取失敗可能因為已領完、已過期或你不在該群。請到錢包記錄核對，仍異常把時間和會話發給人工客服。',
          en: 'Sending a red packet needs wallet balance and the payment PIN. It fails if the balance is low, the PIN is wrong, or the network drops. Claiming can fail if it is empty, expired, or you are not in the group. Check Wallet records, then send the time and chat to the agent if needed.',
          ja: 'お年玉送信には残高と決済パスワードが必要です。残高不足、パスワード誤り、回線切断で失敗します。受け取り失敗は終了・期限切れ・グループ未参加のことがあります。ウォレット記録を確認し、続く場合は時刻と会話を有人サポートへ。',
          ko: '홍바오를 보내려면 잔액과 결제 비밀번호가 필요합니다. 잔액 부족, 비밀번호 오류, 네트워크 끊김이면 실패합니다. 수령 실패는 소진, 만료, 그룹 미참여일 수 있습니다. 지갑 기록을 보고 계속되면 시간과 대화를 상담원에게 보내 주세요.',
        );
      case 'cash_transfer':
        return i18n.t(
          zhHans: '转账请在聊天或钱包中操作，确认收款人和金额后输入支付密码。失败常见原因：余额不足、支付密码错误、对方账号异常。转账记录可在钱包记录查看。不要向陌生人转账。',
          zhHant: '轉帳請在聊天或錢包中操作，確認收款人和金額後輸入支付密碼。失敗常見原因：餘額不足、支付密碼錯誤、對方帳號異常。轉帳記錄可在錢包記錄查看。不要向陌生人轉帳。',
          en: 'Transfer from chat or Wallet, confirm the recipient and amount, then enter the payment PIN. Typical failures: low balance, wrong PIN, or the recipient account is restricted. Check Wallet records. Do not transfer to strangers.',
          ja: '送金はチャットまたはウォレットから行い、相手と金額を確認して決済パスワードを入力します。失敗は残高不足、パスワード誤り、相手アカウント異常が多いです。記録はウォレットで確認し、見知らぬ人へは送金しないでください。',
          ko: '채팅 또는 지갑에서 송금하고 상대와 금액을 확인한 뒤 결제 비밀번호를 입력하세요. 실패는 잔액 부족, 비밀번호 오류, 상대 계정 이상인 경우가 많습니다. 기록은 지갑에서 보고, 모르는 사람에게 보내지 마세요.',
        );
      case 'social_friend':
        return i18n.t(
          zhHans: '可在首页搜索或通讯录里找对方账号，发送好友申请。对方通过后才能私聊。搜不到时请核对账号是否输对；对方关闭加好友时需对方先加你。申请长时间无回应，可请对方在新朋友里查看。',
          zhHant: '可在首頁搜尋或通訊錄裡找對方帳號，傳送好友申請。對方通過後才能私聊。搜不到時請核對帳號是否輸對；對方關閉加好友時需對方先加你。申請長時間無回應，可請對方在新朋友裡查看。',
          en: 'Search on Home or Contacts and send a friend request. Chat starts after they accept. If search fails, check the ID. If they disabled friend requests, they must add you first. Ask them to check New Friends if there is no reply.',
          ja: 'ホーム検索または連絡先から申請できます。承認後にチャットできます。見つからない場合はIDを確認し、申請受付を閉じている場合は相手から追加してもらってください。返事がない場合は相手の「新しい友達」を確認してもらってください。',
          ko: '홈 검색이나 연락처에서 친구 신청을 보내세요. 수락 후 채팅할 수 있습니다. 검색이 안 되면 계정을 확인하고, 상대가 신청을 막았으면 상대가 먼저 추가해야 합니다. 답이 없으면 상대의 새 친구 목록을 봐 달라고 하세요.',
        );
      case 'social_create':
        return i18n.t(
          zhHans: '在首页点右上角加号，选择「创建群聊」，勾选好友后完成。群主可在群资料改群名、管理成员和禁言。普通成员可在群资料退出群聊。',
          zhHant: '在首頁點右上角加號，選擇「建立群聊」，勾選好友後完成。群主可在群資料改群名、管理成員和禁言。普通成員可在群資料退出群聊。',
          en: 'Tap the plus button on Home, choose Create group, and pick friends. Owners can rename the group, manage members, and mute in the group profile. Members can leave there.',
          ja: 'ホーム右上の「＋」から「グループ作成」を選び、メンバーを指定します。オーナーはグループプロフィールで名前、メンバー、発言制限を管理できます。一般メンバーはそこから退室できます。',
          ko: '홈 오른쪽 위 더하기에서 「그룹 만들기」를 고르고 친구를 선택하세요. 그룹장은 그룹 자료에서 이름, 멤버, 금언을 관리합니다. 일반 멤버는 거기서 나갈 수 있습니다.',
        );
      case 'social_join':
        return i18n.t(
          zhHans: '可通过搜索、邀请链接或群二维码进群。部分群需要管理员审核。进不去可能是群已满、需要审核，或你已被移出。被踢后需群主重新邀请。',
          zhHant: '可透過搜尋、邀請連結或群二維碼進群。部分群需要管理員審核。進不去可能是群已滿、需要審核，或你已被移出。被踢後需群主重新邀請。',
          en: 'Join via search, invite link, or group QR. Some groups need admin approval. Join can fail if the group is full, pending review, or you were removed. After a kick, the owner must invite you again.',
          ja: '検索、招待リンク、グループQRから参加できます。承認が必要なグループもあります。満員、審査待ち、退出済みだと参加できません。キック後はオーナーの再招待が必要です。',
          ko: '검색, 초대 링크, 그룹 QR로 들어갈 수 있습니다. 관리자 승인이 필요한 그룹도 있습니다. 정원 초과, 심사 중, 이미 나가진 상태면 실패합니다. 강퇴 후에는 그룹장이 다시 초대해야 합니다.',
        );
      case 'social_mute':
        return i18n.t(
          zhHans: '打开该群聊，点右上角进入群资料，可设置消息免打扰。免打扰后仍能在会话列表看到新消息，但不会频繁弹通知。需要发言时确认自己没有被禁言。',
          zhHant: '打開該群聊，點右上角進入群資料，可設定訊息免打擾。免打擾後仍能在會話列表看到新訊息，但不會頻繁彈通知。需要發言時確認自己沒有被禁言。',
          en: 'Open the group, tap the top-right to open the profile, and enable mute. You will still see new messages in the chat list without frequent banners. Check that you are not muted if you cannot send.',
          ja: 'グループを開き、右上からプロフィールで通知オフにできます。オフでも会話一覧には新着が出ますが、頻繁な通知は止まります。発言できない場合は発言禁止でないか確認してください。',
          ko: '그룹을 열고 오른쪽 위에서 그룹 자료로 들어가 알림을 끄세요. 꺼도 목록에는 새 메시지가 보이지만 알림은 줄어듭니다. 말이 안 나가면 금언 상태인지 확인하세요.',
        );
      case 'auth_register':
        return i18n.t(
          zhHans: '打开 99chat，按注册流程填写信息并完成短信验证。请使用本人手机号，验证码不要发给任何人。注册后请立即设置登录密码和支付密码。',
          zhHant: '打開 99chat，按註冊流程填寫資訊並完成簡訊驗證。請使用本人手機號，驗證碼不要發給任何人。註冊後請立即設定登入密碼和支付密碼。',
          en: 'Open 99chat, complete sign-up and SMS verification with your own number. Never share the code. Set a login password and payment PIN right after registering.',
          ja: '99chatを開き、案内に従ってSMS認証まで完了してください。本人の電話番号を使い、認証コードは共有しないでください。登録後すぐにログインパスワードと決済パスワードを設定してください。',
          ko: '99chat을 열고 가입과 문자 인증을 완료하세요. 본인 번호를 쓰고 인증코드는 공유하지 마세요. 가입 직후 로그인 비밀번호와 결제 비밀번호를 설정하세요.',
        );
      case 'auth_forgot':
        return i18n.t(
          zhHans: '在登录页选择找回密码，用已绑定手机号收取验证码后重置。若手机号停用或收不到短信，请在下方说明注册手机号和大概注册时间，由人工协助核实。',
          zhHant: '在登入頁選擇找回密碼，用已綁定手機號收取驗證碼後重設。若手機號停用或收不到簡訊，請在下方說明註冊手機號和大概註冊時間，由人工協助核實。',
          en: 'Use Forgot password on the login screen and reset with the bound phone SMS. If the number is dead or no SMS arrives, send the registered number and approximate sign-up time to the agent below.',
          ja: 'ログイン画面のパスワード再設定から、連携済み電話のSMSでリセットできます。番号が使えない、SMSが届かない場合は登録番号とおおよその登録時期を下の有人サポートへ送ってください。',
          ko: '로그인 화면의 비밀번호 찾기로 연결된 휴대폰 문자로 재설정하세요. 번호가 안 되거나 문자가 없으면 가입 번호와 대략 가입 시점을 아래 상담원에게 알려 주세요.',
        );
      case 'auth_code':
        return i18n.t(
          zhHans: '请确认手机号无误、信号正常，并检查短信拦截或垃圾箱。可等待倒计时结束后再获取。同一号码短时间请求过多会被限制。验证码仅用于本人操作，不要转发。',
          zhHant: '請確認手機號無誤、訊號正常，並檢查簡訊攔截或垃圾箱。可等待倒計時結束後再獲取。同一號碼短時間請求過多會被限制。驗證碼僅用於本人操作，不要轉發。',
          en: 'Confirm the number, signal, and SMS junk filter. Wait for the countdown before requesting again. Too many requests in a short time can be rate-limited. Do not forward the code.',
          ja: '番号、電波、SMS迷惑フォルダを確認し、カウントダウン後に再取得してください。短時間の連続リクエストは制限されます。認証コードは転送しないでください。',
          ko: '번호, 수신, 스팸함을 확인하고 카운트다운이 끝난 뒤 다시 요청하세요. 짧은 시간에 너무 많이 요청하면 제한됩니다. 인증코드는 전달하지 마세요.',
        );
      case 'auth_disable':
        return i18n.t(
          zhHans: '账号被限制后可能无法登录或无法使用钱包。请在下方发送注册手机号、出现限制的时间和提示原文，由人工核实。不要向自称客服的陌生人转账或提供验证码。',
          zhHant: '帳號被限制後可能無法登入或無法使用錢包。請在下方傳送註冊手機號、出現限制的時間和提示原文，由人工核實。不要向自稱客服的陌生人轉帳或提供驗證碼。',
          en: 'A restricted account may be unable to sign in or use Wallet. Send the registered number, when it started, and the exact message to the agent below. Never transfer money or share codes with anyone claiming to be support.',
          ja: '制限されるとログインやウォレットが使えないことがあります。登録番号、発生時刻、エラー文を下の有人サポートへ送ってください。サポートを名乗る他人への送金や認証コード共有はしないでください。',
          ko: '제한되면 로그인이나 지갑을 못 쓸 수 있습니다. 가입 번호, 발생 시간, 안내 문구를 아래 상담원에게 보내 주세요. 상담원을 사칭한 사람에게 송금하거나 인증코드를 주지 마세요.',
        );
      case 'life_entry':
        return i18n.t(
          zhHans: '请打开「钱包」，进入生活缴费。可缴电费、水费、燃气和手机话费。首次使用可能需要定位以便匹配当地渠道。请只通过 99chat 官方入口缴费，不要点聊天里的不明链接。',
          zhHant: '請打開「錢包」，進入生活繳費。可繳電費、水費、燃氣和手機話費。首次使用可能需要定位以便匹配當地管道。請只透過 99chat 官方入口繳費，不要點聊天裡的不明連結。',
          en: 'Open Wallet and enter Utilities to pay electricity, water, gas, and mobile top-up. Location may be needed the first time to match local providers. Pay only through the official 99chat entry, not unknown chat links.',
          ja: 'ウォレットの公共料金から電気、水道、ガス、携帯チャージができます。初回は地域チャネル合わせのため位置情報が必要なことがあります。99chat公式入口以外のリンクでは支払わないでください。',
          ko: '지갑에서 공과금으로 들어가 전기·수도·가스·휴대폰 충전을 하세요. 처음에는 지역 채널 매칭을 위해 위치가 필요할 수 있습니다. 99chat 공식 메뉴가 아닌 채팅 링크로는 납부하지 마세요.',
        );
      case 'life_fail':
        return i18n.t(
          zhHans: '请核对户号/手机号、城市和缴费渠道是否选对，钱包余额是否足够，支付密码是否正确。失败订单可在缴费记录或钱包记录查看。仍失败请把户号后四位、时间和失败原因发给人工客服。',
          zhHant: '請核對戶號/手機號、城市和繳費管道是否選對，錢包餘額是否足夠，支付密碼是否正確。失敗訂單可在繳費記錄或錢包記錄查看。仍失敗請把戶號後四位、時間和失敗原因發給人工客服。',
          en: 'Check the account or phone number, city, provider, wallet balance, and payment PIN. Failed orders appear in utility or wallet records. If it still fails, send the last four digits, time, and error to the agent.',
          ja: 'お客様番号/携帯番号、都市、チャネル、残高、決済パスワードを確認してください。失敗は支払い履歴またはウォレット記録に出ます。続く場合は番号下4桁、時刻、理由を有人サポートへ。',
          ko: '고객번호/휴대폰, 도시, 채널, 잔액, 결제 비밀번호를 확인하세요. 실패 건은 납부 내역이나 지갑 기록에 있습니다. 계속되면 번호 뒤 4자리, 시간, 사유를 상담원에게 보내 주세요.',
        );
      case 'life_record':
        return i18n.t(
          zhHans: '缴费成功或失败都会留下记录。请到生活缴费页查看订单，也可在「钱包」记录里按时间查找。到账以缴费单位回执为准，一般会在成功后更新状态。',
          zhHant: '繳費成功或失敗都會留下記錄。請到生活繳費頁查看訂單，也可在「錢包」記錄裡按時間查找。到帳以繳費單位回執為準，一般會在成功後更新狀態。',
          en: 'Successful and failed payments are recorded. Check orders on the Utilities page or Wallet records by time. The provider receipt is authoritative; status usually updates after success.',
          ja: '成功も失敗も記録されます。公共料金ページまたはウォレット記録で確認してください。入金は事業者の結果が基準で、成功後に状態が更新されます。',
          ko: '성공·실패 모두 기록이 남습니다. 공과금 페이지나 지갑 기록에서 시간순으로 보세요. 최종은 납부 기관 결과이며, 성공 후 상태가 갱신됩니다.',
        );
      case 'life_balance':
        return i18n.t(
          zhHans: '生活缴费从钱包余额扣款。余额不足时，请先到「钱包」完成充值，到账后再缴费。充值网络、币种请与钱包页提示保持一致。',
          zhHant: '生活繳費從錢包餘額扣款。餘額不足時，請先到「錢包」完成儲值，到帳後再繳費。儲值網路、幣種請與錢包頁提示保持一致。',
          en: 'Utilities are paid from wallet balance. If it is too low, deposit in Wallet first, then pay after the funds arrive. Use the network and coin shown on the deposit page.',
          ja: '公共料金はウォレット残高から引き落とされます。不足時は先に入金し、反映後に支払ってください。入金の通貨とネットワークはウォレットの案内に合わせてください。',
          ko: '공과금은 지갑 잔액에서 빠집니다. 부족하면 먼저 지갑에 입금하고 들어온 뒤 납부하세요. 입금 코인과 네트워크는 지갑 안내와 같게 하세요.',
        );
      case 'other_profile':
        return i18n.t(
          zhHans: '打开「我的」，点头像进入个人资料，可改昵称和头像。头像需要相册权限；昵称可能有修改间隔。改完后好友侧有时会稍晚刷新。',
          zhHant: '打開「我的」，點頭像進入個人資料，可改暱稱和頭像。頭像需要相簿權限；暱稱可能有修改間隔。改完後好友側有時會稍晚刷新。',
          en: 'Open Me, tap the avatar to edit nickname and photo. Photo access is required. Nickname changes may have a cooldown. Friends may see the update after a short delay.',
          ja: '「マイページ」のアイコンからニックネームと画像を変更できます。画像には写真権限が必要で、ニックネームは変更間隔がある場合があります。友人側への反映は少し遅れることがあります。',
          ko: '「내 정보」에서 프로필 사진을 눌러 닉네임과 사진을 바꾸세요. 사진 권한이 필요하고, 닉네임은 변경 간격이 있을 수 있습니다. 친구 쪽 반영은 조금 늦을 수 있습니다.',
        );
      case 'other_report':
        return i18n.t(
          zhHans: '如需投诉或举报，请在下方说明时间、对方账号或群、问题截图要点。我们会转人工处理。请勿在举报内容里发送支付密码或验证码。',
          zhHant: '如需投訴或檢舉，請在下方說明時間、對方帳號或群、問題截圖要點。我們會轉人工處理。請勿在舉報內容裡傳送支付密碼或驗證碼。',
          en: 'To report abuse, send the time, the user or group, and what happened in the box below. An agent will follow up. Do not include payment PINs or SMS codes.',
          ja: '通報は下の入力に日時、相手やグループ、内容を書いてください。有人対応に回します。決済パスワードや認証コードは書かないでください。',
          ko: '신고하려면 아래 입력에 시간, 상대 계정이나 그룹, 내용을 적어 주세요. 상담원이 이어서 처리합니다. 결제 비밀번호나 인증코드는 넣지 마세요.',
        );
      case 'other_feedback':
        return i18n.t(
          zhHans: '功能建议或使用体验可直接写在下方输入框发给客服。请尽量说明所在页面和期望效果，方便我们跟进。',
          zhHant: '功能建議或使用體驗可直接寫在下方輸入框發給客服。請盡量說明所在頁面和期望效果，方便我們跟進。',
          en: 'Send product ideas or issues in the box below. Include the screen you were on and what you expected so we can follow up.',
          ja: 'ご意見は下の入力から送れます。画面名と期待する動作を書いていただけると対応しやすいです。',
          ko: '기능 제안이나 불편은 아래 입력창으로 보내 주세요. 어느 화면인지와 기대한 동작을 적어 주시면 따라가기 쉽습니다.',
        );
      case 'other_human':
        return i18n.t(
          zhHans: '请直接在下方输入问题，即可转接人工在线客服。发文字、图片或视频都可以。高峰时请稍候，坐席正在输入时会有提示。',
          zhHant: '請直接在下方輸入問題，即可轉接人工線上客服。發文字、圖片或影片都可以。高峰時請稍候，坐席正在輸入時會有提示。',
          en: 'Type below to reach a live agent. Text, photos, or videos are fine. Please wait at peak times; you will see a typing hint when an agent is responding.',
          ja: '下に質問を入力すると有人サポートにつながります。文字・画像・動画を送れます。混雑時はお待ちください。担当者が入力中なら表示されます。',
          ko: '아래 입력창에 질문을 쓰면 상담원에게 연결됩니다. 글·사진·영상을 보낼 수 있습니다. 바쁠 때는 잠시 기다려 주세요. 상담원이 입력 중이면 표시됩니다.',
        );
      default:
        return '';
    }
  }

  bool get _showFaqPanel =>
      _historyReady && (_sentItems.isEmpty || _faqOpen);

  void _onCategoryTap(String id) {
    setState(() {
      _selectedCategoryId = id;
      _openSubtopicId = null;
      _faqOpen = true;
    });
  }

  void _onSubtopicTap(String id) {
    setState(() {
      _openSubtopicId = id;
    });
  }

  void _onAnswerBack() {
    setState(() {
      _openSubtopicId = null;
    });
  }

  void _onSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _inputController.clear();
    final echoId = const Uuid().v4();
    setState(() {
      _sentItems.add(
        _CsSentItem(
          kind: _CsSentKind.text,
          name: '',
          content: text,
          messageType: 0,
          echoId: echoId,
        ),
      );
      _faqOpen = false;
    });
    _scrollConversationToEnd();
    unawaited(_postText(content: text, echoId: echoId));
  }

  Future<void> _loadOfficialWebsite() async {
    try {
      final info = await PlatformApi.instance.fetchContact();
      if (!mounted) {
        return;
      }
      setState(() {
        _officialWebsite = info.website.trim();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE official website: $e');
      }
    }
  }

  Future<void> _openOfficialWebsite() async {
    final raw = _officialWebsite.trim();
    if (raw.isEmpty) {
      return;
    }
    var value = raw;
    if (!value.contains('://')) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE open official website: $e');
      }
    }
  }

  Future<void> _bootstrap() async {
    try {
      final session = await KefuVisitorSession.ensure();
      _session = session;
      final messages = await KefuVisitorApi.instance.listMessages(
        contactId: session.sourceId,
        conversationId: session.conversationId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sentItems
          ..clear()
          ..addAll(messages.expand(_itemsFromMessage));
        _faqOpen = _sentItems.isEmpty;
        _historyReady = true;
      });
      _scrollConversationToEnd();
      _cable.connect(session.pubsubToken);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE bootstrap: $e');
      }
      if (mounted) {
        setState(() {
          _faqOpen = _sentItems.isEmpty;
          _historyReady = true;
        });
      }
    }
  }

  Future<KefuVisitorSession?> _ensureSession() async {
    final existing = _session;
    if (existing != null) {
      return existing;
    }
    try {
      final session = await KefuVisitorSession.ensure();
      _session = session;
      _cable.connect(session.pubsubToken);
      return session;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE session: $e');
      }
      return null;
    }
  }

  Future<void> _postText({
    required String content,
    required String echoId,
  }) async {
    try {
      final session = await _ensureSession();
      if (session == null) {
        return;
      }
      final message = await KefuVisitorApi.instance.sendText(
        contactId: session.sourceId,
        conversationId: session.conversationId,
        content: content,
        echoId: echoId,
      );
      if (!mounted) {
        return;
      }
      _applyRemoteMessage(message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE send text: $e');
      }
    }
  }

  void _onCableMessage(KefuVisitorMessage message) {
    if (!mounted) {
      return;
    }
    _applyRemoteMessage(message);
  }

  void _applyRemoteMessage(KefuVisitorMessage message) {
    var incoming = _itemsFromMessage(message);
    if (incoming.isEmpty) {
      return;
    }
    final echo = message.echoId.trim();
    final serverId = message.id.trim();
    setState(() {
      if (echo.isNotEmpty &&
          _sentItems.any(
            (item) => item.echoId == echo && item.serverId.isEmpty,
          )) {
        final pending = _sentItems
            .where((item) => item.echoId == echo && item.serverId.isEmpty)
            .toList();
        incoming = _mergePendingLocals(pending, incoming);
        _sentItems.removeWhere(
          (item) => item.echoId == echo && item.serverId.isEmpty,
        );
        _sentItems.addAll(incoming);
        return;
      }
      if (serverId.isNotEmpty &&
          _sentItems.any((item) => item.serverId == serverId)) {
        return;
      }
      _sentItems.addAll(incoming);
    });
    _scrollConversationToEnd();
  }

  List<_CsSentItem> _mergePendingLocals(
    List<_CsSentItem> pending,
    List<_CsSentItem> incoming,
  ) {
    final unused = List<_CsSentItem>.from(pending);
    return incoming.map((item) {
      if (item.kind == _CsSentKind.text || item.kind == _CsSentKind.system) {
        return item;
      }
      final idx = unused.indexWhere((local) => local.kind == item.kind);
      if (idx < 0) {
        return item;
      }
      final local = unused.removeAt(idx);
      return _CsSentItem(
        kind: item.kind,
        name: item.name.isNotEmpty ? item.name : local.name,
        path: local.path,
        content: item.content,
        messageType: 0,
        echoId: item.echoId.isNotEmpty ? item.echoId : local.echoId,
        serverId: item.serverId,
        remoteUrl: item.remoteUrl,
        thumbUrl: item.thumbUrl,
        localThumbPath: local.localThumbPath,
        bytes: local.bytes,
        width: item.width > 0 ? item.width : local.width,
        height: item.height > 0 ? item.height : local.height,
      );
    }).toList();
  }

  List<_CsSentItem> _itemsFromMessage(KefuVisitorMessage message) {
    final items = <_CsSentItem>[];
    final content = message.content.trim();
    final type = message.messageType;
    if (content.isNotEmpty) {
      items.add(
        _CsSentItem(
          kind: (type == 2 || type == 3) ? _CsSentKind.system : _CsSentKind.text,
          name: '',
          content: content,
          messageType: type,
          echoId: message.echoId,
          serverId: message.id,
        ),
      );
    }
    for (final attachment in message.attachments) {
      items.add(
        _CsSentItem(
          kind: _kindFromFileType(attachment.fileType),
          name: attachment.fileName,
          messageType: type,
          echoId: message.echoId,
          serverId: message.id,
          remoteUrl: attachment.dataUrl,
          thumbUrl: attachment.thumbUrl,
          width: attachment.width,
          height: attachment.height,
        ),
      );
    }
    return items;
  }

  _CsSentKind _kindFromFileType(String fileType) {
    switch (fileType.trim().toLowerCase()) {
      case 'image':
      case '0':
        return _CsSentKind.image;
      case 'video':
      case '2':
        return _CsSentKind.video;
      default:
        return _CsSentKind.file;
    }
  }

  Future<int> _attachmentSize({
    required String path,
    List<int>? bytes,
    int? hinted,
  }) async {
    if (hinted != null && hinted > 0) {
      return hinted;
    }
    if (bytes != null) {
      return bytes.length;
    }
    if (!kIsWeb && path.trim().isNotEmpty) {
      try {
        return await File(path).length();
      } catch (_) {}
    }
    return 0;
  }

  Future<void> _sendPickedAttachment(_CsSentItem item) async {
    try {
      final session = await _ensureSession();
      if (session == null) {
        return;
      }
      var thumbnailPath = item.localThumbPath.trim();
      if (item.kind == _CsSentKind.video &&
          thumbnailPath.isEmpty &&
          !kIsWeb) {
        final videoPath = item.path.trim().isNotEmpty
            ? _csLocalFilePath(item.path)
            : '';
        if (videoPath.isNotEmpty) {
          try {
            thumbnailPath =
                await buildVideoSnapshotForSend(videoPath: videoPath) ?? '';
          } catch (e) {
            if (kDebugMode) {
              debugPrint('CUSTOMER_SERVICE video thumbnail: $e');
            }
          }
        }
      }
      final message = await KefuVisitorApi.instance.sendAttachments(
        contactId: session.sourceId,
        conversationId: session.conversationId,
        echoId: item.echoId,
        filename: item.name,
        path: item.path,
        bytes: item.bytes,
        width: item.width,
        height: item.height,
        thumbnailPath: thumbnailPath,
      );
      if (!mounted) {
        return;
      }
      _applyRemoteMessage(message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE send attachment: $e');
      }
    }
  }

  Future<void> _enqueueAttachment({
    required _CsSentKind kind,
    required String name,
    required String path,
    List<int>? bytes,
    int? hintedSize,
    int width = 0,
    int height = 0,
  }) async {
    final size = await _attachmentSize(
      path: path,
      bytes: bytes,
      hinted: hintedSize,
    );
    if (size > KefuVisitorApi.maxAttachmentBytes) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE skip oversize: $name');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    var localThumbPath = '';
    var videoWidth = width;
    var videoHeight = height;
    if (kind == _CsSentKind.video && !kIsWeb) {
      final videoPath = path.trim().isNotEmpty ? _csLocalFilePath(path) : '';
      if (videoPath.isNotEmpty) {
        try {
          localThumbPath =
              await buildVideoSnapshotForSend(videoPath: videoPath) ?? '';
        } catch (e) {
          if (kDebugMode) {
            debugPrint('CUSTOMER_SERVICE video thumbnail: $e');
          }
        }
        if (videoWidth <= 0 || videoHeight <= 0) {
          final probed = await _probeVideoPixelSize(videoPath);
          if (probed != null) {
            videoWidth = probed.width;
            videoHeight = probed.height;
          } else if (localThumbPath.isNotEmpty) {
            final cover = await probeLocalImageSize(localThumbPath);
            if (cover != null && cover.width > 0 && cover.height > 0) {
              videoWidth = cover.width.round();
              videoHeight = cover.height.round();
            }
          }
        }
      }
    }
    if (!mounted) {
      return;
    }
    final item = _CsSentItem(
      kind: kind,
      name: name,
      path: path,
      messageType: 0,
      echoId: const Uuid().v4(),
      bytes: bytes,
      localThumbPath: localThumbPath,
      width: videoWidth,
      height: videoHeight,
    );
    setState(() {
      _sentItems.add(item);
      _faqOpen = false;
    });
    _scrollConversationToEnd();
    await _sendPickedAttachment(item);
  }

  void _scrollConversationToEnd() {
    void jumpToLatest() {
      if (!_conversationController.hasClients) {
        return;
      }
      _conversationController.jumpTo(
        _conversationController.position.minScrollExtent,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpToLatest();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        jumpToLatest();
      });
    });
  }

  bool _onConversationScrollNotification(ScrollNotification notification) {
    if (_sentItems.isEmpty || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final metrics = notification.metrics;
    final atTop = metrics.maxScrollExtent > 0 &&
        metrics.pixels >= metrics.maxScrollExtent - 32;
    if (notification is OverscrollNotification &&
        notification.overscroll > 0 &&
        metrics.pixels >= metrics.maxScrollExtent - 1) {
      if (!_faqOpen) {
        setState(() {
          _faqOpen = true;
        });
      }
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      if (atTop) {
        if (!_faqOpen) {
          setState(() {
            _faqOpen = true;
          });
        }
      } else if (_faqOpen && metrics.pixels < metrics.maxScrollExtent - 80) {
        setState(() {
          _faqOpen = false;
        });
      }
    }
    return false;
  }

  Future<void> _openSentItem(_CsSentItem item) async {
    switch (item.kind) {
      case _CsSentKind.text:
      case _CsSentKind.system:
        return;
      case _CsSentKind.image:
        final path = item.path.trim();
        final url = _imageUrl(item);
        if (path.isEmpty &&
            url.isEmpty &&
            (item.bytes == null || item.bytes!.isEmpty)) {
          return;
        }
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => _CsImagePreviewPage(
              path: path,
              url: url,
              bytes: item.bytes,
              name: item.name,
            ),
          ),
        );
      case _CsSentKind.video:
        final source = item.path.trim().isNotEmpty
            ? item.path.trim()
            : KefuVisitorApi.instance.resolveMediaUrl(item.remoteUrl);
        if (source.isEmpty) {
          return;
        }
        await MomentsVideoPlayerPage.push(
          context,
          source: source,
          title: item.name,
          onSave: () {
            unawaited(
              _saveCustomerServiceMedia(
                context,
                video: true,
                name: item.name,
                path: item.path,
                url: item.remoteUrl,
                bytes: item.bytes,
              ),
            );
          },
        );
      case _CsSentKind.file:
        if (item.path.trim().isNotEmpty && !kIsWeb) {
          try {
            final result = await OpenFile.open(item.path);
            if (result.type != ResultType.done && kDebugMode) {
              debugPrint('CUSTOMER_SERVICE open file: ${result.message}');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('CUSTOMER_SERVICE open file: $e');
            }
          }
          return;
        }
        final remote = KefuVisitorApi.instance.resolveMediaUrl(item.remoteUrl);
        if (remote.isEmpty) {
          return;
        }
        final uri = Uri.tryParse(remote);
        if (uri == null) {
          return;
        }
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('CUSTOMER_SERVICE open file url: $e');
          }
        }
    }
  }

  String _nameFromPath(String path, String fallback) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return fallback;
    }
    final normalized = trimmed.replaceAll('\\', '/');
    final parts = normalized.split('/');
    final last = parts.isNotEmpty ? parts.last.trim() : '';
    return last.isNotEmpty ? last : fallback;
  }

  Future<void> _onAttachTap() async {
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (dialogContext) {
        final i18n = AppI18n.of(dialogContext);
        return CupertinoActionSheet(
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: Text(i18n.t(
              zhHans: '取消',
              zhHant: '取消',
              en: 'Cancel',
              ja: 'キャンセル',
              ko: '취소',
            )),
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(dialogContext, 'image'),
              child: Text(
                i18n.t(
                  zhHans: '图片',
                  zhHant: '圖片',
                  en: 'Photo',
                  ja: '写真',
                  ko: '사진',
                ),
                style: TextStyle(color: theme.primaryColor),
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(dialogContext, 'video'),
              child: Text(
                i18n.t(
                  zhHans: '视频',
                  zhHant: '影片',
                  en: 'Video',
                  ja: '動画',
                  ko: '동영상',
                ),
                style: TextStyle(color: theme.primaryColor),
              ),
            ),
          ],
        );
      },
    );
    if (!mounted || result == null || result == 'cancel') {
      return;
    }
    if (result == 'image') {
      await _pickImages();
      return;
    }
    if (result == 'video') {
      await _pickVideos();
    }
  }

  Future<void> _pickImages() async {
    try {
      final allowed = await PermissionGuard.photosForPick(context);
      if (!allowed || !mounted) {
        return;
      }
      final picked = await SystemMediaPicker.pickImages(maxAssets: 9);
      if (!mounted || picked.isEmpty) {
        return;
      }
      for (final media in picked) {
        final name = (media.name?.trim().isNotEmpty ?? false)
            ? media.name!.trim()
            : _nameFromPath(media.path, 'image');
        await _enqueueAttachment(
          kind: _CsSentKind.image,
          name: name,
          path: media.path,
          bytes: media.fileBytes,
        );
        if (!mounted) {
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE pick images: $e');
      }
    }
  }

  Future<void> _pickVideos() async {
    try {
      final allowed = await PermissionGuard.videosForPick(context);
      if (!allowed || !mounted) {
        return;
      }
      final picked = await SystemMediaPicker.pickVideos(maxAssets: 9);
      if (!mounted || picked.isEmpty) {
        return;
      }
      for (final media in picked) {
        final name = (media.name?.trim().isNotEmpty ?? false)
            ? media.name!.trim()
            : _nameFromPath(media.path, 'video');
        await _enqueueAttachment(
          kind: _CsSentKind.video,
          name: name,
          path: media.path,
          bytes: media.fileBytes,
          width: media.width ?? 0,
          height: media.height ?? 0,
        );
        if (!mounted) {
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE pick videos: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final i18n = AppI18n.of(context);
    final contentBg =
        dark ? AppColors.background(dark: true) : _kLightContentBg;
    final inputBarBg = dark ? AppColors.card(dark: true) : Colors.white;

    return ColoredBox(
      color: contentBg,
      child: Column(
        children: [
          ColoredBox(
            color: _kHeaderBlue,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: _buildCategoryGrid(i18n),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: contentBg,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_historyReady) {
                    return const SizedBox.expand();
                  }
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onConversationScrollNotification,
                          child: _buildConversation(
                            i18n: i18n,
                            dark: dark,
                          ),
                        ),
                      ),
                      if (_showFaqPanel)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: ColoredBox(
                            color: contentBg,
                            child: _buildFaqArea(
                              i18n,
                              dark: dark,
                              maxHeight: constraints.maxHeight * 0.42,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          ColoredBox(
            color: inputBarBg,
            child: _buildInputBar(i18n, dark: dark, background: inputBarBg),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(AppI18n i18n) {
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var col = 0; col < 4; col++) ...[
                if (col > 0) const SizedBox(width: 6),
                Expanded(
                  child: _buildCategoryChip(
                    i18n,
                    _kCategoryIds[row * 4 + col],
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryChip(AppI18n i18n, String id) {
    final selected = id == _selectedCategoryId;
    return Material(
      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _onCategoryTap(id),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 32,
          child: Center(
            child: Text(
              _categoryLabel(i18n, id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _kHeaderBlue : Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtopicCard(AppI18n i18n, {required bool dark}) {
    final subtopics =
        _kSubtopicIds[_selectedCategoryId] ?? const <String>[];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: dark ? AppColors.card(dark: true) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        primary: false,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: subtopics.length,
        separatorBuilder: (context, index) {
          return ColoredBox(
            color: AppColors.line(dark: dark),
            child: const SizedBox(height: 1),
          );
        },
        itemBuilder: (context, index) {
          final id = subtopics[index];
          return InkWell(
            onTap: () => _onSubtopicTap(id),
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: _kHeaderBlue,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _subtopicLabel(i18n, id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text(dark: dark),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.subText(dark: dark),
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnswerCard(
    AppI18n i18n, {
    required bool dark,
    required double maxHeight,
  }) {
    final openId = _openSubtopicId;
    if (openId == null) {
      return const SizedBox.shrink();
    }
    final cardMaxHeight = maxHeight - 24;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: cardMaxHeight > 0 ? cardMaxHeight : maxHeight,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark ? AppColors.card(dark: true) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ListView(
              padding: EdgeInsets.zero,
              primary: false,
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _onAnswerBack,
                    child: Tooltip(
                      message: i18n.t(
                        zhHans: '返回',
                        zhHant: '返回',
                        en: 'Back',
                        ja: '戻る',
                        ko: '뒤로',
                      ),
                      child: SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: _kHeaderBlue,
                                size: 16,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _subtopicLabel(i18n, openId),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.text(dark: dark),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ColoredBox(
                  color: AppColors.line(dark: dark),
                  child: const SizedBox(height: 1, width: double.infinity),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _subtopicAnswer(i18n, openId),
                          style: TextStyle(
                            color: AppColors.text(dark: dark),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        if (openId == 'faq_official' &&
                            _officialWebsite.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _openOfficialWebsite,
                            child: Text(
                              _officialWebsite,
                              style: const TextStyle(
                                color: _kHeaderBlue,
                                fontSize: 14,
                                height: 1.5,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFaqArea(
    AppI18n i18n, {
    required bool dark,
    required double maxHeight,
  }) {
    if (_openSubtopicId == null) {
      return _buildSubtopicCard(i18n, dark: dark);
    }
    return _buildAnswerCard(
      i18n,
      dark: dark,
      maxHeight: maxHeight,
    );
  }

  Widget _buildConversation({
    required AppI18n i18n,
    required bool dark,
  }) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _conversationController,
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _sentItems.length,
            itemBuilder: (context, index) {
              final item = _sentItems[_sentItems.length - 1 - index];
              return _buildSentBubble(item, dark: dark);
            },
          ),
        ),
        if (_agentTyping)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                i18n.t(
                  zhHans: '正在输入',
                  zhHant: '正在輸入',
                  en: 'Typing',
                  ja: '入力中',
                  ko: '입력 중',
                ),
                style: TextStyle(
                  color: AppColors.subText(dark: dark),
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSentBubble(_CsSentItem item, {required bool dark}) {
    if (item.kind == _CsSentKind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: Text(
          item.content,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.subText(dark: dark),
            fontSize: 12,
          ),
        ),
      );
    }
    final fromVisitor = item.messageType == 0;
    final Widget body;
    switch (item.kind) {
      case _CsSentKind.system:
        body = const SizedBox.shrink();
      case _CsSentKind.text:
        body = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fromVisitor ? _kHeaderBlue : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(
                item.content,
                style: TextStyle(
                  color: fromVisitor ? Colors.white : AppColors.text(dark: false),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
        );
      case _CsSentKind.image:
        body = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              maxHeight: 360,
            ),
            child: _bubbleImage(item),
          ),
        );
      case _CsSentKind.video:
        body = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _videoBubbleBox(item),
        );
      case _CsSentKind.file:
        body = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    color: _kHeaderBlue,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text(dark: false),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    }
    return Align(
      alignment: fromVisitor ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: fromVisitor
            ? const EdgeInsets.fromLTRB(48, 6, 12, 6)
            : const EdgeInsets.fromLTRB(12, 6, 48, 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openSentItem(item),
              borderRadius: BorderRadius.circular(12),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoBubbleBox(_CsSentItem item) {
    final maxW = MediaQuery.sizeOf(context).width * 0.72;
    const maxH = 360.0;
    final ratio = (item.width > 0 && item.height > 0)
        ? item.width / item.height
        : 16 / 9;
    var width = maxW;
    var height = width / ratio;
    if (height > maxH) {
      height = maxH;
      width = height * ratio;
    }
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: const Color(0xFF1A1A1A),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _videoCover(item),
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoCover(_CsSentItem item) {
    final thumb = KefuVisitorApi.instance.resolveMediaUrl(item.thumbUrl);
    if (thumb.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumb,
        fit: BoxFit.cover,
        placeholder: (_, __) => _localVideoCover(item),
        errorWidget: (_, __, ___) => _localVideoCover(item),
      );
    }
    return _localVideoCover(item);
  }

  Widget _localVideoCover(_CsSentItem item) {
    final local = item.localThumbPath.trim();
    if (!kIsWeb && local.isNotEmpty) {
      return Image.file(
        File(_csLocalFilePath(local)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }

  Future<({int width, int height})?> _probeVideoPixelSize(String path) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(path));
      await controller.initialize().timeout(const Duration(seconds: 4));
      final size = controller.value.size;
      if (size.width > 0 && size.height > 0) {
        return (width: size.width.round(), height: size.height.round());
      }
    } catch (_) {
    } finally {
      await controller?.dispose();
    }
    return null;
  }

  Widget _bubbleImage(_CsSentItem item) {
    final bytes = item.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _imagePlaceholder(broken: true),
      );
    }
    final path = item.path.trim();
    if (!kIsWeb && path.isNotEmpty) {
      return Image.file(
        File(_csLocalFilePath(path)),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          final url = _imageUrl(item);
          if (url.isEmpty) {
            return _imagePlaceholder(broken: true);
          }
          return _networkImage(url);
        },
      );
    }
    final url = _imageUrl(item);
    if (url.isNotEmpty) {
      return _networkImage(url);
    }
    return _imagePlaceholder();
  }

  String _imageUrl(_CsSentItem item) {
    return KefuVisitorApi.instance.resolveMediaUrl(item.remoteUrl);
  }

  Widget _networkImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => _imagePlaceholder(),
      errorWidget: (_, __, ___) => _imagePlaceholder(broken: true),
    );
  }

  Widget _imagePlaceholder({bool broken = false}) {
    return ColoredBox(
      color: const Color(0xFFE0E0E0),
      child: Center(
        child: Icon(
          broken ? Icons.broken_image_outlined : Icons.image_outlined,
        ),
      ),
    );
  }

  Widget _buildInputBar(
    AppI18n i18n, {
    required bool dark,
    required Color background,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _onAttachTap,
              borderRadius: BorderRadius.circular(6),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.add, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _inputController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _onSend(),
                style: TextStyle(
                  color: AppColors.text(dark: dark),
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: i18n.t(
                    zhHans: '请输入您的问题，将会转接人工在线客服',
                    zhHant: '請輸入您的問題，將會轉接人工線上客服',
                    en: 'Type your question to reach a live agent',
                    ja: 'ご質問を入力すると有人サポートにつながります',
                    ko: '질문을 입력하면 상담원에게 연결됩니다',
                  ),
                  hintStyle: TextStyle(
                    color: AppColors.subText(dark: dark),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: AppColors.line(dark: dark)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: AppColors.line(dark: dark)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: _kHeaderBlue,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _onSend,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CsImagePreviewPage extends StatelessWidget {
  const _CsImagePreviewPage({
    this.path = '',
    this.url = '',
    this.bytes,
    this.name = '',
  });

  final String path;
  final String url;
  final List<int>? bytes;
  final String name;

  @override
  Widget build(BuildContext context) {
    Widget image;
    final rawBytes = bytes;
    if (rawBytes != null && rawBytes.isNotEmpty) {
      image = Image.memory(
        Uint8List.fromList(rawBytes),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          return const Icon(
            Icons.broken_image_outlined,
            color: Colors.white,
            size: 64,
          );
        },
      );
    } else if (!kIsWeb && path.trim().isNotEmpty) {
      image = Image.file(
        File(_csLocalFilePath(path)),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          return const Icon(
            Icons.broken_image_outlined,
            color: Colors.white,
            size: 64,
          );
        },
      );
    } else if (KefuVisitorApi.instance.resolveMediaUrl(url).isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: KefuVisitorApi.instance.resolveMediaUrl(url),
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) {
          return const Icon(
            Icons.broken_image_outlined,
            color: Colors.white,
            size: 64,
          );
        },
      );
    } else {
      image = const Icon(
        Icons.image_outlined,
        color: Colors.white,
        size: 64,
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: Colors.white),
            onPressed: () {
              unawaited(
                _saveCustomerServiceMedia(
                  context,
                  video: false,
                  name: name,
                  path: path,
                  url: url,
                  bytes: bytes,
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: image,
        ),
      ),
    );
  }
}

String _csLocalFilePath(String path) {
  if (path.startsWith('file:')) {
    return Uri.parse(path).toFilePath();
  }
  return path;
}

bool _csSaveResultOk(dynamic result) {
  if (result == null) {
    return false;
  }
  if (result is bool) {
    return result;
  }
  if (result is num) {
    return result == 100 || result == 1 || result == 0;
  }
  if (result is String) {
    final value = result.trim().toLowerCase();
    if (value.isEmpty) {
      return false;
    }
    if (value.contains('fail') || value.contains('error')) {
      return false;
    }
    return true;
  }
  if (result is Map) {
    final success = result['isSuccess'] ?? result['success'];
    if (success is bool) {
      return success;
    }
    final code = result['returnCode'] ?? result['resultCode'] ?? result['code'];
    if (code is num) {
      return code == 100 || code == 1 || code == 0;
    }
  }
  return true;
}

String _csSaveExt(String name, {required bool video}) {
  final lower = name.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot >= 0 && dot < lower.length - 1) {
    return lower.substring(dot);
  }
  return video ? '.mp4' : '.jpg';
}

Future<void> _saveCustomerServiceMedia(
  BuildContext context, {
  required bool video,
  required String name,
  required String path,
  required String url,
  List<int>? bytes,
}) async {
  if (kIsWeb) {
    ToastUtils.toast(
      AppI18n.of(context).t(
        zhHans: '当前暂不支持保存',
        zhHant: '目前暫不支援儲存',
        en: 'Saving is not supported here.',
        ja: 'ここでは保存できません。',
        ko: '여기서는 저장할 수 없습니다.',
      ),
    );
    return;
  }
  final granted = video
      ? await PermissionGuard.videosForSave(context)
      : await PermissionGuard.photosForSave(context);
  if (!granted) {
    if (context.mounted) {
      MediaPreviewSaveNotice.show(
        context,
        success: false,
        kind: video ? MediaPreviewSaveKind.video : MediaPreviewSaveKind.image,
      );
    }
    return;
  }
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final safeName = name.trim().isEmpty
      ? (video ? 'cs_video_$stamp' : 'cs_image_$stamp')
      : name.trim();
  var saved = false;
  try {
    final local = path.trim();
    if (local.isNotEmpty) {
      final file = File(_csLocalFilePath(local));
      if (file.existsSync()) {
        if (video) {
          saved = _csSaveResultOk(
            await ImageGallerySaverPlus.saveFile(file.path),
          );
        } else {
          saved = await GallerySaveToPhotos.saveFile(file, name: safeName);
        }
      }
    }
    if (!saved && bytes != null && bytes.isNotEmpty) {
      if (video) {
        final dir = await getTemporaryDirectory();
        final tmp = File('${dir.path}/cs_$stamp${_csSaveExt(safeName, video: true)}');
        await tmp.writeAsBytes(bytes, flush: true);
        saved = _csSaveResultOk(
          await ImageGallerySaverPlus.saveFile(tmp.path),
        );
      } else {
        saved = await GallerySaveToPhotos.saveBytes(
          Uint8List.fromList(bytes),
          name: safeName,
        );
      }
    }
    if (!saved) {
      final remote = KefuVisitorApi.instance.resolveMediaUrl(url);
      if (remote.isNotEmpty) {
        final dio = createAppDio(
          BaseOptions(
            connectTimeout: 30000,
            receiveTimeout: 120000,
            followRedirects: true,
            responseType: ResponseType.bytes,
          ),
        );
        final response = await dio.get<List<int>>(remote);
        final data = response.data;
        if (data != null && data.isNotEmpty) {
          if (video) {
            final dir = await getTemporaryDirectory();
            final tmp = File(
              '${dir.path}/cs_$stamp${_csSaveExt(safeName, video: true)}',
            );
            await tmp.writeAsBytes(data, flush: true);
            saved = _csSaveResultOk(
              await ImageGallerySaverPlus.saveFile(tmp.path),
            );
          } else {
            saved = await GallerySaveToPhotos.saveBytes(
              Uint8List.fromList(data),
              name: safeName,
            );
          }
        }
      }
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('CUSTOMER_SERVICE save media: $e');
    }
    saved = false;
  }
  if (context.mounted) {
    MediaPreviewSaveNotice.show(
      context,
      success: saved,
      kind: video ? MediaPreviewSaveKind.video : MediaPreviewSaveKind.image,
    );
  }
}

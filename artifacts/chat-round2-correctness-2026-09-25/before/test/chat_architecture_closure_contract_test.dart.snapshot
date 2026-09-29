import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('chat architecture closure', () {
    test('app message-list code has no direct projection write', () {
      final result = Process.runSync(
        'rg',
        <String>[
          '-n',
          r'setMessageList\s*\(|messageListMap\s*\[[^\]]+\]\s*=',
          'lib/src',
        ],
      );
      expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
    });

    test('history and search are routed through IM-06 coordinators', () {
      final chatModel = _read(
        'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
        'separate_models/tui_chat_separate_view_model.dart',
      );
      final searchModel = _read(
        'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
        'view_models/tui_search_view_model.dart',
      );
      expect(chatModel, contains('getHistoryMessageListThroughIm06('));
      expect(searchModel, contains('_searchMessagesThroughIm06('));
      expect(
        searchModel,
        isNot(contains('_messageService.searchLocalMessages(')),
      );
      expect(
        searchModel,
        isNot(contains('_messageService.searchCloudMessages(')),
      );
    });

    test('account boundary invalidates writer and clears projections', () {
      final auth = _read('lib/src/services/auth_bootstrap_service.dart');
      final account = _read('lib/src/services/account_session_service.dart');
      expect(auth, contains('invalidateImListenerEpoch();'));
      expect(auth, contains('configureMessageWriterScopeForSession('));
      expect(account, contains('GroupMemberStore.instance.clear('));
      expect(account, contains('serviceLocator<TUIChatGlobalModel>().clearData()'));
    });

    test('group member pickers publish and observe the shared store', () {
      for (final path in <String>[
        'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
            'TIMUIKitTextField/tim_uikit_at_text.dart',
        'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
            'TIMUIKitTextField/tim_uikit_call_invite_list.dart',
      ]) {
        final source = _read(path);
        expect(source, contains('GroupMemberStore.instance.addListener('));
        expect(source, contains('GroupMemberStore.instance.putMembers('));
        expect(source, contains('GroupMemberStore.instance.removeListener('));
      }
    });
  });
}

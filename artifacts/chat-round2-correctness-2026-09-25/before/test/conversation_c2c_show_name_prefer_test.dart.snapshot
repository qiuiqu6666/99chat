import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_c2c_show_name_prefer.dart';

void main() {
  test('store remark wins over incoming nick', () {
    expect(
      ConversationC2cShowNamePrefer.preferC2cShowName(
        existingShowName: '旧备注',
        incomingShowName: '真名',
        storeName: '备注A',
      ),
      '备注A',
    );
  });

  test('existing wins when store empty and incoming differs', () {
    expect(
      ConversationC2cShowNamePrefer.preferC2cShowName(
        existingShowName: '备注B',
        incomingShowName: '真名',
        storeName: '',
      ),
      '备注B',
    );
  });

  test('incoming used when store and existing empty', () {
    expect(
      ConversationC2cShowNamePrefer.preferC2cShowName(
        existingShowName: '',
        incomingShowName: '真名',
        storeName: null,
      ),
      '真名',
    );
  });

  test('preferForConversationIds reads store for c2c', () {
    expect(
      ConversationC2cShowNamePrefer.preferForConversationIds(
        conversationID: 'c2c_u1',
        userID: 'u1',
        existingShowName: '行备注',
        incomingShowName: '真名',
        readStore: (id) => id == 'u1' ? 'Store备注' : null,
      ),
      'Store备注',
    );
  });

  group('preferC2cShowNameOnUpsert', () {
    test('local remark wins when store empty', () {
      expect(
        ConversationC2cShowNamePrefer.preferC2cShowNameOnUpsert(
          existingShowName: '旧名',
          incomingShowName: '真名',
          storeName: '',
          localRemark: '本地备注',
          remarkConfirmedEmpty: false,
        ),
        '本地备注',
      );
    });

    test('existing remark kept over incoming nick when unconfirmed', () {
      expect(
        ConversationC2cShowNamePrefer.preferC2cShowNameOnUpsert(
          existingShowName: '行备注',
          incomingShowName: '真名',
          storeName: null,
          localRemark: '',
          remarkConfirmedEmpty: false,
        ),
        '行备注',
      );
    });

    test('incoming replaces existing when remark confirmed empty', () {
      expect(
        ConversationC2cShowNamePrefer.preferC2cShowNameOnUpsert(
          existingShowName: '旧昵称',
          incomingShowName: '新昵称',
          storeName: null,
          localRemark: null,
          remarkConfirmedEmpty: true,
        ),
        '新昵称',
      );
    });

    test('incoming used when existing empty', () {
      expect(
        ConversationC2cShowNamePrefer.preferC2cShowNameOnUpsert(
          existingShowName: '',
          incomingShowName: '真名',
          storeName: null,
          localRemark: null,
          remarkConfirmedEmpty: false,
        ),
        '真名',
      );
    });
  });

  group('captureNameForStore', () {
    test('local remark wins', () {
      expect(
        ConversationC2cShowNamePrefer.captureNameForStore(
          showName: '真名',
          localRemark: '本地备注',
          localNickname: '真名',
          remarkConfirmedEmpty: false,
        ),
        '本地备注',
      );
    });

    test('nick-equal showName skipped when remark unconfirmed', () {
      expect(
        ConversationC2cShowNamePrefer.captureNameForStore(
          showName: '真名',
          localRemark: '',
          localNickname: '真名',
          remarkConfirmedEmpty: false,
        ),
        isNull,
      );
    });

    test('nick-equal showName written when remark confirmed empty', () {
      expect(
        ConversationC2cShowNamePrefer.captureNameForStore(
          showName: '真名',
          localRemark: '',
          localNickname: '真名',
          remarkConfirmedEmpty: true,
        ),
        '真名',
      );
    });

    test('showName differing from nick is written', () {
      expect(
        ConversationC2cShowNamePrefer.captureNameForStore(
          showName: '会话备注',
          localRemark: null,
          localNickname: '真名',
          remarkConfirmedEmpty: false,
        ),
        '会话备注',
      );
    });
  });
}

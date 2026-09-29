import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('C2C friend avatar fallback resolves from a list source', () {
    final friends = <V2TimFriendInfo>[
      V2TimFriendInfo(
        userID: 'face_user_1',
        userProfile: V2TimUserFullInfo(
          userID: 'face_user_1',
          faceUrl: 'https://example.com/face-user-1.png',
        ),
      ),
    ];

    expect(
      ConversationFaceUrl.resolve(
        userId: 'face_user_1',
        conversationFaceUrl: '',
        friendList: friends,
      ),
      'https://example.com/face-user-1.png',
    );
  });

  test('non-list friend sources retain the avatar fallback behavior', () {
    final friends = <V2TimFriendInfo>[
      V2TimFriendInfo(
        userID: 'face_user_2',
        userProfile: V2TimUserFullInfo(
          userID: 'face_user_2',
          faceUrl: 'https://example.com/face-user-2.png',
        ),
      ),
    ].where((_) => true);

    expect(
      ConversationFaceUrl.resolve(
        userId: 'face_user_2',
        conversationFaceUrl: '',
        friendList: friends,
      ),
      'https://example.com/face-user-2.png',
    );
  });
}

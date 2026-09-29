import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_utils.dart';

String imageKey({String? sdkId, String client = 'local-1'}) =>
    chatBubbleImageWidgetKey(
      kind: 'local',
      outgoingStableId: client,
      msgID: sdkId,
      idFallback: sdkId == null ? client : 'sdk-created-id',
      urlOrPathFallback: sdkId == null ? '/picked.png' : '/compressed.png',
    );

void main() {
  test('SDK identity and compression preserve outgoing image identity', () {
    expect(imageKey(sdkId: 'server-1'), imageKey());
    expect(imageKey(client: 'local-2'), isNot(imageKey()));
    expect(
      chatBubbleImageWidgetKey(kind: 'net', msgID: 'received'),
      'chat_img_bubble_received',
    );
  });

  testWidgets('SDK adoption keeps the mounted image and outer subtree',
      (tester) async {
    Widget bubble(String? sdkId) {
      final key = imageKey(sdkId: sdkId);
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          key: ValueKey('visibility:$key'),
          child: Image(
            key: ValueKey(key),
            image: const AssetImage('missing-test-image'),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
        ),
      );
    }

    await tester.pumpWidget(bubble(null));
    final imageElement = tester.element(find.byType(Image));
    final imageState = tester.state(find.byType(Image));
    await tester.pumpWidget(bubble('server-1'));
    expect(tester.element(find.byType(Image)), same(imageElement));
    expect(tester.state(find.byType(Image)), same(imageState));
    await tester.pumpWidget(const SizedBox());
  });
}

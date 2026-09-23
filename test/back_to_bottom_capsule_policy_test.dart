import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/back_to_bottom_capsule_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/true_latest_end.dart';

void main() {
  test('geometry epsilon is 2px, not a product bottom threshold', () {
    expect(TrueLatestEnd.geometryEpsilon, 2.0);
    expect(BackToBottomCapsulePolicy.geometryEpsilon, 2.0);
    expect(BackToBottomCapsulePolicy.followExitThresholdPx, 24.0);
    expect(BackToBottomCapsulePolicy.capsuleShowViewportRatio, 0.5);
    expect(BackToBottomCapsulePolicy.isPhysicallyAtBottom(2), isTrue);
    expect(BackToBottomCapsulePolicy.isPhysicallyAtBottom(2.1), isFalse);
  });

  test('hides at true latest end even if leave latch is stale', () {
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: true,
        hasMissingNewer: false,
        distanceFromLatestEdge: 800,
        viewportDimension: 800,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isFalse,
    );
  });

  test('shows unseen arrivals within the follow-exit band', () {
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: false,
        distanceFromLatestEdge: 12,
        viewportDimension: 800,
        liveUnreadCount: 3,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isTrue,
    );
  });

  test('shows unseen arrivals before the half-viewport threshold', () {
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: false,
        distanceFromLatestEdge: 100,
        viewportDimension: 800,
        liveUnreadCount: 3,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isTrue,
    );
  });

  test('shows at half viewport with N still 3', () {
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: false,
        distanceFromLatestEdge: 400,
        viewportDimension: 800,
        liveUnreadCount: 3,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isTrue,
    );
  });

  test('keeps the capsule at list end when newer pages are missing', () {
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: true,
        distanceFromLatestEdge: 0,
        viewportDimension: 800,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isTrue,
    );
  });

  test('locks hide the capsule during inbound pin or return-to-bottom', () {
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: false,
        distanceFromLatestEdge: 400,
        viewportDimension: 800,
        presentationBottomLocked: true,
        programmaticScrollToBottom: false,
      ),
      isFalse,
    );
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: true,
        distanceFromLatestEdge: 0,
        viewportDimension: 800,
        presentationBottomLocked: false,
        programmaticScrollToBottom: true,
      ),
      isFalse,
    );
  });
}

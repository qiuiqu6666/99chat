import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/profile.dart';

void main() {
  test('empty capture still applies when current owner matches /me', () {
    expect(
      shouldApplySelfMeResult(
        capturedOwner: '',
        currentOwner: 'a',
        meUserId: 'a',
      ),
      isTrue,
    );
  });

  test('matching capture, current owner and /me applies', () {
    expect(
      shouldApplySelfMeResult(
        capturedOwner: 'a',
        currentOwner: 'a',
        meUserId: 'a',
      ),
      isTrue,
    );
  });

  test('stale capture for previous owner is discarded after switch', () {
    expect(
      shouldApplySelfMeResult(
        capturedOwner: 'a',
        currentOwner: 'b',
        meUserId: 'a',
      ),
      isFalse,
    );
  });

  test('current owner mismatch with /me is discarded', () {
    expect(
      shouldApplySelfMeResult(
        capturedOwner: '',
        currentOwner: 'b',
        meUserId: 'a',
      ),
      isFalse,
    );
  });

  test('empty /me user id never applies', () {
    expect(
      shouldApplySelfMeResult(
        capturedOwner: 'a',
        currentOwner: 'a',
        meUserId: '',
      ),
      isFalse,
    );
  });
}

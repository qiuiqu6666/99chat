import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_initial_window_reveal_policy.dart';

void main() {
  bool ready({bool complete = false, bool painted = false,
      bool positioned = false, bool messages = false}) =>
      ChatInitialWindowRevealPolicy.canReveal(
        alreadyPainted: painted,
        explicitPosition: positioned,
        completeWindow: complete,
        hasMessages: messages,
      );

  test('a single local message reveals while history continues loading', () {
    expect(ready(messages: true), isTrue);
    expect(ready(complete: true, messages: true), isTrue);
  });
  test('warm complete and confirmed short histories reveal immediately', () {
    expect(ready(complete: true), isTrue);
  });
  test('empty bootstrap waits for data or confirmed empty history', () {
    expect(ready(), isFalse);
    expect(ready(complete: true), isTrue);
  });
  test('search and already visible history are never hidden again', () {
    expect(ready(positioned: true), isTrue);
    expect(ready(painted: true), isTrue);
  });
}

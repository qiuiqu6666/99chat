import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/utils/sangong_operator_names.dart';

void main() {
  test('deduplicates IM IDs and excludes ambiguous admin IDs and labels',
      () async {
    final result = await resolveSangongOperatorNames(
      [' afsqdw797d ', 'afsqdw797d', '88', '张三(88)', ''],
      (ids) async {
        expect(ids, ['afsqdw797d']);
        return {'afsqdw797d': '张三'};
      },
    );
    expect(result, {'afsqdw797d': '张三'});
  });
  test('batches lookups and tolerates failure', () async {
    var calls = 0;
    final result = await resolveSangongOperatorNames(
      List.generate(205, (i) => 'user$i'),
      (ids) async {
        expect(ids.length, lessThanOrEqualTo(100));
        calls++;
        if (calls == 2) throw StateError('offline');
        return {for (final id in ids) id: '昵称$id'};
      },
    );
    expect(calls, 3);
    expect(result.length, 105);
  });
  test('does not fetch after the page becomes inactive', () async {
    final result = await resolveSangongOperatorNames(['user1'], (_) async {
      fail('unexpected lookup');
    }, isActive: () => false);
    expect(result, isEmpty);
  });
}

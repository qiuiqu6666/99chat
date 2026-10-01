import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_member_detail_page.dart';
import 'sangong_transfers_entry_test.dart' show mockPages;

void main() {
  testWidgets('member cards and labels follow live theme changes',
      (tester) async {
    mockPages();
    final member = SangongTeamMemberDto.fromJson(
        {'imUserId': 'other', 'nickname': '主题测试', 'balance': 36});
    for (final brightness in [
      Brightness.light,
      Brightness.dark,
      Brightness.light
    ]) {
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: SangongAgentMemberDetailPage(member: member),
      ));
      await tester.pumpAndSettle();
      final card = tester.widget<Card>(find.byType(Card).first);
      expect(card.color, theme.colorScheme.surface);
      final label = tester.widget<Text>(find.text('余额'));
      expect(label.style!.color, theme.colorScheme.onSurfaceVariant);
      final value = tester.element(find.text('36'));
      final textColor = DefaultTextStyle.of(value).style.color!;
      final a = textColor.computeLuminance();
      final b = card.color!.computeLuminance();
      expect(((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
          greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    }
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_member_loader.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_member_picker_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_member.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

class _Theme extends ChangeNotifier implements DefaultThemeData {
  @override
  TUITheme get theme => DefTheme.getTheme(ThemeType.blue);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('open picker receives later pages and search finds new members',
      (tester) async {
    final next = Completer<GroupLiveMemberPage>();
    await tester.pumpWidget(ChangeNotifierProvider<DefaultThemeData>(
      create: (_) => _Theme(),
      child:
          MaterialApp(home: GroupLiveMemberPickerPage(loadPage: (cursor) async {
        if (cursor == '0') {
          return const GroupLiveMemberPage([
            RedPacketMember(userId: '1', name: 'First member'),
          ], 'next');
        }
        return next.future;
      })),
    ));
    await tester.pump();
    expect(find.text('First member'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Later');
    next.complete(const GroupLiveMemberPage([
      RedPacketMember(userId: '2', name: 'Later anchor'),
    ], '0'));
    await tester.pumpAndSettle();
    expect(find.text('Later anchor'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(find.text('First member'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('failed load shows retry and recovers in the same picker',
      (tester) async {
    var fail = true;
    await tester.pumpWidget(ChangeNotifierProvider<DefaultThemeData>(
      create: (_) => _Theme(),
      child: MaterialApp(home: GroupLiveMemberPickerPage(loadPage: (_) async {
        if (fail) throw StateError('offline');
        return const GroupLiveMemberPage([
          RedPacketMember(userId: '1', name: 'Recovered anchor'),
        ], '0');
      })),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Member list incomplete. Tap to retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('Recovered anchor'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });
}

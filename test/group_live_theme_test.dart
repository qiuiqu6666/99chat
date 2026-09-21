import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_online_live_scaffold.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_top_banner.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';

const _pushUrl = 'rtmp://stream.example.test/live/theme-regression';

// Implements the provider contract without constructing the SDK-backed provider.
class _LiveThemePreference extends ChangeNotifier implements DefaultThemeData {
  ThemeType _current = ThemeType.blue;

  @override
  ThemeType get currentThemeType => _current;

  @override
  ThemeMode get materialThemeMode =>
      _current == ThemeType.dark ? ThemeMode.dark : ThemeMode.light;

  @override
  set currentThemeType(ThemeType value) {
    _current = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GroupLiveThemeHarness extends StatelessWidget {
  const _GroupLiveThemeHarness(
      {required this.controller, required this.onCopy});

  final TextEditingController controller;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return GroupLiveOnlineLiveScaffold(
      body: Column(
        children: [
          const GroupLiveOnlineLiveHeader(),
          const GroupLiveScheduleHeader(),
          GroupLiveFormSection(
            title: 'Streaming configuration',
            children: [
              GroupLiveRoomNameField(
                controller: controller,
                enabled: true,
                hintText: 'Choose a room name',
              ),
              GroupLiveScheduleField(
                key: const ValueKey('schedule-value'),
                label: 'Start time',
                value: '2026-09-16 10:00',
                trailing: GroupLiveFieldTrailing.calendar,
                onTap: () {},
              ),
              GroupLiveScheduleField(
                key: const ValueKey('schedule-placeholder'),
                label: 'Destination',
                value: '',
                placeholder: 'Choose a group',
                onTap: () {},
              ),
              GroupLiveCopyField(
                key: const ValueKey('populated-copy'),
                label: 'Streaming URL',
                value: _pushUrl,
                onCopy: onCopy,
              ),
              GroupLiveCopyField(
                key: const ValueKey('empty-copy'),
                label: 'Unavailable URL',
                value: '',
                onCopy: onCopy,
              ),
              const GroupLivePushQrField(value: _pushUrl),
            ],
          ),
          const GroupLiveSettingsCard(
            title: 'Room permissions',
            children: [GroupLivePointsUsageSection()],
          ),
        ],
      ),
    );
  }
}

Color _textColor(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text)).style!.color!;
}

BoxDecoration _firstBox(WidgetTester tester, Finder parent) {
  return tester
      .widgetList<Container>(
        find.descendant(of: parent, matching: find.byType(Container)),
      )
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .first;
}

List<Color> _ancestorBoxColors(WidgetTester tester, String text) {
  return tester
      .widgetList<Container>(
        find.ancestor(of: find.text(text), matching: find.byType(Container)),
      )
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.color)
      .whereType<Color>()
      .toList();
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
}

void _expectLiveFormColors(WidgetTester tester, {required bool dark}) {
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
  final appBar = tester.widget<AppBar>(find.byType(AppBar));
  final page = scaffold.backgroundColor!;
  final card = _firstBox(tester, find.byType(GroupLiveFormCard));
  final settings = _firstBox(tester, find.byType(GroupLiveSettingsCard));
  final roomName = tester.widget<TextField>(find.byType(TextField));
  final field = roomName.decoration!.fillColor!;

  expect(page, dark ? AppTokens.backgroundDark : const Color(0xFFF3F4F6));
  expect(appBar.backgroundColor, page);
  expect(card.color, dark ? AppTokens.surfaceDark : Colors.white);
  expect(settings.color, card.color);
  expect(field, dark ? AppTokens.surfaceAltDark : AppTokens.fieldFill);
  expect(
    card.boxShadow!.single.color.a,
    dark ? greaterThan(0.04) : closeTo(0.04, 0.005),
  );

  // The status bar must stay readable even when MaterialApp is still light.
  expect(
    appBar.systemOverlayStyle!.statusBarIconBrightness,
    dark ? Brightness.light : Brightness.dark,
  );
  expect(
    appBar.systemOverlayStyle!.statusBarBrightness,
    dark ? Brightness.dark : Brightness.light,
  );

  for (final text in [
    'Live room setup',
    'Streaming configuration',
    'Room permissions',
    'Points usage',
  ]) {
    final color = _textColor(tester, text);
    if (dark) expect(color, AppTokens.textPrimaryDark);
    expect(_contrast(color, page), greaterThan(7), reason: text);
  }
  for (final text in [
    'Live room name',
    'Start time',
    'Streaming URL',
    'Scan this QR code in Xinxian to fill the streaming URL.',
  ]) {
    final color = _textColor(tester, text);
    if (dark) expect(color, AppTokens.textSecondaryDark);
    expect(_contrast(color, page), greaterThan(dark ? 4.5 : 3), reason: text);
  }
  expect(_contrast(roomName.style!.color!, field), greaterThan(7));
  expect(
      _contrast(roomName.decoration!.hintStyle!.color!, field), greaterThan(3));
  expect(_contrast(_textColor(tester, _pushUrl), field), greaterThan(7));
  expect(
    _contrast(_textColor(tester, 'Choose a group'), field),
    greaterThan(3),
  );

  for (final key in ['schedule-value', 'schedule-placeholder']) {
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, field);
  }
  for (final key in ['populated-copy', 'empty-copy']) {
    expect(_firstBox(tester, find.byKey(ValueKey(key))).color, field);
  }
  expect(_firstBox(tester, find.byType(GroupLivePushQrField)).color, field);

  final activeCopy = tester.widget<Icon>(
    find.descendant(
      of: find.byKey(const ValueKey('populated-copy')),
      matching: find.byIcon(Icons.copy_rounded),
    ),
  );
  final disabledCopy = tester.widget<Icon>(
    find.descendant(
      of: find.byKey(const ValueKey('empty-copy')),
      matching: find.byIcon(Icons.copy_rounded),
    ),
  );
  expect(activeCopy.color, isNot(disabledCopy.color));
  expect(_contrast(activeCopy.color!, field), greaterThan(3));
  for (final icon in [Icons.calendar_today_outlined, Icons.chevron_right]) {
    expect(
      _contrast(tester.widget<Icon>(find.byIcon(icon)).color!, field),
      greaterThan(3),
    );
  }

  // QR modules deliberately keep a white quiet zone and black data in both modes.
  final qr = tester.widget<QrImageView>(find.byType(QrImageView));
  expect(qr.backgroundColor, Colors.white);
  expect(qr.eyeStyle.color, Colors.black);
  expect(qr.dataModuleStyle.color, Colors.black);
  expect(qr.padding, const EdgeInsets.all(10));
}

void main() {
  testWidgets('live form follows app preference light-dark-light in place',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preference = _LiveThemePreference();
    final controller = TextEditingController(text: 'Test broadcast');
    addTearDown(preference.dispose);
    addTearDown(controller.dispose);
    var copyCount = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<DefaultThemeData>.value(
        value: preference,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: _GroupLiveThemeHarness(
            controller: controller,
            onCopy: () => copyCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final originalField = tester.element(find.byType(GroupLiveRoomNameField));
    final originalScaffold = tester.element(find.byType(Scaffold));

    for (final type in [ThemeType.blue, ThemeType.dark, ThemeType.blue]) {
      preference.currentThemeType = type;
      await tester.pumpAndSettle();
      _expectLiveFormColors(tester, dark: type == ThemeType.dark);
      expect(tester.element(find.byType(Scaffold)), same(originalScaffold));
      expect(
        tester.element(find.byType(GroupLiveRoomNameField)),
        same(originalField),
      );
      expect(controller.text, 'Test broadcast');
      expect(Theme.of(originalScaffold).brightness, Brightness.light);
      expect(tester.takeException(), isNull);
    }

    final enabledCopy = find.descendant(
      of: find.byKey(const ValueKey('populated-copy')),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(enabledCopy);
    await tester.tap(enabledCopy);
    expect(copyCount, 1);
    final emptyCopy = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('empty-copy')),
        matching: find.byType(InkWell),
      ),
    );
    expect(emptyCopy.onTap, isNull);
  });

  testWidgets('live shell falls back to Material brightness without provider',
      (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, value, child) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: value,
          home: child,
        ),
        child: const GroupLiveOnlineLiveScaffold(
          body: GroupLiveOnlineLiveHeader(),
        ),
      ),
    );
    for (final value in [ThemeMode.light, ThemeMode.dark, ThemeMode.light]) {
      mode.value = value;
      await tester.pumpAndSettle();
      final dark = value == ThemeMode.dark;
      final page = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        page.backgroundColor,
        dark ? AppTokens.backgroundDark : const Color(0xFFF3F4F6),
      );
      expect(find.byType(GroupLiveOnlineLiveHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('open OBS guide updates surfaces and text with app preference',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preference = _LiveThemePreference();
    addTearDown(preference.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<DefaultThemeData>.value(
        value: preference,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGroupLiveObsGuideSheet(context),
                child: const Text('Open streaming guide'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open streaming guide'));
    await tester.pumpAndSettle();
    expect(find.text('Xinxian setup'), findsOneWidget);
    final originalTitle = tester.element(find.text('Xinxian setup'));

    for (final type in [ThemeType.blue, ThemeType.dark, ThemeType.blue]) {
      preference.currentThemeType = type;
      await tester.pumpAndSettle();
      final dark = type == ThemeType.dark;
      final page = dark ? AppTokens.backgroundDark : const Color(0xFFF3F4F6);
      final card = dark ? AppTokens.surfaceDark : Colors.white;
      expect(_ancestorBoxColors(tester, 'Xinxian setup'), contains(page));
      expect(
        _ancestorBoxColors(tester, 'Download Xinxian'),
        containsAll([page, card]),
      );
      for (final title in [
        'Xinxian setup',
        'Download Xinxian',
        'Paste the full streaming URL',
        'Recommended settings',
        'Start and stop',
      ]) {
        final color = _textColor(tester, title);
        if (dark) expect(color, AppTokens.textPrimaryDark);
        expect(_contrast(color, card), greaterThan(7), reason: title);
      }
      final subtitle = _textColor(
        tester,
        'Use Xinxian on phone. Four steps to go live.',
      );
      if (dark) expect(subtitle, AppTokens.textSecondaryDark);
      expect(_contrast(subtitle, page), greaterThan(dark ? 4.5 : 3));
      for (var step = 1; step <= 4; step++) {
        expect(_textColor(tester, '$step'), Colors.white);
      }
      expect(tester.element(find.text('Xinxian setup')), same(originalTitle));
      expect(tester.takeException(), isNull);
    }

    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Xinxian setup'), findsNothing);
  });

  testWidgets('chat live banner and enter button follow app theme in place',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preference = _LiveThemePreference();
    addTearDown(preference.dispose);
    var enterCount = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<DefaultThemeData>.value(
        value: preference,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: GroupLiveTopBanner(
              session: const GroupLiveSession(
                liveSessionId: 'theme-regression-live',
                roomName: '直播发包中',
                // Empty identities prevent member lookup and avatar fetching.
                groupId: '',
                anchorUserId: '',
                status: GroupLiveStatus.live,
              ),
              onTap: () => enterCount++,
            ),
          ),
        ),
      ),
    );
    final bannerFinder = find.byType(GroupLiveTopBanner);
    final originalBanner = tester.element(bannerFinder);

    for (final type in [ThemeType.blue, ThemeType.dark, ThemeType.blue]) {
      preference.currentThemeType = type;
      await tester.pump(const Duration(milliseconds: 32));
      final dark = type == ThemeType.dark;
      final bannerSurface = tester.widget<Material>(
        find.descendant(of: bannerFinder, matching: find.byType(Material)),
      );
      expect(
        bannerSurface.color,
        dark ? AppTokens.surfaceAltDark : Colors.white,
      );
      const titleLabel = '直播发包中';
      final titleColor = _textColor(tester, titleLabel);
      expect(
        titleColor,
        dark ? AppTokens.textPrimaryDark : const Color(0xFF1F2329),
      );
      expect(_contrast(titleColor, bannerSurface.color!), greaterThan(7));

      const actionLabel = 'Enter room';
      final buttonBox = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text(actionLabel),
              matching: find.byType(Container),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(buttonBox.gradient, isNotNull);
      final actionColor = _textColor(tester, actionLabel);
      expect(actionColor, Colors.white);
      expect(tester.element(bannerFinder), same(originalBanner));
      expect(Theme.of(originalBanner).brightness, Brightness.light);

      await tester.tap(find.text(actionLabel));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    }
    expect(enterCount, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live room name field maxLength is 10', (tester) async {
    final preference = _LiveThemePreference();
    final controller = TextEditingController();
    addTearDown(preference.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<DefaultThemeData>.value(
        value: preference,
        child: MaterialApp(
          home: _GroupLiveThemeHarness(
            controller: controller,
            onCopy: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(GroupLiveRoomNameField),
        matching: find.byType(TextField),
      ),
    );
    expect(GroupLiveRoomNameField.maxLength, 10);
    expect(field.maxLength, GroupLiveRoomNameField.maxLength);
  });
}

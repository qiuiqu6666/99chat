import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String loginSource;
  late String loginPageBuild;
  late String formPage;

  setUpAll(() {
    loginSource = File('lib/src/pages/login.dart').readAsStringSync();
    final loginPageAt =
        loginSource.indexOf('class LoginPage extends StatelessWidget');
    final loginBodyAt =
        loginSource.indexOf('class _LoginBody extends StatefulWidget');
    expect(loginPageAt, greaterThanOrEqualTo(0));
    expect(loginBodyAt, greaterThan(loginPageAt));
    loginPageBuild = loginSource.substring(loginPageAt, loginBodyAt);

    final formAt = loginSource.indexOf('Widget _buildFormPage(Widget child)');
    final nextAt = loginSource.indexOf('Widget _buildVersionText()', formAt);
    expect(formAt, greaterThanOrEqualTo(0));
    expect(nextAt, greaterThan(formAt));
    formPage = loginSource.substring(formAt, nextAt);
  });

  test('LoginPage.build uses NativeDesktopSelectableMessageText on isNativeDesktop',
      () {
    expect(
      loginSource.contains(
        'package:tencent_cloud_chat_uikit/ui/utils/native_desktop_text_selection.dart',
      ),
      isTrue,
    );
    expect(loginPageBuild.contains('PlatformUtils().isNativeDesktop'), isTrue);
    expect(
      loginPageBuild.contains('NativeDesktopSelectableMessageText('),
      isTrue,
    );
    expect(loginPageBuild.contains('GestureDetector('), isTrue);
    expect(
      loginPageBuild.contains('onTap: () => FocusScope.of(context).unfocus()'),
      isTrue,
    );

    final nativeAt = loginPageBuild.indexOf('PlatformUtils().isNativeDesktop');
    final selectableAt =
        loginPageBuild.indexOf('NativeDesktopSelectableMessageText(');
    final gestureAt = loginPageBuild.indexOf('GestureDetector(');
    expect(nativeAt, greaterThanOrEqualTo(0));
    expect(selectableAt, greaterThan(nativeAt));
    expect(gestureAt, greaterThan(selectableAt));
  });

  test('_buildFormPage excludes mouse from dragDevices on isNativeDesktop', () {
    expect(loginSource.contains('package:flutter/gestures.dart'), isTrue);
    expect(formPage.contains('if (PlatformUtils().isNativeDesktop)'), isTrue);
    expect(formPage.contains('ScrollConfiguration'), isTrue);
    expect(formPage.contains('PointerDeviceKind.mouse'), isTrue);
    expect(
      formPage.contains('parent: AlwaysScrollableScrollPhysics()'),
      isTrue,
    );
    expect(
      formPage.contains(
        'keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag',
      ),
      isTrue,
    );
  });
}

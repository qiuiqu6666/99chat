import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/platform_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/app_update_service.dart';

PlatformContactInfo _info({
  String updateType = 'OPTIONAL',
  String? minVersion,
  int? minVersionCode,
  String version = '2.0.0',
  String build = '1',
}) {
  return PlatformContactInfo.fromJson(<String, dynamic>{
    'website': 'https://99chat.vip/',
    'email': 'admin@99chat.chat',
    'version': version,
    'build': build,
    'downloadUrl': 'https://down.99chat.vip',
    'platform': 'android',
    'updateType': updateType,
    'minVersion': minVersion,
    'minVersionCode': minVersionCode,
  });
}

void main() {
  group('Android APK 地址选择', () {
    test('优先使用独立 APK 下载地址，保留网页链接', () {
      final info = PlatformContactInfo.fromJson({
        'downloadUrl': 'https://down.99chat.vip',
        'apkUrl': 'https://cdn.example.com/app?id=21',
      });
      expect(AppUpdateService.resolveAndroidApkUrl(info),
          'https://cdn.example.com/app?id=21');
      expect(info.downloadUrl, 'https://down.99chat.vip');
    });
    test('旧接口 APK 直链可自动下载，带查询参数仍识别', () {
      final info = PlatformContactInfo.fromJson({
        'downloadUrl': 'https://cdn.example.com/app.APK?token=abc',
      });
      expect(AppUpdateService.resolveAndroidApkUrl(info), info.downloadUrl);
    });
    test('旧官方网盘网页改为已验证的 APK 地址并隔离 CDN 缓存', () {
      final info = _info(version: '3.0.1', build: '20');
      final uri = Uri.parse(AppUpdateService.resolveAndroidApkUrl(info)!);
      expect(uri.host, 'image.99chat.vip');
      expect(uri.path, '/app-release.apk');
      expect(uri.queryParameters, {'version': '3.0.1', 'build': '20'});
    });
    test('当前后台的旧版本信息仍可让安卓 19 检测到已发布的 20', () {
      final info = PlatformContactInfo.fromJson({
        'version': '1.0.0',
        'build': '1',
        'updateType': 'OPTIONAL',
        'downloadUrl': 'https://99chat.com/download',
      });
      final release = AppUpdateService.resolveBundledAndroidRelease(
          info: info, currentVersion: '3.0.1', currentBuildNumber: 19);
      expect(release?.version, '3.0.1');
      expect(release?.build, 20);
      expect(Uri.parse(release!.url).host, 'image.99chat.vip');
    });
    test('已升级到 20 或后台关闭更新时不再下载', () {
      final info = PlatformContactInfo.fromJson({
        'version': '1.0.0',
        'build': '1',
        'updateType': 'OPTIONAL',
      });
      expect(
          AppUpdateService.resolveBundledAndroidRelease(
              info: info, currentVersion: '3.0.1', currentBuildNumber: 20),
          isNull);
      final disabled = PlatformContactInfo.fromJson({
        'version': '1.0.0',
        'build': '1',
        'updateType': 'NONE',
      });
      expect(
          AppUpdateService.resolveBundledAndroidRelease(
              info: disabled, currentVersion: '3.0.1', currentBuildNumber: 19),
          isNull);
    });
    test('后台真正发布更高版本时不被内置 20 号包覆盖', () {
      final info = PlatformContactInfo.fromJson({
        'version': '3.0.2',
        'build': '21',
        'updateType': 'OPTIONAL',
        'downloadUrl': 'https://99chat.com/download',
      });
      expect(
          AppUpdateService.resolveBundledAndroidRelease(
              info: info, currentVersion: '3.0.1', currentBuildNumber: 19),
          isNull);
      expect(AppUpdateService.resolveAndroidApkUrl(info), isNull);
    });
    test('旧版外链只对版本吻合的 20 号包切换为内部下载', () {
      final currentRelease = PlatformContactInfo.fromJson({
        'version': '3.0.1',
        'build': '20',
        'downloadUrl': 'https://99chat.com/download',
      });
      expect(
          Uri.parse(AppUpdateService.resolveAndroidApkUrl(currentRelease)!)
              .host,
          'image.99chat.vip');
    });
    test('其他网页和不合法地址继续走旧版更新流程', () {
      for (final url in [
        'https://example.com/download',
        'file:///tmp/app.apk',
        'https://user:password@example.com/app.apk'
      ]) {
        final info = PlatformContactInfo.fromJson({'downloadUrl': url});
        expect(AppUpdateService.resolveAndroidApkUrl(info), isNull);
      }
    });
  });
  group('UpdatePolicy 枚举解析', () {
    test('updateType=FORCE → UpdatePolicy.force', () {
      expect(_info(updateType: 'FORCE').updatePolicy, UpdatePolicy.force);
    });
    test('updateType=force → UpdatePolicy.force（大小写不敏感）', () {
      expect(_info(updateType: 'force').updatePolicy, UpdatePolicy.force);
    });
    test('updateType=OPTIONAL → UpdatePolicy.optional', () {
      expect(_info(updateType: 'OPTIONAL').updatePolicy, UpdatePolicy.optional);
    });
    test('updateType=GRAY → UpdatePolicy.gray', () {
      expect(_info(updateType: 'GRAY').updatePolicy, UpdatePolicy.gray);
    });
    test('updateType=NONE → UpdatePolicy.none', () {
      expect(_info(updateType: 'NONE').updatePolicy, UpdatePolicy.none);
    });
    test('缺失字段 → UpdatePolicy.optional（默认）', () {
      expect(_info().updatePolicy, UpdatePolicy.optional);
    });
    test('未知值 → UpdatePolicy.optional（容错）', () {
      expect(_info(updateType: 'random').updatePolicy, UpdatePolicy.optional);
    });
  });

  group('UpdatePolicyX 扩展属性', () {
    test('shouldPrompt: none → false，其他 → true', () {
      expect(UpdatePolicy.none.shouldPrompt, isFalse);
      expect(UpdatePolicy.optional.shouldPrompt, isTrue);
      expect(UpdatePolicy.force.shouldPrompt, isTrue);
      expect(UpdatePolicy.gray.shouldPrompt, isTrue);
    });
    test('isMandatory: force / gray → true；optional / none → false', () {
      expect(UpdatePolicy.force.isMandatory, isTrue);
      expect(UpdatePolicy.gray.isMandatory, isTrue);
      expect(UpdatePolicy.optional.isMandatory, isFalse);
      expect(UpdatePolicy.none.isMandatory, isFalse);
    });
    test('showCloseButton: optional → true，其他 → false', () {
      expect(UpdatePolicy.optional.showCloseButton, isTrue);
      expect(UpdatePolicy.force.showCloseButton, isFalse);
      expect(UpdatePolicy.gray.showCloseButton, isFalse);
      expect(UpdatePolicy.none.showCloseButton, isFalse);
    });
  });

  group('AppUpdateService.evaluateUpdatePolicy', () {
    final s = AppUpdateService.instance;

    test('updateType=NONE → noPrompt（即使有新版也不弹）', () {
      final d = s.evaluateUpdatePolicy(
        info: _info(updateType: 'NONE', minVersionCode: 999),
        currentVersion: '1.0.0',
        currentBuildNumber: 1,
      );
      expect(d, UpdateOutcome.noPrompt);
    });

    test('updateType=OPTIONAL + 任意版本 → optional（可关闭）', () {
      final d = s.evaluateUpdatePolicy(
        info: _info(updateType: 'OPTIONAL'),
        currentVersion: '1.0.0',
        currentBuildNumber: 1,
      );
      expect(d, UpdateOutcome.optional);
    });

    test('updateType=FORCE + minVersionCode 大于当前 → mandatory', () {
      final d = s.evaluateUpdatePolicy(
        info: _info(updateType: 'FORCE', minVersionCode: 20),
        currentVersion: '1.0.0',
        currentBuildNumber: 10,
      );
      expect(d, UpdateOutcome.mandatory);
    });

    test('updateType=FORCE + minVersionCode 不大于当前 → optional', () {
      final d = s.evaluateUpdatePolicy(
        info: _info(updateType: 'FORCE', minVersionCode: 20),
        currentVersion: '2.0.0',
        currentBuildNumber: 30,
      );
      expect(d, UpdateOutcome.optional);
    });

    test('updateType=FORCE + minVersionCode 缺失 → mandatory（降级强制）', () {
      final d = s.evaluateUpdatePolicy(
        info: _info(updateType: 'FORCE'),
        currentVersion: '9.9.9',
        currentBuildNumber: 9999,
      );
      expect(d, UpdateOutcome.mandatory);
    });

    test('updateType=GRAY + minVersionCode 大于当前 → mandatory', () {
      final d = s.evaluateUpdatePolicy(
        info: _info(updateType: 'GRAY', minVersionCode: 20),
        currentVersion: '1.0.0',
        currentBuildNumber: 10,
      );
      expect(d, UpdateOutcome.mandatory);
    });

    test('updateType=GRAY + minVersionCode 不大于当前 → optional', () {
      final d = s.evaluateUpdatePolicy(
        info: _info(updateType: 'GRAY', minVersionCode: 20),
        currentVersion: '2.0.0',
        currentBuildNumber: 30,
      );
      expect(d, UpdateOutcome.optional);
    });
  });

  group('AppUpdateService.compareVersions (semver)', () {
    test('1.0.2 < 2.0.0', () {
      expect(AppUpdateService.compareVersions('1.0.2', '2.0.0') < 0, isTrue);
    });
    test('1.0.2+1 == 1.0.2（+ 后是 build 号）', () {
      expect(AppUpdateService.compareVersions('1.0.2+1', '1.0.2'), 0);
    });
    test('1.10.0 > 1.9.0（按段数字比，不是字符串）', () {
      expect(AppUpdateService.compareVersions('1.10.0', '1.9.0') > 0, isTrue);
    });
    test('2.0.0-rc1 < 2.0.0（预发布版 < 正式版）', () {
      expect(
          AppUpdateService.compareVersions('2.0.0-rc1', '2.0.0') < 0, isTrue);
    });
  });
}

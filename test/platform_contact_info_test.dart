import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/platform_api.dart';

void main() {
  group('PlatformContactInfo.fromJson', () {
    test('文档 §4.2 完整响应：所有字段解析', () {
      final info = PlatformContactInfo.fromJson(<String, dynamic>{
        'website': 'https://99chat.vip/',
        'email': 'admin@99chat.chat',
        'version': '3.0.1',
        'build': '2',
        'downloadUrl': 'https://down.99chat.vip',
        'platform': 'ios',
        'updateType': 'FORCE',
        'minVersion': '2',
        'minVersionCode': 2,
        'changelog': '体验全面升级\n第二行',
        'grayPercent': 100,
        'inGray': true,
        'splash': {
          'enabled': true,
          'version': '20260907-01',
          'imageUrl': 'https://.../splash.webp',
          'imageMd5': 'abc123',
          'contentType': 'image/webp',
          'width': 1080,
          'height': 1920,
          'bytes': 234567,
          'fit': 'cover',
        },
      });
      expect(info.website, 'https://99chat.vip/');
      expect(info.email, 'admin@99chat.chat');
      expect(info.version, '3.0.1');
      expect(info.build, '2');
      expect(info.downloadUrl, 'https://down.99chat.vip');
      expect(info.platform, 'ios');
      expect(info.updateType, 'FORCE');
      expect(info.minVersion, '2');
      expect(info.minVersionCode, 2);
      expect(info.changelog, '体验全面升级\n第二行');
      expect(info.grayPercent, 100);
      expect(info.inGray, isTrue);
      expect(info.updatePolicy, UpdatePolicy.force);
      expect(info.isMandatoryUpdate, isTrue);
      expect(info.splash, isNotNull);
      expect(info.splash!.enabled, isTrue);
      expect(info.splash!.version, '20260907-01');
      expect(info.splash!.imageUrl, 'https://.../splash.webp');
    });

    test('文档 §4.4 最小响应：缺失字段走默认', () {
      final info = PlatformContactInfo.fromJson(<String, dynamic>{
        'website': 'https://99chat.vip/',
        'email': 'admin@99chat.chat',
        'version': '1.0.0',
        'build': '1',
        'downloadUrl': 'https://99chat.com/download',
        'platform': 'android',
        'updateType': 'OPTIONAL',
        'inGray': false,
        'splash': {
          'enabled': false,
          'version': 'default',
        },
      });
      expect(info.updateType, 'OPTIONAL');
      expect(info.updatePolicy, UpdatePolicy.optional);
      expect(info.isMandatoryUpdate, isFalse);
      expect(info.minVersion, isNull);
      expect(info.minVersionCode, isNull);
      expect(info.changelog, isNull);
      expect(info.grayPercent, isNull);
      expect(info.splash, isNotNull);
      expect(info.splash!.enabled, isFalse);
      expect(info.splash!.hasDownloadableImage, isFalse);
    });

    test('updateType 大小写不敏感（force / Force 都归一为 FORCE）', () {
      final lower =
          PlatformContactInfo.fromJson(<String, dynamic>{'updateType': 'force'});
      final mixed = PlatformContactInfo.fromJson(
          <String, dynamic>{'updateType': 'Force'});
      final empty = PlatformContactInfo.fromJson(<String, dynamic>{});
      expect(lower.updatePolicy, UpdatePolicy.force);
      expect(mixed.updatePolicy, UpdatePolicy.force);
      expect(empty.updateType, 'OPTIONAL');
      expect(empty.updatePolicy, UpdatePolicy.optional);
    });

    test('minVersionCode 缺失时走 minVersion 字符串路径', () {
      final info = PlatformContactInfo.fromJson(<String, dynamic>{
        'updateType': 'FORCE',
        'minVersion': '2.0.0',
      });
      expect(info.updateType, 'FORCE');
      expect(info.minVersion, '2.0.0');
      expect(info.minVersionCode, isNull);
    });

    test('changelog 含 \\n 不被吞掉', () {
      final info = PlatformContactInfo.fromJson(<String, dynamic>{
        'changelog': '第一行\n第二行\n第三行',
      });
      expect(info.changelog!.split('\n').length, 3);
    });

    test('空 JSON 不抛异常', () {
      final info = PlatformContactInfo.fromJson(<String, dynamic>{});
      expect(info.website, '');
      expect(info.updateType, 'OPTIONAL');
      expect(info.splash, isNull);
    });
  });
}

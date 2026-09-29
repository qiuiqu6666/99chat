import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/platform_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/splash_config_service.dart';

void main() {
  test('PlatformSplashConfig.hasDownloadableImage：enabled=false → false', () {
    final cfg = PlatformSplashConfig.fromJson(<String, dynamic>{
      'enabled': false,
      'version': 'default',
    });
    expect(cfg.enabled, isFalse);
    expect(cfg.hasDownloadableImage, isFalse);
  });

  test('PlatformSplashConfig.hasDownloadableImage：enabled=true + 有 url → true',
      () {
    final cfg = PlatformSplashConfig.fromJson(<String, dynamic>{
      'enabled': true,
      'version': '20260907-01',
      'imageUrl': 'https://.../splash.webp',
      'contentType': 'image/webp',
      'bytes': 12345,
    });
    expect(cfg.enabled, isTrue);
    expect(cfg.hasDownloadableImage, isTrue);
    expect(cfg.imageUrl, 'https://.../splash.webp');
  });

  test('PlatformContactInfo.splash 解析后字段完整', () {
    final info = PlatformContactInfo.fromJson(<String, dynamic>{
      'version': '1.0.0',
      'build': '1',
      'splash': {
        'enabled': true,
        'version': 'v1',
        'imageUrl': 'https://x/splash.webp',
        'imageMd5': 'deadbeef',
        'contentType': 'image/webp',
        'width': 1080,
        'height': 1920,
        'bytes': 234567,
        'fit': 'cover',
      },
    });
    final splash = info.splash!;
    expect(splash.enabled, isTrue);
    expect(splash.version, 'v1');
    expect(splash.imageMd5, 'deadbeef');
    expect(splash.width, 1080);
    expect(splash.height, 1920);
    expect(splash.bytes, 234567);
  });

  test('SplashConfigService 单例可访问', () {
    expect(SplashConfigService.instance, isNotNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/media_url_resolver.dart';

void main() {
  test('only known legacy media origin migrates and signature stays exact', () {
    expect(MediaUrlResolver.resolve('http://119.28.179.146:8081/chat-media/v1/a%2Fb.sig?x=a%2Fb'),
      'https://api99chat.99chat.vip/chat-media/v1/a%2Fb.sig?x=a%2Fb');
    expect(MediaUrlResolver.resolve('http://unrelated.example/chat-media/v1/token'),
      'http://unrelated.example/chat-media/v1/token');
    expect(MediaUrlResolver.resolve('http://119.28.179.146:8081/other'),
      'http://119.28.179.146:8081/other');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/group_profile.dart';

void main() {
  test('group alias keeps one leading @ without changing the ID', () {
    expect(normalizeGroupAliasLeadingAt('@@TGS#cLFXJRIM62C5'),
        '@TGS#cLFXJRIM62C5');
    expect(normalizeGroupAliasLeadingAt('@TGS#cLFXJRIM62C5'),
        '@TGS#cLFXJRIM62C5');
    expect(normalizeGroupAliasLeadingAt('TGS#cLFXJRIM62C5'),
        'TGS#cLFXJRIM62C5');
  });
}

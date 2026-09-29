import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

void main() {
  group('readApiWriteEnvelope', () {
    test('unwrapped map without code is not a business error', () {
      final envelope = readApiWriteEnvelope(<String, dynamic>{'groupId': 'g'});
      expect(envelope.isBusinessError, isFalse);
      expect(envelope.payload, isA<Map>());
    });

    test('numeric and string success codes are not business errors', () {
      for (final raw in <dynamic>[
        <String, dynamic>{'code': 0},
        <String, dynamic>{'code': '0'},
        <String, dynamic>{'code': 'ok'},
      ]) {
        final envelope = readApiWriteEnvelope(raw);
        expect(envelope.isBusinessError, isFalse, reason: '$raw');
      }
    });

    test('explicit business code is an error', () {
      final envelope = readApiWriteEnvelope(<String, dynamic>{
        'code': 'NOT_GROUP_OWNER_OR_ADMIN',
      });
      expect(envelope.isBusinessError, isTrue);
      expect(envelope.businessCode, 'NOT_GROUP_OWNER_OR_ADMIN');
    });

    test('success wrapper with data:true keeps non-map payload', () {
      final envelope = readApiWriteEnvelope(<String, dynamic>{
        'code': 0,
        'data': true,
      });
      expect(envelope.isBusinessError, isFalse);
      expect(envelope.payload, isTrue);
    });

    test('result:"ok" is success with string payload', () {
      final envelope = readApiWriteEnvelope(<String, dynamic>{
        'result': 'ok',
      });
      expect(envelope.isBusinessError, isFalse);
      expect(envelope.payload, 'ok');
    });

    test('null and true bodies are not business errors', () {
      expect(readApiWriteEnvelope(null).isBusinessError, isFalse);
      expect(readApiWriteEnvelope(null).payload, isNull);
      expect(readApiWriteEnvelope(true).isBusinessError, isFalse);
      expect(readApiWriteEnvelope(true).payload, isTrue);
    });
  });
}

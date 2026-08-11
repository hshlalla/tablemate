import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/auth/jwt_decoder.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final header = encodeSegment({'alg': 'HS256', 'typ': 'JWT'});
  final body = encodeSegment(payload);
  return '$header.$body.fake-signature';
}

void main() {
  group('decodeUserId', () {
    test('extracts the sub claim from a valid JWT', () {
      final token = _fakeJwt({'sub': 'user-123', 'email': 'jane@example.com'});

      expect(decodeUserId(token), 'user-123');
    });

    test('throws FormatException when the token does not have 3 segments', () {
      expect(() => decodeUserId('not-a-jwt'), throwsFormatException);
    });

    test('throws FormatException when the payload has no sub claim', () {
      final token = _fakeJwt({'email': 'jane@example.com'});

      expect(() => decodeUserId(token), throwsFormatException);
    });
  });
}

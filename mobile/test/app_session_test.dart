import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/app_session.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encodeSegment({'alg': 'HS256'})}.${encodeSegment(payload)}.fake-signature';
}

void main() {
  group('AppSession', () {
    test('login stores the access token and decodes the user id', () async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@example.com'});
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'accessToken': token}), 200);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );
      var notified = false;
      session.addListener(() => notified = true);

      await session.login('jane@example.com', 'password123');

      expect(session.isAuthenticated, isTrue);
      expect(session.userId, 'user-1');
      expect(notified, isTrue);
    });

    test('logout clears the session and notifies listeners', () async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@example.com'});
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'accessToken': token}), 200);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );
      await session.login('jane@example.com', 'password123');
      var notified = false;
      session.addListener(() => notified = true);

      session.logout();

      expect(session.isAuthenticated, isFalse);
      expect(session.userId, isNull);
      expect(notified, isTrue);
    });

    test('discoverRepository throws before login', () {
      final session = AppSession(baseUrl: 'http://localhost:3000');

      expect(() => session.discoverRepository, throwsStateError);
    });
  });
}

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
        return http.Response(
          jsonEncode({'accessToken': token, 'refreshToken': 'r-1'}),
          200,
        );
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
        return http.Response(
          jsonEncode({'accessToken': token, 'refreshToken': 'r-1'}),
          200,
        );
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

    test('using a repository before login throws StateError', () async {
      final session = AppSession(baseUrl: 'http://localhost:3000');

      await expectLater(
        () => session.discoverRepository.fetchCandidates(),
        throwsStateError,
      );
    });

    test(
        'login leaves the session unauthenticated when the token fails to decode',
        () async {
      final badToken = _fakeJwt({'email': 'jane@example.com'}); // no `sub`
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'accessToken': badToken, 'refreshToken': 'r-1'}),
          200,
        );
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );

      await expectLater(
        session.login('jane@example.com', 'password123'),
        throwsFormatException,
      );

      expect(session.isAuthenticated, isFalse);
      expect(session.userId, isNull);
    });
  });

  group('AppSession refresh', () {
    test('refreshes the access token and retries when a repository sees a 401',
        () async {
      final loginAccess = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      final freshAccess = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      var candidatesCalls = 0;
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path == '/auth/login') {
          return http.Response(
            jsonEncode({'accessToken': loginAccess, 'refreshToken': 'r-1'}),
            200,
          );
        }
        if (path == '/auth/refresh') {
          return http.Response(
            jsonEncode({'accessToken': freshAccess, 'refreshToken': 'r-2'}),
            200,
          );
        }
        if (path == '/swipes/candidates') {
          candidatesCalls++;
          if (candidatesCalls == 1) {
            return http.Response(jsonEncode({'message': 'expired'}), 401);
          }
          return http.Response(jsonEncode({'candidates': []}), 200);
        }
        return http.Response(jsonEncode({'message': 'not found'}), 404);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );
      await session.login('jane@x.com', 'pw');

      // First candidates call 401s -> AppSession refreshes -> retry succeeds.
      final result = await session.discoverRepository.fetchCandidates();

      expect(result, isEmpty);
      expect(candidatesCalls, 2);
    });

    test('logs out when the refresh itself fails', () async {
      final loginAccess = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      var candidatesCalls = 0;
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path == '/auth/login') {
          return http.Response(
            jsonEncode({'accessToken': loginAccess, 'refreshToken': 'r-1'}),
            200,
          );
        }
        if (path == '/auth/refresh') {
          return http.Response(jsonEncode({'message': 'revoked'}), 401);
        }
        if (path == '/swipes/candidates') {
          candidatesCalls++;
          return http.Response(jsonEncode({'message': 'expired'}), 401);
        }
        return http.Response(jsonEncode({'message': 'not found'}), 404);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );
      await session.login('jane@x.com', 'pw');

      await expectLater(
        () => session.discoverRepository.fetchCandidates(),
        throwsA(isA<ApiException>()),
      );
      expect(candidatesCalls, 1); // one attempt, then refresh failed -> no retry
      expect(session.isAuthenticated, isFalse);
    });
  });
}

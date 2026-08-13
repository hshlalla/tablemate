import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/app_session.dart';
import 'package:mobile/auth/token_store.dart';
import 'package:mobile/auth_gate.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encodeSegment({'alg': 'HS256'})}.${encodeSegment(payload)}.fake-signature';
}

class FakeTokenStore implements TokenStore {
  FakeTokenStore({this.accessToken, this.refreshToken});
  String? accessToken;
  String? refreshToken;

  @override
  Future<({String? accessToken, String? refreshToken})> read() async =>
      (accessToken: accessToken, refreshToken: refreshToken);

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> clear() async {}
}

class BlockingTokenStore implements TokenStore {
  final _never = Completer<({String? accessToken, String? refreshToken})>();

  @override
  Future<({String? accessToken, String? refreshToken})> read() => _never.future;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets(
    'logs in, shows the home screen, and logs back out to the login screen',
    (tester) async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@example.com'});
      final mockClient = MockClient((request) async {
        if (request.url.path == '/auth/login') {
          return http.Response(
            jsonEncode({'accessToken': token, 'refreshToken': 'r-1'}),
            200,
          );
        }
        if (request.url.path == '/swipes/candidates') {
          return http.Response(jsonEncode({'candidates': []}), 200);
        }
        if (request.url.path == '/matches') {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response(jsonEncode({'message': 'not found'}), 404);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient: ApiClient(
          baseUrl: 'http://localhost:3000',
          httpClient: mockClient,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppSession>.value(
          value: session,
          child: const MaterialApp(home: AuthGate()),
        ),
      );

      expect(find.byKey(const Key('emailField')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('emailField')), 'jane@example.com');
      await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
      await tester.tap(find.byKey(const Key('loginButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logoutButton')), findsOneWidget);
      expect(find.text('더 이상 후보가 없습니다'), findsOneWidget);

      await tester.tap(find.byKey(const Key('logoutButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('emailField')), findsOneWidget);
    },
  );

  testWidgets('shows a loading indicator while restoring', (tester) async {
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      tokenStore: BlockingTokenStore(),
    );
    session.restore(); // never completes -> stays restoring

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSession>.value(
        value: session,
        child: const MaterialApp(home: AuthGate()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('restores a stored session straight into the home screen',
      (tester) async {
    final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
    final mockClient = MockClient((request) async {
      if (request.url.path == '/swipes/candidates') {
        return http.Response(jsonEncode({'candidates': []}), 200);
      }
      if (request.url.path == '/matches') {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response(jsonEncode({'message': 'not found'}), 404);
    });
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      apiClient: ApiClient(
        baseUrl: 'http://localhost:3000',
        httpClient: mockClient,
      ),
      tokenStore: FakeTokenStore(accessToken: token, refreshToken: 'r-1'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSession>.value(
        value: session,
        child: const MaterialApp(home: AuthGate()),
      ),
    );

    await session.restore();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('logoutButton')), findsOneWidget);
  });
}

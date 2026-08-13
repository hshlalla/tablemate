import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/app_session.dart';
import 'package:mobile/auth/login_screen.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encodeSegment({'alg': 'HS256'})}.${encodeSegment(payload)}.fake-signature';
}

void main() {
  testWidgets('submits email and password and authenticates the session', (tester) async {
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

    await tester.pumpWidget(MaterialApp(home: LoginScreen(session: session)));

    await tester.enterText(find.byKey(const Key('emailField')), 'jane@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(session.isAuthenticated, isTrue);
  });

  testWidgets('shows an error message when login fails', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode({'message': 'Invalid credentials'}), 401);
    });
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      apiClient:
          ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
    );

    await tester.pumpWidget(MaterialApp(home: LoginScreen(session: session)));

    await tester.enterText(find.byKey(const Key('emailField')), 'jane@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'wrong');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid credentials'), findsOneWidget);
  });

  testWidgets('navigating to signup and completing it shows a success message', (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/auth/signup') {
        return http.Response(
          jsonEncode({'id': 'user-2', 'email': 'amy@example.com'}),
          201,
        );
      }
      return http.Response(jsonEncode({'message': 'not found'}), 404);
    });
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      apiClient:
          ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
    );

    await tester.pumpWidget(MaterialApp(home: LoginScreen(session: session)));

    await tester.tap(find.byKey(const Key('goToSignupButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('emailField')), 'amy@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
    await tester.tap(find.byKey(const Key('signupButton')));
    await tester.pumpAndSettle();

    expect(find.text('가입 완료 — 로그인해주세요'), findsOneWidget);
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/auth/auth_repository.dart';

void main() {
  group('AuthRepository', () {
    test('login returns both access and refresh tokens', () async {
      final api = ApiClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'accessToken': 'a-1', 'refreshToken': 'r-1'}),
            200,
          );
        }),
      );
      final repo = AuthRepository(api);

      final tokens = await repo.login('jane@example.com', 'pw');

      expect(tokens.accessToken, 'a-1');
      expect(tokens.refreshToken, 'r-1');
    });

    test('refresh posts the refresh token and returns the rotated pair',
        () async {
      String? sentPath;
      Map<String, dynamic>? sentBody;
      final api = ApiClient(
        httpClient: MockClient((request) async {
          sentPath = request.url.path;
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'accessToken': 'a-2', 'refreshToken': 'r-2'}),
            200,
          );
        }),
      );
      final repo = AuthRepository(api);

      final tokens = await repo.refresh('r-1');

      expect(sentPath, '/auth/refresh');
      expect(sentBody, {'refreshToken': 'r-1'});
      expect(tokens.accessToken, 'a-2');
      expect(tokens.refreshToken, 'r-2');
    });

    test('logout posts the refresh token to /auth/logout', () async {
      String? sentPath;
      final api = ApiClient(
        httpClient: MockClient((request) async {
          sentPath = request.url.path;
          return http.Response('{}', 200);
        }),
      );
      final repo = AuthRepository(api);

      await repo.logout('r-1');

      expect(sentPath, '/auth/logout');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/api/authenticated_api_client.dart';

void main() {
  group('AuthenticatedApiClient', () {
    test('attaches the current access token to the request', () async {
      String? sentAuth;
      final api = ApiClient(
        httpClient: MockClient((request) async {
          sentAuth = request.headers['Authorization'];
          return http.Response('[]', 200);
        }),
      );
      final client = AuthenticatedApiClient(
        api,
        () => 'access-1',
        () async => 'unused',
      );

      await client.get('/matches');

      expect(sentAuth, 'Bearer access-1');
    });

    test('refreshes once and retries with the new token on a 401', () async {
      var calls = 0;
      final authHeaders = <String?>[];
      final api = ApiClient(
        httpClient: MockClient((request) async {
          calls++;
          authHeaders.add(request.headers['Authorization']);
          if (calls == 1) {
            return http.Response('{"message": "expired"}', 401);
          }
          return http.Response('{"ok": true}', 200);
        }),
      );
      var refreshCalls = 0;
      final client = AuthenticatedApiClient(
        api,
        () => 'stale',
        () async {
          refreshCalls++;
          return 'fresh';
        },
      );

      final result = await client.post('/swipes', {'x': 1});

      expect(refreshCalls, 1);
      expect(calls, 2);
      expect(authHeaders, ['Bearer stale', 'Bearer fresh']);
      expect(result, {'ok': true});
    });

    test('does not refresh on a non-401 error', () async {
      final api = ApiClient(
        httpClient: MockClient((request) async {
          return http.Response('{"message": "boom"}', 500);
        }),
      );
      var refreshCalls = 0;
      final client = AuthenticatedApiClient(
        api,
        () => 'access-1',
        () async {
          refreshCalls++;
          return 'fresh';
        },
      );

      await expectLater(
        () => client.get('/matches'),
        throwsA(isA<ApiException>()),
      );
      expect(refreshCalls, 0);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';

void main() {
  group('ApiClient.post', () {
    test('returns decoded body on success with a valid JSON object', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"accessToken": "abc123"}', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      final result = await apiClient.post('/auth/login', {
        'email': 'jane@example.com',
        'password': 'password123',
      });

      expect(result['accessToken'], 'abc123');
    });

    test('throws ApiException with server message on error status with valid JSON object', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"message": "Invalid credentials"}', 401);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.post('/auth/login', {'email': 'x', 'password': 'y'}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid credentials')),
      );
    });

    test('throws ApiException instead of crashing on an empty response body', () async {
      final mockClient = MockClient((request) async {
        return http.Response('', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.post('/auth/login', {'email': 'x', 'password': 'y'}),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException instead of crashing on a non-JSON (HTML) response body', () async {
      final mockClient = MockClient((request) async {
        return http.Response('<html><body>502 Bad Gateway</body></html>', 502);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.post('/auth/login', {'email': 'x', 'password': 'y'}),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException instead of crashing when JSON body is an array, not an object', () async {
      final mockClient = MockClient((request) async {
        return http.Response('[1, 2, 3]', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.post('/auth/login', {'email': 'x', 'password': 'y'}),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException instead of crashing when JSON body is a bare scalar', () async {
      final mockClient = MockClient((request) async {
        return http.Response('"just a string"', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.post('/auth/login', {'email': 'x', 'password': 'y'}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('ApiClient.get', () {
    test('returns decoded body when it is a JSON array', () async {
      final mockClient = MockClient((request) async {
        return http.Response('[{"id": "match-1"}]', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      final result = await apiClient.get('/matches', accessToken: 'token-123');

      expect(result, [
        {'id': 'match-1'},
      ]);
    });

    test('returns decoded body when it is a JSON object', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"candidates": []}', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      final result = await apiClient.get(
        '/swipes/candidates',
        accessToken: 'token-123',
      );

      expect(result, {'candidates': []});
    });

    test('sends the bearer token in the Authorization header', () async {
      String? capturedAuthHeader;
      final mockClient = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.Response('[]', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      await apiClient.get('/matches', accessToken: 'token-123');

      expect(capturedAuthHeader, 'Bearer token-123');
    });

    test('throws ApiException with server message on error status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"message": "Unauthorized"}', 401);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.get('/matches', accessToken: 'bad-token'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Unauthorized'),
        ),
      );
    });

    test('throws ApiException instead of crashing on a non-JSON response body', () async {
      final mockClient = MockClient((request) async {
        return http.Response('<html>502</html>', 502);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.get('/matches', accessToken: 'token-123'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

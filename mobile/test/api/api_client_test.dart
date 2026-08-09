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
}

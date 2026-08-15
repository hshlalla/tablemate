import 'dart:convert';

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

    test('carries the HTTP status code on the thrown ApiException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"message": "Unauthorized"}', 401);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      await expectLater(
        () => apiClient.get('/matches', accessToken: 'bad-token'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });

  group('ApiClient.postMultipart', () {
    test('sends a multipart POST with the bearer token and file', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'photoUrl': '/profiles/photos/x.jpg'}),
          200,
        );
      });
      final apiClient = ApiClient(httpClient: mockClient);

      final result = await apiClient.postMultipart(
        '/profiles/me/photo',
        bytes: [1, 2, 3],
        filename: 'p.jpg',
        field: 'photo',
        contentType: 'image/jpeg',
        accessToken: 'tok',
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/profiles/me/photo');
      expect(captured.headers['authorization'], 'Bearer tok');
      expect(captured.headers['content-type'], contains('multipart/form-data'));
      expect(result, {'photoUrl': '/profiles/photos/x.jpg'});
    });

    test('throws ApiException with status on an error response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'message': 'Unauthorized'}), 401);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      await expectLater(
        () => apiClient.postMultipart(
          '/profiles/me/photo',
          bytes: [1],
          filename: 'p.jpg',
          field: 'photo',
          contentType: 'image/jpeg',
          accessToken: 'bad',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });
}

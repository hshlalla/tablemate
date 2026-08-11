import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/discover/discover_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  group('DiscoverRepository.fetchCandidates', () {
    test('returns the parsed candidate list from ApiClient.get', () async {
      final mockApiClient = MockApiClient();
      when(() => mockApiClient.get('/swipes/candidates', accessToken: 'token-123'))
          .thenAnswer(
        (_) async => {
          'candidates': [
            {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
          ],
        },
      );
      final repo = DiscoverRepository(mockApiClient, 'token-123');

      final result = await repo.fetchCandidates();

      expect(result, [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ]);
    });

    test('throws ApiException when the response is a list, not an object', () async {
      final mockApiClient = MockApiClient();
      when(() => mockApiClient.get('/swipes/candidates', accessToken: 'token-123'))
          .thenAnswer(
        (_) async => [
          {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
        ],
      );
      final repo = DiscoverRepository(mockApiClient, 'token-123');

      expect(() => repo.fetchCandidates(), throwsA(isA<ApiException>()));
    });

    test('throws ApiException when the candidates key is missing', () async {
      final mockApiClient = MockApiClient();
      when(() => mockApiClient.get('/swipes/candidates', accessToken: 'token-123'))
          .thenAnswer((_) async => {'unexpected': 'shape'});
      final repo = DiscoverRepository(mockApiClient, 'token-123');

      expect(() => repo.fetchCandidates(), throwsA(isA<ApiException>()));
    });

    test('throws ApiException when candidates is not a List', () async {
      final mockApiClient = MockApiClient();
      when(() => mockApiClient.get('/swipes/candidates', accessToken: 'token-123'))
          .thenAnswer((_) async => {'candidates': 'not-a-list'});
      final repo = DiscoverRepository(mockApiClient, 'token-123');

      expect(() => repo.fetchCandidates(), throwsA(isA<ApiException>()));
    });
  });
}

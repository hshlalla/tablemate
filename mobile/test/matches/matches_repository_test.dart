import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/matches/matches_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  group('MatchesRepository.listMatches', () {
    test('returns the parsed match list from ApiClient.get', () async {
      final mockApiClient = MockApiClient();
      when(() => mockApiClient.get('/matches', accessToken: 'token-123'))
          .thenAnswer(
        (_) async => [
          {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
        ],
      );
      final repo = MatchesRepository(mockApiClient, 'token-123');

      final result = await repo.listMatches();

      expect(result, [
        {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
      ]);
    });

    test('throws ApiException when the response is not a list', () async {
      final mockApiClient = MockApiClient();
      when(() => mockApiClient.get('/matches', accessToken: 'token-123'))
          .thenAnswer((_) async => {'unexpected': 'shape'});
      final repo = MatchesRepository(mockApiClient, 'token-123');

      expect(() => repo.listMatches(), throwsA(isA<ApiException>()));
    });
  });
}

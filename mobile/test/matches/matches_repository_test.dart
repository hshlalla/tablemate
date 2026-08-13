import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/api/authenticated_api_client.dart';
import 'package:mobile/matches/matches_repository.dart';

class MockAuthenticatedApiClient extends Mock
    implements AuthenticatedApiClient {}

void main() {
  group('MatchesRepository.listMatches', () {
    test('returns the parsed match list', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/matches')).thenAnswer(
        (_) async => [
          {'id': 'match-1', 'counterpartUserId': 'user-2', 'counterpartName': 'Jane'},
        ],
      );
      final repo = MatchesRepository(client);

      final result = await repo.listMatches();

      expect(result, [
        {'id': 'match-1', 'counterpartUserId': 'user-2', 'counterpartName': 'Jane'},
      ]);
    });

    test('throws ApiException when the response is not a list', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/matches'))
          .thenAnswer((_) async => {'unexpected': 'shape'});
      final repo = MatchesRepository(client);

      expect(() => repo.listMatches(), throwsA(isA<ApiException>()));
    });
  });
}

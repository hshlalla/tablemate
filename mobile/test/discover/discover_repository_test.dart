import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/api/authenticated_api_client.dart';
import 'package:mobile/discover/discover_repository.dart';

class MockAuthenticatedApiClient extends Mock
    implements AuthenticatedApiClient {}

void main() {
  group('DiscoverRepository', () {
    test('fetchCandidates returns the candidate list', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/swipes/candidates')).thenAnswer(
        (_) async => {
          'candidates': [
            {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
          ],
        },
      );
      final repo = DiscoverRepository(client);

      final result = await repo.fetchCandidates();

      expect(result, [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ]);
    });

    test('fetchCandidates throws when the shape is invalid', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/swipes/candidates'))
          .thenAnswer((_) async => {'unexpected': 'shape'});
      final repo = DiscoverRepository(client);

      expect(() => repo.fetchCandidates(), throwsA(isA<ApiException>()));
    });

    test('swipe posts and reports whether a match resulted', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.post('/swipes', {'targetUserId': 'user-2', 'liked': true}))
          .thenAnswer((_) async => {'swipe': {}, 'match': {'id': 'm-1'}});
      final repo = DiscoverRepository(client);

      final matched = await repo.swipe('user-2', true);

      expect(matched, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/authenticated_api_client.dart';
import 'package:mobile/profile/profile_repository.dart';

class MockAuthenticatedApiClient extends Mock
    implements AuthenticatedApiClient {}

void main() {
  group('ProfileRepository', () {
    test('getMyProfile returns the profile map', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/profiles/me')).thenAnswer(
        (_) async =>
            {'displayName': 'Jane', 'photoUrl': '/profiles/photos/a.jpg'},
      );
      final repo = ProfileRepository(client);

      final result = await repo.getMyProfile();

      expect(result, {
        'displayName': 'Jane',
        'photoUrl': '/profiles/photos/a.jpg',
      });
    });

    test('getMyProfile returns null when the backend returns null', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/profiles/me')).thenAnswer((_) async => null);
      final repo = ProfileRepository(client);

      expect(await repo.getMyProfile(), isNull);
    });

    test('uploadPhoto posts the file to the photo endpoint', () async {
      final client = MockAuthenticatedApiClient();
      when(
        () => client.postMultipart(
          '/profiles/me/photo',
          bytes: [1, 2],
          filename: 'p.jpg',
          field: 'photo',
          contentType: 'image/jpeg',
        ),
      ).thenAnswer((_) async => {'photoUrl': '/profiles/photos/new.jpg'});
      final repo = ProfileRepository(client);

      final result = await repo.uploadPhoto(
        bytes: [1, 2],
        filename: 'p.jpg',
        contentType: 'image/jpeg',
      );

      expect(result, {'photoUrl': '/profiles/photos/new.jpg'});
    });
  });
}

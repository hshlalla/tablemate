import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/auth/secure_token_store.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('SecureTokenStore', () {
    test('read returns the access and refresh tokens by key', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.read(key: 'accessToken'))
          .thenAnswer((_) async => 'a-1');
      when(() => storage.read(key: 'refreshToken'))
          .thenAnswer((_) async => 'r-1');
      final store = SecureTokenStore(storage: storage);

      final result = await store.read();

      expect(result.accessToken, 'a-1');
      expect(result.refreshToken, 'r-1');
    });

    test('write persists both tokens under their keys', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
      final store = SecureTokenStore(storage: storage);

      await store.write(accessToken: 'a-1', refreshToken: 'r-1');

      verify(() => storage.write(key: 'accessToken', value: 'a-1')).called(1);
      verify(() => storage.write(key: 'refreshToken', value: 'r-1')).called(1);
    });

    test('clear deletes both token keys', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      final store = SecureTokenStore(storage: storage);

      await store.clear();

      verify(() => storage.delete(key: 'accessToken')).called(1);
      verify(() => storage.delete(key: 'refreshToken')).called(1);
    });
  });
}

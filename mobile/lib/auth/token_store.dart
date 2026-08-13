/// Persists the auth token pair. Abstracted so tests can inject an
/// in-memory fake instead of touching platform secure storage.
abstract class TokenStore {
  Future<({String? accessToken, String? refreshToken})> read();
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clear();
}

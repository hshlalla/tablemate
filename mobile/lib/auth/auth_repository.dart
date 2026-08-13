import '../api/api_client.dart';

class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<({String accessToken, String refreshToken})> login(
    String email,
    String password,
  ) async {
    final result = await _apiClient.post('/auth/login', {
      'email': email,
      'password': password,
    });
    return (
      accessToken: result['accessToken'] as String,
      refreshToken: result['refreshToken'] as String,
    );
  }

  Future<void> signup(String email, String password) async {
    await _apiClient.post('/auth/signup', {
      'email': email,
      'password': password,
    });
  }

  Future<({String accessToken, String refreshToken})> refresh(
    String refreshToken,
  ) async {
    final result = await _apiClient.post('/auth/refresh', {
      'refreshToken': refreshToken,
    });
    return (
      accessToken: result['accessToken'] as String,
      refreshToken: result['refreshToken'] as String,
    );
  }

  Future<void> logout(String refreshToken) async {
    await _apiClient.post('/auth/logout', {'refreshToken': refreshToken});
  }
}

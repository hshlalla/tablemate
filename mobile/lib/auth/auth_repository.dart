import '../api/api_client.dart';

class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<String> login(String email, String password) async {
    final result = await _apiClient.post('/auth/login', {
      'email': email,
      'password': password,
    });
    return result['accessToken'] as String;
  }

  Future<void> signup(String email, String password) async {
    await _apiClient.post('/auth/signup', {
      'email': email,
      'password': password,
    });
  }
}

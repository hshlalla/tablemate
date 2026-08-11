import '../api/api_client.dart';

class MatchesRepository {
  MatchesRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String _accessToken;

  Future<List<Map<String, dynamic>>> listMatches() async {
    final decoded = await _apiClient.get('/matches', accessToken: _accessToken);
    if (decoded is! List) {
      throw ApiException('Invalid response from server');
    }
    return decoded.cast<Map<String, dynamic>>();
  }
}

import '../api/api_client.dart';
import '../api/authenticated_api_client.dart';

class MatchesRepository {
  MatchesRepository(this._client);

  final AuthenticatedApiClient _client;

  Future<List<Map<String, dynamic>>> listMatches() async {
    final decoded = await _client.get('/matches');
    if (decoded is! List) {
      throw ApiException('Invalid response from server');
    }
    return decoded.cast<Map<String, dynamic>>();
  }
}

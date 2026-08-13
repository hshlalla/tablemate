import '../api/api_client.dart';
import '../api/authenticated_api_client.dart';

class DiscoverRepository {
  DiscoverRepository(this._client);

  final AuthenticatedApiClient _client;

  Future<List<Map<String, dynamic>>> fetchCandidates() async {
    final decoded = await _client.get('/swipes/candidates');
    if (decoded is! Map<String, dynamic> || decoded['candidates'] is! List) {
      throw ApiException('Invalid response from server');
    }
    return (decoded['candidates'] as List).cast<Map<String, dynamic>>();
  }

  Future<bool> swipe(String targetUserId, bool liked) async {
    final result = await _client.post(
      '/swipes',
      {'targetUserId': targetUserId, 'liked': liked},
    );
    return result['match'] != null;
  }
}

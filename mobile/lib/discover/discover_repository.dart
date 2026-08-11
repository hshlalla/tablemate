import '../api/api_client.dart';

class DiscoverRepository {
  DiscoverRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String _accessToken;

  Future<List<Map<String, dynamic>>> fetchCandidates() async {
    final decoded = await _apiClient.get(
      '/swipes/candidates',
      accessToken: _accessToken,
    );
    if (decoded is! Map<String, dynamic> || decoded['candidates'] is! List) {
      throw ApiException('Invalid response from server');
    }
    return (decoded['candidates'] as List).cast<Map<String, dynamic>>();
  }

  Future<bool> swipe(String targetUserId, bool liked) async {
    final result = await _apiClient.post(
      '/swipes',
      {'targetUserId': targetUserId, 'liked': liked},
      accessToken: _accessToken,
    );
    return result['match'] != null;
  }
}

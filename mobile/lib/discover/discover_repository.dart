import '../api/api_client.dart';

class DiscoverRepository {
  DiscoverRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String _accessToken;

  Future<bool> swipe(String targetUserId, bool liked) async {
    final result = await _apiClient.post(
      '/swipes',
      {'targetUserId': targetUserId, 'liked': liked},
      accessToken: _accessToken,
    );
    return result['match'] != null;
  }
}

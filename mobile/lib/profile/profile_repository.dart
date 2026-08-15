import '../api/api_client.dart';
import '../api/authenticated_api_client.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final AuthenticatedApiClient _client;

  Future<Map<String, dynamic>?> getMyProfile() async {
    final decoded = await _client.get('/profiles/me');
    if (decoded == null) return null;
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Invalid response from server');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) {
    return _client.postMultipart(
      '/profiles/me/photo',
      bytes: bytes,
      filename: filename,
      field: 'photo',
      contentType: contentType,
    );
  }
}

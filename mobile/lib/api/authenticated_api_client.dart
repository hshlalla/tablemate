import 'api_client.dart';

/// Wraps [ApiClient] with the current access token and transparent
/// single-retry refresh on a 401. Auth token accessors are injected as
/// functions so this stays decoupled from AppSession and easy to test.
class AuthenticatedApiClient {
  AuthenticatedApiClient(
    this._api,
    this._currentAccessToken,
    this._refreshAccessToken,
  );

  final ApiClient _api;
  final String Function() _currentAccessToken;
  final Future<String> Function() _refreshAccessToken;

  Future<dynamic> get(String path) async {
    try {
      return await _api.get(path, accessToken: _currentAccessToken());
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final newToken = await _refreshAccessToken();
      return await _api.get(path, accessToken: newToken);
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _api.post(path, body, accessToken: _currentAccessToken());
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final newToken = await _refreshAccessToken();
      return await _api.post(path, body, accessToken: newToken);
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<int> bytes,
    required String filename,
    required String field,
    required String contentType,
  }) async {
    try {
      return await _api.postMultipart(
        path,
        bytes: bytes,
        filename: filename,
        field: field,
        contentType: contentType,
        accessToken: _currentAccessToken(),
      );
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final newToken = await _refreshAccessToken();
      return await _api.postMultipart(
        path,
        bytes: bytes,
        filename: filename,
        field: field,
        contentType: contentType,
        accessToken: newToken,
      );
    }
  }
}

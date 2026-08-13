import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
import 'api/authenticated_api_client.dart';
import 'auth/auth_repository.dart';
import 'auth/jwt_decoder.dart';
import 'chat/chat_socket_client.dart';
import 'discover/discover_repository.dart';
import 'matches/matches_repository.dart';

class AppSession extends ChangeNotifier {
  AppSession({required String baseUrl, ApiClient? apiClient})
      : _baseUrl = baseUrl,
        _apiClient = apiClient ?? ApiClient(baseUrl: baseUrl);

  final String _baseUrl;
  final ApiClient _apiClient;

  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  Future<String>? _inFlightRefresh;
  DiscoverRepository? _discoverRepository;
  MatchesRepository? _matchesRepository;

  bool get isAuthenticated => _accessToken != null;
  String? get userId => _userId;

  late final AuthRepository authRepository = AuthRepository(_apiClient);

  late final AuthenticatedApiClient _authClient = AuthenticatedApiClient(
    _apiClient,
    _requireToken,
    _refresh,
  );

  DiscoverRepository get discoverRepository =>
      _discoverRepository ??= DiscoverRepository(_authClient);

  MatchesRepository get matchesRepository =>
      _matchesRepository ??= MatchesRepository(_authClient);

  String _requireToken() {
    final token = _accessToken;
    if (token == null) {
      throw StateError('AppSession: not authenticated');
    }
    return token;
  }

  Future<void> login(String email, String password) async {
    final tokens = await authRepository.login(email, password);
    final userId = decodeUserId(tokens.accessToken);
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
    _userId = userId;
    notifyListeners();
  }

  /// Single-flight refresh: concurrent 401s share one in-flight refresh.
  Future<String> _refresh() {
    return _inFlightRefresh ??=
        _doRefresh().whenComplete(() => _inFlightRefresh = null);
  }

  Future<String> _doRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      throw StateError('AppSession: not authenticated');
    }
    try {
      final tokens = await authRepository.refresh(refreshToken);
      _accessToken = tokens.accessToken;
      _refreshToken = tokens.refreshToken;
      return tokens.accessToken;
    } catch (_) {
      logout();
      rethrow;
    }
  }

  void logout() {
    final refreshToken = _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    _discoverRepository = null;
    _matchesRepository = null;
    notifyListeners();
    if (refreshToken != null) {
      // Best-effort server-side revocation; ignore failures.
      authRepository.logout(refreshToken).catchError((_) {});
    }
  }

  ChatSocketClient buildChatSocketClient() {
    return ChatSocketClient(_baseUrl, _requireToken());
  }
}

import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
import 'api/authenticated_api_client.dart';
import 'auth/auth_repository.dart';
import 'auth/jwt_decoder.dart';
import 'auth/token_store.dart';
import 'auth/secure_token_store.dart';
import 'chat/chat_socket_client.dart';
import 'discover/discover_repository.dart';
import 'matches/matches_repository.dart';
import 'profile/profile_repository.dart';

class AppSession extends ChangeNotifier {
  AppSession({
    required String baseUrl,
    ApiClient? apiClient,
    TokenStore? tokenStore,
  })  : _baseUrl = baseUrl,
        _apiClient = apiClient ?? ApiClient(baseUrl: baseUrl),
        _tokenStore = tokenStore ?? SecureTokenStore();

  final String _baseUrl;
  final ApiClient _apiClient;
  final TokenStore _tokenStore;

  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  bool _isRestoring = false;
  Future<String>? _inFlightRefresh;
  DiscoverRepository? _discoverRepository;
  MatchesRepository? _matchesRepository;
  ProfileRepository? _profileRepository;

  bool get isAuthenticated => _accessToken != null;
  bool get isRestoring => _isRestoring;
  String? get userId => _userId;
  String get baseUrl => _baseUrl;

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

  ProfileRepository get profileRepository =>
      _profileRepository ??= ProfileRepository(_authClient);

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
    await _persist();
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
      await _persist();
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
    _profileRepository = null;
    notifyListeners();
    if (refreshToken != null) {
      // Best-effort server-side revocation; ignore failures.
      authRepository.logout(refreshToken).catchError((_) {});
    }
    _clearStore();
  }

  ChatSocketClient buildChatSocketClient() {
    return ChatSocketClient(_baseUrl, _requireToken());
  }

  Future<void> restore() async {
    _isRestoring = true;
    notifyListeners();
    try {
      final stored = await _tokenStore.read();
      final access = stored.accessToken;
      final refresh = stored.refreshToken;
      if (access != null && refresh != null) {
        final userId = decodeUserId(access);
        _accessToken = access;
        _refreshToken = refresh;
        _userId = userId;
      }
    } on FormatException {
      await _clearStore();
    } catch (_) {
      // Storage read failure -> treat as no stored session.
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final access = _accessToken;
    final refresh = _refreshToken;
    if (access == null || refresh == null) return;
    try {
      await _tokenStore.write(accessToken: access, refreshToken: refresh);
    } catch (_) {}
  }

  Future<void> _clearStore() async {
    try {
      await _tokenStore.clear();
    } catch (_) {}
  }
}

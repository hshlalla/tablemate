import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
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
  String? _userId;
  DiscoverRepository? _discoverRepository;
  MatchesRepository? _matchesRepository;

  bool get isAuthenticated => _accessToken != null;
  String? get userId => _userId;

  late final AuthRepository authRepository = AuthRepository(_apiClient);

  DiscoverRepository get discoverRepository =>
      _discoverRepository ??= DiscoverRepository(_apiClient, _requireToken());

  MatchesRepository get matchesRepository =>
      _matchesRepository ??= MatchesRepository(_apiClient, _requireToken());

  String _requireToken() {
    final token = _accessToken;
    if (token == null) {
      throw StateError('AppSession: not authenticated');
    }
    return token;
  }

  Future<void> login(String email, String password) async {
    final token = await authRepository.login(email, password);
    final userId = decodeUserId(token);
    _accessToken = token;
    _userId = userId;
    _discoverRepository = null;
    _matchesRepository = null;
    notifyListeners();
  }

  void logout() {
    _accessToken = null;
    _userId = null;
    _discoverRepository = null;
    _matchesRepository = null;
    notifyListeners();
  }

  ChatSocketClient buildChatSocketClient() {
    return ChatSocketClient(_baseUrl, _requireToken());
  }
}

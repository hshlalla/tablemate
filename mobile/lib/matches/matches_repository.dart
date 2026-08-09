import 'dart:convert';
import 'package:http/http.dart' as http;

class MatchesRepository {
  MatchesRepository(this._baseUrl, this._accessToken);

  final String _baseUrl;
  final String _accessToken;

  Future<List<Map<String, dynamic>>> listMatches() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/matches'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }
}

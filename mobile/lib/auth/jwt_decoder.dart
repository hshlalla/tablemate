import 'dart:convert';

/// Decodes the `sub` claim (user id) from a JWT's payload, without
/// verifying the signature. This is safe here because the token is the
/// one this client itself just received from `POST /auth/login` /
/// `POST /auth/signup` — there is no untrusted third party handing us a
/// token to verify.
String decodeUserId(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) {
    throw FormatException(
      'Not a valid JWT: expected 3 segments, got ${parts.length}',
    );
  }

  final payload = _decodeBase64Segment(parts[1]);
  final decoded = jsonDecode(payload);
  if (decoded is! Map<String, dynamic> || decoded['sub'] is! String) {
    throw const FormatException('JWT payload missing "sub" claim');
  }
  return decoded['sub'] as String;
}

String _decodeBase64Segment(String segment) {
  final normalized = base64Url.normalize(segment);
  return utf8.decode(base64Url.decode(normalized));
}

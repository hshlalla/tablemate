/// Resolves a backend-relative photo path (e.g. `/profiles/photos/<key>`)
/// into an absolute URL the app can load, or null when there is no photo.
String? absolutePhotoUrl(String baseUrl, String? relative) {
  if (relative == null) return null;
  return '$baseUrl$relative';
}

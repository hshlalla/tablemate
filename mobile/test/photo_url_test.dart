import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/photo_url.dart';

void main() {
  group('absolutePhotoUrl', () {
    test('prefixes the base url onto a relative path', () {
      expect(
        absolutePhotoUrl('http://localhost:3000', '/profiles/photos/a.jpg'),
        'http://localhost:3000/profiles/photos/a.jpg',
      );
    });

    test('returns null when the relative path is null', () {
      expect(absolutePhotoUrl('http://localhost:3000', null), isNull);
    });
  });
}

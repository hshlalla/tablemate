import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/profile/image_picker_service.dart';

class MockImagePicker extends Mock implements ImagePicker {}

void main() {
  group('GalleryImagePicker', () {
    test('returns the picked image bytes, name and content type', () async {
      final picker = MockImagePicker();
      when(() => picker.pickImage(source: ImageSource.gallery)).thenAnswer(
        (_) async => XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          name: 'p.png',
          path: 'p.png',
          mimeType: 'image/png',
        ),
      );
      final service = GalleryImagePicker(picker: picker);

      final result = await service.pickFromGallery();

      expect(result, isNotNull);
      expect(result!.bytes, [1, 2, 3]);
      expect(result.filename, 'p.png');
      expect(result.contentType, 'image/png');
    });

    test('returns null when the user cancels', () async {
      final picker = MockImagePicker();
      when(() => picker.pickImage(source: ImageSource.gallery))
          .thenAnswer((_) async => null);
      final service = GalleryImagePicker(picker: picker);

      expect(await service.pickFromGallery(), isNull);
    });
  });
}

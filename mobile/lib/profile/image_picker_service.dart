import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class PickedImage {
  PickedImage({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

abstract class ImagePickerService {
  Future<PickedImage?> pickFromGallery();
}

class GalleryImagePicker implements ImagePickerService {
  GalleryImagePicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedImage?> pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final contentType =
        file.mimeType ?? lookupMimeType(file.name) ?? 'image/jpeg';
    return PickedImage(
      bytes: bytes,
      filename: file.name,
      contentType: contentType,
    );
  }
}

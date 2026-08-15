import 'package:flutter/material.dart';
import '../photo_url.dart';
import '../widgets/profile_avatar.dart';
import 'image_picker_service.dart';
import 'profile_repository.dart';

class ProfileScreen extends StatefulWidget {
  ProfileScreen({
    super.key,
    required this.repository,
    required this.imageBaseUrl,
    ImagePickerService? picker,
  }) : picker = picker ?? GalleryImagePicker();

  final ProfileRepository repository;
  final String imageBaseUrl;
  final ImagePickerService picker;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _uploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.repository.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _changePhoto() async {
    final picked = await widget.picker.pickFromGallery();
    if (picked == null) return;
    setState(() {
      _uploading = true;
      _errorMessage = null;
    });
    try {
      final updated = await widget.repository.uploadPhoto(
        bytes: picked.bytes,
        filename: picked.filename,
        contentType: picked.contentType,
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final photoUrl = absolutePhotoUrl(
      widget.imageBaseUrl,
      _profile?['photoUrl'] as String?,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('프로필')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProfileAvatar(imageUrl: photoUrl, radius: 60),
            const SizedBox(height: 16),
            Text(
              _profile?['displayName'] as String? ?? '(이름 없음)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              key: const Key('changePhotoButton'),
              onPressed: _uploading ? null : _changePhoto,
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('사진 변경'),
            ),
          ],
        ),
      ),
    );
  }
}

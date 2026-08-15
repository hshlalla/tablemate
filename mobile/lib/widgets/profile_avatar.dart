import 'package:flutter/material.dart';

/// A circular profile photo. Falls back to a person icon when there is no
/// image url or the image fails to load.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.imageUrl, this.radius = 20});

  final String? imageUrl;
  final double radius;

  Widget _fallback() =>
      CircleAvatar(radius: radius, child: Icon(Icons.person, size: radius));

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) {
      return _fallback();
    }
    return ClipOval(
      child: Image.network(
        url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      ),
    );
  }
}

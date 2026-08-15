import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/profile_avatar.dart';

void main() {
  testWidgets('renders a network image from the given url', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileAvatar(imageUrl: 'http://localhost:3000/profiles/photos/a.jpg'),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect(
      (image.image as NetworkImage).url,
      'http://localhost:3000/profiles/photos/a.jpg',
    );
  });

  testWidgets('shows a fallback icon when there is no url', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ProfileAvatar(imageUrl: null)),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}

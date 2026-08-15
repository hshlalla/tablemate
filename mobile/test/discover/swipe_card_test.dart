import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/discover/swipe_card.dart';

void main() {
  testWidgets('shows the photo and name when an imageUrl is given',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SwipeCard(name: 'Jane', imageUrl: 'http://x/a.jpg'),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'http://x/a.jpg');
    expect(find.text('Jane'), findsOneWidget);
  });

  testWidgets('shows only the name when there is no imageUrl', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SwipeCard(name: 'Jane')));

    expect(find.byType(Image), findsNothing);
    expect(find.text('Jane'), findsOneWidget);
  });
}

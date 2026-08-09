import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/discover/discover_repository.dart';
import 'package:mobile/discover/discover_screen.dart';

class MockDiscoverRepository extends Mock implements DiscoverRepository {}

void main() {
  testWidgets('tapping like calls DiscoverRepository.swipe with liked=true', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.swipe('user-2', true)).thenAnswer((_) async => false);

    await tester.pumpWidget(MaterialApp(
      home: DiscoverScreen(
        repository: mockRepo,
        candidateUserId: 'user-2',
        candidateName: 'Jane',
      ),
    ));

    await tester.tap(find.byKey(const Key('likeButton')));
    await tester.pumpAndSettle();

    verify(() => mockRepo.swipe('user-2', true)).called(1);
  });
}

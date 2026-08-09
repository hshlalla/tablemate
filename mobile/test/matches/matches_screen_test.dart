import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/matches/matches_repository.dart';
import 'package:mobile/matches/matches_screen.dart';

class MockMatchesRepository extends Mock implements MatchesRepository {}

void main() {
  testWidgets('renders each match returned by the repository', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo),
    ));
    await tester.pumpAndSettle();

    expect(find.text('match-1'), findsOneWidget);
  });
}

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
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('match-1'), findsOneWidget);
  });

  testWidgets('tapping a match calls onSelectMatch with its id', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
      ],
    );
    String? selected;

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(
        repository: mockRepo,
        onSelectMatch: (matchId) => selected = matchId,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('match-1'));
    await tester.pumpAndSettle();

    expect(selected, 'match-1');
  });

  testWidgets('shows an error message when listMatches throws', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenThrow(Exception('Network error'));

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Exception: Network error'), findsOneWidget);
  });

  testWidgets('calling refresh() via GlobalKey re-invokes listMatches()', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
      ],
    );
    final key = GlobalKey<MatchesScreenState>();

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(key: key, repository: mockRepo, onSelectMatch: (_) {}),
    ));
    await tester.pumpAndSettle();

    verify(() => mockRepo.listMatches()).called(1);

    await key.currentState!.refresh();
    await tester.pumpAndSettle();

    verify(() => mockRepo.listMatches()).called(1);
  });

  testWidgets(
    'shows a retryButton on error, and tapping it re-invokes listMatches()',
    (tester) async {
      final mockRepo = MockMatchesRepository();
      when(() => mockRepo.listMatches()).thenThrow(Exception('Network error'));

      await tester.pumpWidget(MaterialApp(
        home: MatchesScreen(repository: mockRepo, onSelectMatch: (_) {}),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retryButton')), findsOneWidget);
      verify(() => mockRepo.listMatches()).called(1);

      when(() => mockRepo.listMatches()).thenAnswer(
        (_) async => [
          {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
        ],
      );

      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.listMatches()).called(1);
      expect(find.text('match-1'), findsOneWidget);
    },
  );
}

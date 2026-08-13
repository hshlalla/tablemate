import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/matches/matches_repository.dart';
import 'package:mobile/matches/matches_screen.dart';

class MockMatchesRepository extends Mock implements MatchesRepository {}

void main() {
  testWidgets('renders the counterpart name of each match', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {
          'id': 'match-1',
          'counterpartUserId': 'user-2',
          'counterpartName': 'Jane',
        },
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_, _) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Jane'), findsOneWidget);
  });

  testWidgets('falls back to a placeholder when the counterpart name is null',
      (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {
          'id': 'match-1',
          'counterpartUserId': 'user-2',
          'counterpartName': null,
        },
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_, _) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('(이름 없음)'), findsOneWidget);
  });

  testWidgets('tapping a match calls onSelectMatch with its id and name',
      (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {
          'id': 'match-1',
          'counterpartUserId': 'user-2',
          'counterpartName': 'Jane',
        },
      ],
    );
    String? selectedId;
    String? selectedName;

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(
        repository: mockRepo,
        onSelectMatch: (matchId, name) {
          selectedId = matchId;
          selectedName = name;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jane'));
    await tester.pumpAndSettle();

    expect(selectedId, 'match-1');
    expect(selectedName, 'Jane');
  });

  testWidgets('shows an error message when listMatches throws', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenThrow(Exception('Network error'));

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_, _) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Exception: Network error'), findsOneWidget);
  });

  testWidgets('calling refresh() via GlobalKey re-invokes listMatches()',
      (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {
          'id': 'match-1',
          'counterpartUserId': 'user-2',
          'counterpartName': 'Jane',
        },
      ],
    );
    final key = GlobalKey<MatchesScreenState>();

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(
        key: key,
        repository: mockRepo,
        onSelectMatch: (_, _) {},
      ),
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
        home: MatchesScreen(repository: mockRepo, onSelectMatch: (_, _) {}),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retryButton')), findsOneWidget);
      verify(() => mockRepo.listMatches()).called(1);

      when(() => mockRepo.listMatches()).thenAnswer(
        (_) async => [
          {
            'id': 'match-1',
            'counterpartUserId': 'user-2',
            'counterpartName': 'Jane',
          },
        ],
      );

      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.listMatches()).called(1);
      expect(find.text('Jane'), findsOneWidget);
    },
  );
}

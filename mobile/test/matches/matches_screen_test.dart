import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/matches/matches_repository.dart';
import 'package:mobile/matches/matches_screen.dart';
import 'package:mobile/widgets/profile_avatar.dart';

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
          'counterpartPhotoUrl': null,
        },
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_, _, _) {}),
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
          'counterpartPhotoUrl': null,
        },
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_, _, _) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('(이름 없음)'), findsOneWidget);
  });

  testWidgets('renders a counterpart avatar from the resolved photo url',
      (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {
          'id': 'match-1',
          'counterpartUserId': 'user-2',
          'counterpartName': 'Jane',
          'counterpartPhotoUrl': '/profiles/photos/j.jpg',
        },
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(
        repository: mockRepo,
        onSelectMatch: (_, _, _) {},
        imageBaseUrl: 'http://localhost:3000',
      ),
    ));
    await tester.pumpAndSettle();

    final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
    expect(avatar.imageUrl, 'http://localhost:3000/profiles/photos/j.jpg');
  });

  testWidgets('tapping a match calls onSelectMatch with id, name and photo url',
      (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {
          'id': 'match-1',
          'counterpartUserId': 'user-2',
          'counterpartName': 'Jane',
          'counterpartPhotoUrl': '/profiles/photos/j.jpg',
        },
      ],
    );
    String? selectedId;
    String? selectedName;
    String? selectedPhotoUrl;

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(
        repository: mockRepo,
        imageBaseUrl: 'http://localhost:3000',
        onSelectMatch: (matchId, name, photoUrl) {
          selectedId = matchId;
          selectedName = name;
          selectedPhotoUrl = photoUrl;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jane'));
    await tester.pumpAndSettle();

    expect(selectedId, 'match-1');
    expect(selectedName, 'Jane');
    expect(selectedPhotoUrl, 'http://localhost:3000/profiles/photos/j.jpg');
  });

  testWidgets('shows an error message when listMatches throws', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenThrow(Exception('Network error'));

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_, _, _) {}),
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
          'counterpartPhotoUrl': null,
        },
      ],
    );
    final key = GlobalKey<MatchesScreenState>();

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(
        key: key,
        repository: mockRepo,
        onSelectMatch: (_, _, _) {},
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
        home: MatchesScreen(repository: mockRepo, onSelectMatch: (_, _, _) {}),
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
            'counterpartPhotoUrl': null,
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/discover/discover_repository.dart';
import 'package:mobile/discover/discover_screen.dart';
import 'package:mobile/discover/swipe_card.dart';

class MockDiscoverRepository extends Mock implements DiscoverRepository {}

void main() {
  testWidgets('resolves the candidate photoUrl into an absolute SwipeCard image',
      (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenAnswer(
      (_) async => [
        {
          'userId': 'user-2',
          'displayName': 'Jane',
          'bio': 'Hi',
          'photoUrl': '/profiles/photos/a.jpg',
        },
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverScreen(
          repository: mockRepo,
          imageBaseUrl: 'http://localhost:3000',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.widget<SwipeCard>(find.byType(SwipeCard));
    expect(card.imageUrl, 'http://localhost:3000/profiles/photos/a.jpg');
  });

  testWidgets('fetches candidates on load and shows the first one', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenAnswer(
      (_) async => [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ],
    );

    await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
    await tester.pumpAndSettle();

    expect(find.text('Jane'), findsOneWidget);
  });

  testWidgets(
    'tapping like calls DiscoverRepository.swipe with liked=true and advances to next candidate',
    (tester) async {
      final mockRepo = MockDiscoverRepository();
      when(() => mockRepo.fetchCandidates()).thenAnswer(
        (_) async => [
          {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
          {'userId': 'user-3', 'displayName': 'Amy', 'bio': 'Hey'},
        ],
      );
      when(() => mockRepo.swipe('user-2', true)).thenAnswer((_) async => false);

      await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.swipe('user-2', true)).called(1);
      expect(find.text('Amy'), findsOneWidget);
    },
  );

  testWidgets('shows an empty state once all candidates are swiped', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenAnswer(
      (_) async => [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ],
    );
    when(() => mockRepo.swipe('user-2', false)).thenAnswer((_) async => false);

    await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('passButton')));
    await tester.pumpAndSettle();

    expect(find.text('더 이상 후보가 없습니다'), findsOneWidget);
  });

  testWidgets('shows an error message when DiscoverRepository.swipe throws', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenAnswer(
      (_) async => [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ],
    );
    when(() => mockRepo.swipe('user-2', true)).thenThrow(Exception('Network error'));

    await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('likeButton')));
    await tester.pumpAndSettle();

    expect(find.text('Exception: Network error'), findsOneWidget);
  });

  testWidgets('shows an error message when fetchCandidates throws', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenThrow(Exception('Network error'));

    await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
    await tester.pumpAndSettle();

    expect(find.text('Exception: Network error'), findsOneWidget);
  });

  testWidgets(
    'clears the error message once a retry succeeds',
    (tester) async {
      final mockRepo = MockDiscoverRepository();
      when(() => mockRepo.fetchCandidates()).thenThrow(Exception('Network error'));

      await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      expect(find.text('Exception: Network error'), findsOneWidget);
      expect(find.byKey(const Key('retryButton')), findsOneWidget);

      when(() => mockRepo.fetchCandidates()).thenAnswer(
        (_) async => [
          {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
        ],
      );

      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();

      expect(find.text('Exception: Network error'), findsNothing);
      expect(find.text('Jane'), findsOneWidget);
    },
  );

  testWidgets(
    'shows a retryButton once candidates are exhausted, and tapping it re-invokes fetchCandidates()',
    (tester) async {
      final mockRepo = MockDiscoverRepository();
      when(() => mockRepo.fetchCandidates()).thenAnswer(
        (_) async => [
          {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
        ],
      );
      when(() => mockRepo.swipe('user-2', false)).thenAnswer((_) async => false);

      await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('passButton')));
      await tester.pumpAndSettle();

      expect(find.text('더 이상 후보가 없습니다'), findsOneWidget);
      expect(find.byKey(const Key('retryButton')), findsOneWidget);
      verify(() => mockRepo.fetchCandidates()).called(1);

      when(() => mockRepo.fetchCandidates()).thenAnswer(
        (_) async => [
          {'userId': 'user-3', 'displayName': 'Amy', 'bio': 'Hey'},
        ],
      );

      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.fetchCandidates()).called(1);
      expect(find.text('Amy'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping like twice in quick succession only calls swipe once',
    (tester) async {
      final mockRepo = MockDiscoverRepository();
      when(() => mockRepo.fetchCandidates()).thenAnswer(
        (_) async => [
          {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
        ],
      );
      final completer = Completer<bool>();
      when(() => mockRepo.swipe('user-2', true))
          .thenAnswer((_) => completer.future);

      await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();

      completer.complete(false);
      await tester.pumpAndSettle();

      verify(() => mockRepo.swipe('user-2', true)).called(1);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/auth/auth_repository.dart';
import 'package:mobile/auth/login_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  testWidgets('submits email and password to AuthRepository.login', (tester) async {
    final mockRepo = MockAuthRepository();
    when(() => mockRepo.login('jane@example.com', 'password123'))
        .thenAnswer((_) async => 'fake-token');

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(authRepository: mockRepo),
    ));

    await tester.enterText(find.byKey(const Key('emailField')), 'jane@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    verify(() => mockRepo.login('jane@example.com', 'password123')).called(1);
  });
}

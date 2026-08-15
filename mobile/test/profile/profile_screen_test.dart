import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/profile/image_picker_service.dart';
import 'package:mobile/profile/profile_repository.dart';
import 'package:mobile/profile/profile_screen.dart';
import 'package:mobile/widgets/profile_avatar.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

class FakeImagePickerService implements ImagePickerService {
  FakeImagePickerService(this.result);
  final PickedImage? result;
  @override
  Future<PickedImage?> pickFromGallery() async => result;
}

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('loads and shows the profile name and photo', (tester) async {
    final repo = MockProfileRepository();
    when(() => repo.getMyProfile()).thenAnswer(
      (_) async =>
          {'displayName': 'Jane', 'photoUrl': '/profiles/photos/a.jpg'},
    );

    await tester.pumpWidget(wrap(ProfileScreen(
      repository: repo,
      imageBaseUrl: 'http://localhost:3000',
      picker: FakeImagePickerService(null),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Jane'), findsOneWidget);
    final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
    expect(avatar.imageUrl, 'http://localhost:3000/profiles/photos/a.jpg');
  });

  testWidgets('picking an image uploads it and shows the new photo',
      (tester) async {
    final repo = MockProfileRepository();
    when(() => repo.getMyProfile()).thenAnswer(
      (_) async => {'displayName': 'Jane', 'photoUrl': null},
    );
    when(() => repo.uploadPhoto(
          bytes: any(named: 'bytes'),
          filename: 'p.jpg',
          contentType: 'image/jpeg',
        )).thenAnswer(
      (_) async =>
          {'displayName': 'Jane', 'photoUrl': '/profiles/photos/new.jpg'},
    );
    final picked = PickedImage(
      bytes: Uint8List.fromList([1, 2]),
      filename: 'p.jpg',
      contentType: 'image/jpeg',
    );

    await tester.pumpWidget(wrap(ProfileScreen(
      repository: repo,
      imageBaseUrl: 'http://localhost:3000',
      picker: FakeImagePickerService(picked),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('changePhotoButton')));
    await tester.pumpAndSettle();

    verify(() => repo.uploadPhoto(
          bytes: any(named: 'bytes'),
          filename: 'p.jpg',
          contentType: 'image/jpeg',
        )).called(1);
    final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
    expect(avatar.imageUrl, 'http://localhost:3000/profiles/photos/new.jpg');
  });

  testWidgets('cancelling the picker does not upload', (tester) async {
    final repo = MockProfileRepository();
    when(() => repo.getMyProfile()).thenAnswer(
      (_) async => {'displayName': 'Jane', 'photoUrl': null},
    );

    await tester.pumpWidget(wrap(ProfileScreen(
      repository: repo,
      imageBaseUrl: 'http://localhost:3000',
      picker: FakeImagePickerService(null),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('changePhotoButton')));
    await tester.pumpAndSettle();

    verifyNever(() => repo.uploadPhoto(
          bytes: any(named: 'bytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
        ));
  });

  testWidgets('shows an error message when the upload fails', (tester) async {
    final repo = MockProfileRepository();
    when(() => repo.getMyProfile()).thenAnswer(
      (_) async => {'displayName': 'Jane', 'photoUrl': null},
    );
    when(() => repo.uploadPhoto(
          bytes: any(named: 'bytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
        )).thenThrow(Exception('upload failed'));
    final picked = PickedImage(
      bytes: Uint8List.fromList([1, 2]),
      filename: 'p.jpg',
      contentType: 'image/jpeg',
    );

    await tester.pumpWidget(wrap(ProfileScreen(
      repository: repo,
      imageBaseUrl: 'http://localhost:3000',
      picker: FakeImagePickerService(picked),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('changePhotoButton')));
    await tester.pumpAndSettle();

    expect(find.text('Exception: upload failed'), findsOneWidget);
  });
}

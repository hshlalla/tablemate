# 모바일 프로필 사진 업로드 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사용자가 갤러리에서 사진을 골라 `POST /profiles/me/photo`로 업로드하고, `ProfileScreen`에서 현재/갱신된 사진을 볼 수 있게 한다.

**Architecture:** 이미지 선택은 `ImagePickerService` 추상화 뒤에(테스트는 페이크 주입), 멀티파트 업로드는 `ApiClient`/`AuthenticatedApiClient`에 추가해 기존 401 자동 갱신을 재사용. `ProfileRepository`가 조회/업로드를, `ProfileScreen`이 UI를 담당하고 `HomeScreen` AppBar 아이콘으로 진입한다.

**Tech Stack:** Flutter(stable), `provider`(기존), `image_picker`(신규), `http_parser`(신규, 멀티파트 MediaType), `mime`(image_picker 전이), `http`(기존, MultipartRequest), `mocktail`(dev, 기존).

**Spec:** `docs/superpowers/specs/2026-08-15-profile-photo-upload-design.md`

## Global Constraints

- 멀티파트 업로드의 401 처리는 `AuthenticatedApiClient.postMultipart`가 담당한다(리프레시 1회 후 재시도). 리포지토리/화면은 직접 토큰을 다루지 않는다.
- 이미지 선택은 `ImagePickerService`를 통해서만 한다. `ProfileScreen`은 플랫폼 채널(`image_picker`)을 직접 호출하지 않는다.
- `contentType`은 `image/jpeg`|`image/png`를 기대하되 최종 검증은 백엔드가 담당한다.
- 모바일 flutter 명령은 `export PATH="/Users/studio/development/flutter/bin:$PATH"` 후 `mobile/`에서 실행한다.
- 각 로직 단위는 TDD.

---

## 파일 구조 개요

```
mobile/
  pubspec.yaml                                (수정: image_picker, http_parser)
  lib/
    api/
      api_client.dart                         (수정: postMultipart)
      authenticated_api_client.dart           (수정: postMultipart)
    profile/
      image_picker_service.dart               (신규)
      profile_repository.dart                 (신규)
      profile_screen.dart                     (신규)
    app_session.dart                          (수정: profileRepository)
    home_screen.dart                          (수정: 프로필 진입 버튼)
  test/
    api/api_client_test.dart                  (수정: postMultipart)
    api/authenticated_api_client_test.dart    (수정: postMultipart)
    profile/image_picker_service_test.dart    (신규)
    profile/profile_repository_test.dart      (신규)
    profile/profile_screen_test.dart          (신규)
    auth_gate_test.dart                       (수정: 프로필 버튼 존재 확인)
```

---

### Task 1: `http_parser` 의존성 + `ApiClient.postMultipart`

**Files:**
- Modify: `mobile/pubspec.yaml` (via pub add)
- Modify: `mobile/lib/api/api_client.dart`
- Modify: `mobile/test/api/api_client_test.dart`

**Interfaces:**
- Produces: `ApiClient.postMultipart(String path, { required List<int> bytes, required String filename, required String field, required String contentType, String? accessToken }): Future<Map<String, dynamic>>`. Task 2가 소비.

- [ ] **Step 1: 패키지 추가**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter pub add http_parser`
Expected: `pubspec.yaml`/`pubspec.lock` 갱신.

- [ ] **Step 2: 실패하는 테스트 작성 (`api_client_test.dart` 맨 끝 `}` 앞에 새 그룹 추가)**

```dart
  group('ApiClient.postMultipart', () {
    test('sends a multipart POST with the bearer token and file', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'photoUrl': '/profiles/photos/x.jpg'}),
          200,
        );
      });
      final apiClient = ApiClient(httpClient: mockClient);

      final result = await apiClient.postMultipart(
        '/profiles/me/photo',
        bytes: [1, 2, 3],
        filename: 'p.jpg',
        field: 'photo',
        contentType: 'image/jpeg',
        accessToken: 'tok',
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/profiles/me/photo');
      expect(captured.headers['authorization'], 'Bearer tok');
      expect(captured.headers['content-type'], contains('multipart/form-data'));
      expect(result, {'photoUrl': '/profiles/photos/x.jpg'});
    });

    test('throws ApiException with status on an error response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'message': 'Unauthorized'}), 401);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      await expectLater(
        () => apiClient.postMultipart(
          '/profiles/me/photo',
          bytes: [1],
          filename: 'p.jpg',
          field: 'photo',
          contentType: 'image/jpeg',
          accessToken: 'bad',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });
```

(파일 상단 import에 `import 'dart:convert';`, `import 'package:http/http.dart' as http;`, `import 'package:http/testing.dart';`가 이미 있음 — 확인만.)

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/api_client_test.dart`
Expected: FAIL (`The method 'postMultipart' isn't defined`)

- [ ] **Step 4: 구현**

`mobile/lib/api/api_client.dart` 상단 import에 추가:

```dart
import 'package:http_parser/http_parser.dart';
```

`get()` 아래에 추가:

```dart
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<int> bytes,
    required String filename,
    required String field,
    required String contentType,
    String? accessToken,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ),
    );

    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'Invalid response from server',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        'Invalid response from server',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        decoded['message']?.toString() ?? 'Request failed',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/api_client_test.dart`
Expected: PASS (기존 + 신규 2개)

- [ ] **Step 6: 커밋**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/api/api_client.dart mobile/test/api/api_client_test.dart
git commit -m "feat: add ApiClient.postMultipart for multipart uploads"
```

---

### Task 2: `AuthenticatedApiClient.postMultipart`

**Files:**
- Modify: `mobile/lib/api/authenticated_api_client.dart`
- Modify: `mobile/test/api/authenticated_api_client_test.dart`

**Interfaces:**
- Consumes: `ApiClient.postMultipart`(Task 1)
- Produces: `AuthenticatedApiClient.postMultipart(String path, { required List<int> bytes, required String filename, required String field, required String contentType }): Future<Map<String, dynamic>>`. Task 4가 소비.

- [ ] **Step 1: 실패하는 테스트 작성 (`authenticated_api_client_test.dart`의 group 안에 추가)**

```dart
    test('postMultipart refreshes once and retries on a 401', () async {
      var calls = 0;
      final authHeaders = <String?>[];
      final api = ApiClient(
        httpClient: MockClient((request) async {
          calls++;
          authHeaders.add(request.headers['authorization']);
          if (calls == 1) {
            return http.Response('{"message": "expired"}', 401);
          }
          return http.Response('{"photoUrl": "/profiles/photos/x.jpg"}', 200);
        }),
      );
      var refreshCalls = 0;
      final client = AuthenticatedApiClient(
        api,
        () => 'stale',
        () async {
          refreshCalls++;
          return 'fresh';
        },
      );

      final result = await client.postMultipart(
        '/profiles/me/photo',
        bytes: [1, 2, 3],
        filename: 'p.jpg',
        field: 'photo',
        contentType: 'image/jpeg',
      );

      expect(refreshCalls, 1);
      expect(calls, 2);
      expect(authHeaders, ['Bearer stale', 'Bearer fresh']);
      expect(result, {'photoUrl': '/profiles/photos/x.jpg'});
    });
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/authenticated_api_client_test.dart`
Expected: FAIL (`The method 'postMultipart' isn't defined`)

- [ ] **Step 3: 구현 (`authenticated_api_client.dart`의 `post` 아래에 추가)**

```dart
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<int> bytes,
    required String filename,
    required String field,
    required String contentType,
  }) async {
    try {
      return await _api.postMultipart(
        path,
        bytes: bytes,
        filename: filename,
        field: field,
        contentType: contentType,
        accessToken: _currentAccessToken(),
      );
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final newToken = await _refreshAccessToken();
      return await _api.postMultipart(
        path,
        bytes: bytes,
        filename: filename,
        field: field,
        contentType: contentType,
        accessToken: newToken,
      );
    }
  }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/authenticated_api_client_test.dart`
Expected: PASS (기존 3개 + 신규 1개)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/api/authenticated_api_client.dart mobile/test/api/authenticated_api_client_test.dart
git commit -m "feat: add AuthenticatedApiClient.postMultipart with 401 refresh"
```

---

### Task 3: `ImagePickerService` + `GalleryImagePicker`

**Files:**
- Modify: `mobile/pubspec.yaml` (via pub add)
- Create: `mobile/lib/profile/image_picker_service.dart`
- Create: `mobile/test/profile/image_picker_service_test.dart`

**Interfaces:**
- Produces: `PickedImage { Uint8List bytes; String filename; String contentType; }`, `abstract class ImagePickerService { Future<PickedImage?> pickFromGallery(); }`, `GalleryImagePicker implements ImagePickerService`. Task 4/5가 소비.

- [ ] **Step 1: 패키지 추가**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter pub add image_picker`
Expected: `pubspec.yaml`/`pubspec.lock` 갱신(`mime` 포함).

- [ ] **Step 2: 실패하는 테스트 작성**

`mobile/test/profile/image_picker_service_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/profile/image_picker_service.dart';

class MockImagePicker extends Mock implements ImagePicker {}

void main() {
  group('GalleryImagePicker', () {
    test('returns the picked image bytes, name and content type', () async {
      final picker = MockImagePicker();
      when(() => picker.pickImage(source: ImageSource.gallery)).thenAnswer(
        (_) async => XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          name: 'p.png',
          mimeType: 'image/png',
        ),
      );
      final service = GalleryImagePicker(picker: picker);

      final result = await service.pickFromGallery();

      expect(result, isNotNull);
      expect(result!.bytes, [1, 2, 3]);
      expect(result.filename, 'p.png');
      expect(result.contentType, 'image/png');
    });

    test('returns null when the user cancels', () async {
      final picker = MockImagePicker();
      when(() => picker.pickImage(source: ImageSource.gallery))
          .thenAnswer((_) async => null);
      final service = GalleryImagePicker(picker: picker);

      expect(await service.pickFromGallery(), isNull);
    });
  });
}
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/profile/image_picker_service_test.dart`
Expected: FAIL (`Target of URI doesn't exist: '.../image_picker_service.dart'`)

- [ ] **Step 4: 구현**

`mobile/lib/profile/image_picker_service.dart`:

```dart
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class PickedImage {
  PickedImage({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

abstract class ImagePickerService {
  Future<PickedImage?> pickFromGallery();
}

class GalleryImagePicker implements ImagePickerService {
  GalleryImagePicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedImage?> pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final contentType =
        file.mimeType ?? lookupMimeType(file.name) ?? 'image/jpeg';
    return PickedImage(
      bytes: bytes,
      filename: file.name,
      contentType: contentType,
    );
  }
}
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/profile/image_picker_service_test.dart`
Expected: PASS (2/2)

- [ ] **Step 6: 커밋**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/profile/image_picker_service.dart mobile/test/profile/image_picker_service_test.dart
git commit -m "feat: add ImagePickerService with gallery-backed implementation"
```

---

### Task 4: `ProfileRepository` + `AppSession.profileRepository`

**Files:**
- Create: `mobile/lib/profile/profile_repository.dart`
- Create: `mobile/test/profile/profile_repository_test.dart`
- Modify: `mobile/lib/app_session.dart`

**Interfaces:**
- Consumes: `AuthenticatedApiClient.get`(기존)/`postMultipart`(Task 2)
- Produces: `ProfileRepository(AuthenticatedApiClient)` with `getMyProfile(): Future<Map<String, dynamic>?>`, `uploadPhoto({ required List<int> bytes, required String filename, required String contentType }): Future<Map<String, dynamic>>`. `AppSession.profileRepository`. Task 5/6이 소비.

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/profile/profile_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/authenticated_api_client.dart';
import 'package:mobile/profile/profile_repository.dart';

class MockAuthenticatedApiClient extends Mock
    implements AuthenticatedApiClient {}

void main() {
  group('ProfileRepository', () {
    test('getMyProfile returns the profile map', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/profiles/me')).thenAnswer(
        (_) async => {'displayName': 'Jane', 'photoUrl': '/profiles/photos/a.jpg'},
      );
      final repo = ProfileRepository(client);

      final result = await repo.getMyProfile();

      expect(result, {
        'displayName': 'Jane',
        'photoUrl': '/profiles/photos/a.jpg',
      });
    });

    test('getMyProfile returns null when the backend returns null', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/profiles/me')).thenAnswer((_) async => null);
      final repo = ProfileRepository(client);

      expect(await repo.getMyProfile(), isNull);
    });

    test('uploadPhoto posts the file to the photo endpoint', () async {
      final client = MockAuthenticatedApiClient();
      when(
        () => client.postMultipart(
          '/profiles/me/photo',
          bytes: [1, 2],
          filename: 'p.jpg',
          field: 'photo',
          contentType: 'image/jpeg',
        ),
      ).thenAnswer((_) async => {'photoUrl': '/profiles/photos/new.jpg'});
      final repo = ProfileRepository(client);

      final result = await repo.uploadPhoto(
        bytes: [1, 2],
        filename: 'p.jpg',
        contentType: 'image/jpeg',
      );

      expect(result, {'photoUrl': '/profiles/photos/new.jpg'});
    });
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/profile/profile_repository_test.dart`
Expected: FAIL (모듈 없음)

- [ ] **Step 3: 구현**

`mobile/lib/profile/profile_repository.dart`:

```dart
import '../api/api_client.dart';
import '../api/authenticated_api_client.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final AuthenticatedApiClient _client;

  Future<Map<String, dynamic>?> getMyProfile() async {
    final decoded = await _client.get('/profiles/me');
    if (decoded == null) return null;
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Invalid response from server');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) {
    return _client.postMultipart(
      '/profiles/me/photo',
      bytes: bytes,
      filename: filename,
      field: 'photo',
      contentType: contentType,
    );
  }
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/profile/profile_repository_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: `AppSession`에 profileRepository 배선**

`mobile/lib/app_session.dart` 상단 import에 추가:

```dart
import 'profile/profile_repository.dart';
```

필드 선언부(`_matchesRepository` 근처)에 추가:

```dart
  ProfileRepository? _profileRepository;
```

`matchesRepository` 게터 아래에 추가:

```dart
  ProfileRepository get profileRepository =>
      _profileRepository ??= ProfileRepository(_authClient);
```

`logout()`에서 다른 리포지토리 초기화와 함께 추가:

```dart
    _profileRepository = null;
```

- [ ] **Step 6: 전체 스위트 확인 (회귀 없는지)**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test`
Expected: 전체 PASS.

- [ ] **Step 7: 커밋**

```bash
git add mobile/lib/profile/profile_repository.dart mobile/test/profile/profile_repository_test.dart mobile/lib/app_session.dart
git commit -m "feat: add ProfileRepository and expose it from AppSession"
```

---

### Task 5: `ProfileScreen`

**Files:**
- Create: `mobile/lib/profile/profile_screen.dart`
- Create: `mobile/test/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `ProfileRepository`(Task 4), `ImagePickerService`(Task 3), `absolutePhotoUrl`(기존), `ProfileAvatar`(기존)
- Produces: `ProfileScreen({ required ProfileRepository repository, required String imageBaseUrl, ImagePickerService picker })`. Task 6이 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/profile/profile_screen_test.dart`:

```dart
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
      (_) async => {'displayName': 'Jane', 'photoUrl': '/profiles/photos/a.jpg'},
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
      (_) async => {'displayName': 'Jane', 'photoUrl': '/profiles/photos/new.jpg'},
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
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/profile/profile_screen_test.dart`
Expected: FAIL (모듈 없음)

- [ ] **Step 3: 구현**

`mobile/lib/profile/profile_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../photo_url.dart';
import '../widgets/profile_avatar.dart';
import 'image_picker_service.dart';
import 'profile_repository.dart';

class ProfileScreen extends StatefulWidget {
  ProfileScreen({
    super.key,
    required this.repository,
    required this.imageBaseUrl,
    ImagePickerService? picker,
  }) : picker = picker ?? GalleryImagePicker();

  final ProfileRepository repository;
  final String imageBaseUrl;
  final ImagePickerService picker;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _uploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.repository.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _changePhoto() async {
    final picked = await widget.picker.pickFromGallery();
    if (picked == null) return;
    setState(() {
      _uploading = true;
      _errorMessage = null;
    });
    try {
      final updated = await widget.repository.uploadPhoto(
        bytes: picked.bytes,
        filename: picked.filename,
        contentType: picked.contentType,
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final photoUrl = absolutePhotoUrl(
      widget.imageBaseUrl,
      _profile?['photoUrl'] as String?,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('프로필')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProfileAvatar(imageUrl: photoUrl, radius: 60),
            const SizedBox(height: 16),
            Text(
              _profile?['displayName'] as String? ?? '(이름 없음)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              key: const Key('changePhotoButton'),
              onPressed: _uploading ? null : _changePhoto,
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('사진 변경'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/profile/profile_screen_test.dart`
Expected: PASS (4/4)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/profile/profile_screen.dart mobile/test/profile/profile_screen_test.dart
git commit -m "feat: add ProfileScreen with gallery photo upload"
```

---

### Task 6: `HomeScreen` 프로필 진입 버튼

**Files:**
- Modify: `mobile/lib/home_screen.dart`
- Modify: `mobile/test/auth_gate_test.dart`

**Interfaces:**
- Consumes: `AppSession.profileRepository`/`baseUrl`(Task 4), `ProfileScreen`(Task 5)
- Produces: 없음(진입점)

- [ ] **Step 1: 실패하는 테스트 작성 (`auth_gate_test.dart`의 첫 번째 로그인 테스트에 프로필 버튼 존재 확인 추가)**

`auth_gate_test.dart`의 `'logs in, shows the home screen, and logs back out to the login screen'` 테스트에서 `expect(find.byKey(const Key('logoutButton')), findsOneWidget);` 아래에 추가:

```dart
      expect(find.byKey(const Key('profileButton')), findsOneWidget);
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth_gate_test.dart`
Expected: FAIL (`profileButton` 없음)

- [ ] **Step 3: 구현**

`mobile/lib/home_screen.dart` 상단 import에 추가:

```dart
import 'profile/profile_screen.dart';
```

AppBar의 `actions` 배열에서 기존 `logoutButton` `IconButton` **앞에** 다음을 추가:

```dart
          IconButton(
            key: const Key('profileButton'),
            icon: const Icon(Icons.person),
            onPressed: () {
              final session = context.read<AppSession>();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    repository: session.profileRepository,
                    imageBaseUrl: session.baseUrl,
                  ),
                ),
              );
            },
          ),
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth_gate_test.dart`
Expected: PASS.

- [ ] **Step 5: 전체 스위트 + analyze**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, analyze 클린.

- [ ] **Step 6: 커밋**

```bash
git add mobile/lib/home_screen.dart mobile/test/auth_gate_test.dart
git commit -m "feat: open ProfileScreen from a HomeScreen AppBar button"
```

---

### Task 7: 검증 + README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 모바일 전체 스위트 + analyze**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, 클린.

- [ ] **Step 2: README 갱신**

`README.md`를 Read한 뒤 프로필 사진 관련 "알려진 제약" 항목을 갱신한다: 모바일에서 이제 프로필 화면(AppBar 프로필 아이콘)에서 갤러리 사진을 골라 업로드할 수 있다(카메라·크롭·다중 사진은 후속). 실기기에서의 실제 갤러리 선택은 이 개발 환경 툴체인 부재로 검증되지 않고 `ImagePickerService` 페이크·목 테스트로 갈음했다. `mobile/` 구조 설명에 `lib/profile/`(프로필 화면·리포지토리·이미지 선택 추상화)을 추가한다.

- [ ] **Step 3: 커밋**

```bash
git add README.md
git commit -m "docs: document mobile profile photo upload"
```

## Self-Review 결과

- **스펙 커버리지:** 의존성(Task 1, 3), `ApiClient.postMultipart`(Task 1), `AuthenticatedApiClient.postMultipart`(Task 2), `ImagePickerService`/`GalleryImagePicker`(Task 3), `ProfileRepository`+`AppSession`(Task 4), `ProfileScreen`(Task 5), 내비게이션(Task 6), 검증·문서(Task 7) — 스펙 전 항목 커버.
- **플레이스홀더 스캔:** 없음. 모든 코드 스텝에 실제 코드 포함.
- **타입 일관성:** `postMultipart(path, {bytes, filename, field, contentType, [accessToken]})` 시그니처가 Task 1(ApiClient)·Task 2(AuthenticatedApiClient, accessToken 제외)·Task 4(ProfileRepository 소비)에서 일치. `PickedImage{bytes,filename,contentType}`(Task 3)가 Task 5의 `uploadPhoto` 인자와 일치. `ProfileRepository.getMyProfile(): Future<Map?>`/`uploadPhoto(...)`(Task 4)가 Task 5 소비와 일치. `ProfileScreen({repository, imageBaseUrl, picker})`(Task 5)가 Task 6 사용처와 일치. `absolutePhotoUrl`/`ProfileAvatar`는 이전 서브프로젝트에서 확립된 것을 재사용.

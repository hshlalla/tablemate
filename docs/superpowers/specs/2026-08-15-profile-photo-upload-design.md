# 모바일 프로필 사진 업로드 설계 문서

**작성일:** 2026-08-15
**상태:** 설계 승인됨 (구현 계획 대기)

## 목표

사용자가 자기 프로필 사진을 갤러리에서 골라 업로드할 수 있게 한다. `ProfileScreen`에서 현재 사진/이름을 보여주고, 갤러리에서 선택한 이미지를 `POST /profiles/me/photo`로 멀티파트 업로드한다. 액세스 토큰 만료 시 기존 401 자동 갱신을 재사용한다.

## 설계 결정 (확정)

- **진입 경로:** `HomeScreen` AppBar의 프로필 아이콘 → `ProfileScreen` push.
- **이미지 소스:** 갤러리만(`image_picker`의 `ImageSource.gallery`). 카메라는 후속.
- **추상화:** 이미지 선택은 `ImagePickerService` 뒤에 두어 테스트에서 페이크 주입. 멀티파트 업로드는 API 계층에 추가해 기존 `AuthenticatedApiClient`의 401 재시도 패턴을 재사용.

## 비목표

- 카메라 촬영, 이미지 크롭/리사이즈, 다중 사진, 이름·바이오 편집 UI.

## 실현가능성 스파이크 (수행됨)

- `flutter pub add image_picker --dry-run` → 해석 성공(15개 의존성, `mime` 포함).
- `http ^1.6.0`은 `MultipartRequest` 지원 확인.

---

## 아키텍처

### 의존성

- 추가: `image_picker`(^1.x), `http_parser`(멀티파트 파트의 `MediaType` 구성용; http의 전이 의존이지만 직접 import하므로 명시 선언).

### 이미지 선택 추상화 (`mobile/lib/profile/image_picker_service.dart`)

```
class PickedImage {
  final Uint8List bytes;
  final String filename;
  final String contentType; // image/jpeg | image/png
}

abstract class ImagePickerService {
  Future<PickedImage?> pickFromGallery(); // null when the user cancels
}

class GalleryImagePicker implements ImagePickerService {
  GalleryImagePicker({ImagePicker? picker});
  // wraps image_picker; derives contentType from XFile.mimeType,
  // falling back to lookupMimeType(filename) (package:mime).
}
```

- 생성자에 `ImagePicker`를 주입 가능하게 하여 목으로 테스트.
- `contentType` 도출: `XFile.mimeType`이 있으면 사용, 없으면 `lookupMimeType(filename)`(package:mime), 둘 다 없으면 `image/jpeg`로 폴백. 도출된 타입이 실제로 jpeg/png인지의 최종 검증은 백엔드(멀티파트 파트 content-type 기반)가 담당하며, 거부 시 화면에 에러를 표시한다.

### API 계층 — 멀티파트

- `ApiClient.postMultipart(String path, { required List<int> bytes, required String filename, required String field, required String contentType, String? accessToken }): Future<Map<String, dynamic>>`
  - `http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))` 생성, `accessToken`이 있으면 `Authorization: Bearer` 헤더, `http.MultipartFile.fromBytes(field, bytes, filename: filename, contentType: MediaType.parse(contentType))` 추가.
  - `_httpClient.send(request)` → `http.Response.fromStream` → JSON 디코드. 비-JSON이거나 `Map`이 아니면 `ApiException('Invalid response from server', statusCode)`. `statusCode >= 400`이면 `ApiException(message ?? 'Request failed', statusCode)`. 성공 시 디코드된 `Map` 반환. (기존 `post`와 동일한 방어·상태코드 규약.)
- `AuthenticatedApiClient.postMultipart(String path, { required List<int> bytes, required String filename, required String field, required String contentType }): Future<Map<String, dynamic>>`
  - 현재 액세스 토큰으로 `_api.postMultipart(...)` 호출. `ApiException.statusCode == 401`이면 `_refreshAccessToken()` 1회 후 새 토큰으로 재시도. (기존 `get`/`post`와 동일.)

### `ProfileRepository` (`mobile/lib/profile/profile_repository.dart`)

```
class ProfileRepository {
  ProfileRepository(AuthenticatedApiClient client);
  Future<Map<String, dynamic>?> getMyProfile();       // GET /profiles/me, null when backend returns null
  Future<Map<String, dynamic>> uploadPhoto({ required List<int> bytes, required String filename, required String contentType });
  // POST /profiles/me/photo, field 'photo' -> updated profile map
}
```

- `getMyProfile`: `_client.get('/profiles/me')`가 `null`이면 `null` 반환, `Map`이면 그대로, 그 외 타입이면 `ApiException`.
- `uploadPhoto`: `_client.postMultipart('/profiles/me/photo', bytes: ..., filename: ..., field: 'photo', contentType: ...)`.

### `AppSession`

- `ProfileRepository get profileRepository`(지연 생성, `_authClient` 기반). `logout()`에서 다른 지연 리포지토리들과 함께 `null`로 초기화.

### `ProfileScreen` (`mobile/lib/profile/profile_screen.dart`)

- 생성자: `{ required ProfileRepository repository, required String imageBaseUrl, ImagePickerService picker }`(picker 기본값 `GalleryImagePicker()`).
- `initState`에서 `getMyProfile()` 로드 → `ProfileAvatar`(큰 반지름) + `displayName` 표시. 로드 중 스피너.
- "사진 변경" 버튼(key `changePhotoButton`) → `picker.pickFromGallery()`:
  - `null`(취소)이면 아무 것도 하지 않음.
  - 선택되면 업로드 중 상태(버튼 비활성/스피너) → `repository.uploadPhoto(...)` → 반환된 프로필의 `photoUrl`로 아바타 갱신.
  - 실패 시 빨간 에러 메시지(기존 `_errorMessage` 패턴).
- 현재 사진 URL은 `absolutePhotoUrl(imageBaseUrl, profile['photoUrl'])`로 렌더.

### 내비게이션 (`mobile/lib/home_screen.dart`)

- AppBar `actions`에 프로필 `IconButton`(key `profileButton`, `Icons.person`) 추가 → `Navigator.push`로 `ProfileScreen(repository: session.profileRepository, imageBaseUrl: session.baseUrl)`. 기존 로그아웃 아이콘은 유지.

---

## 테스트 & 검증 (모두 이 샌드박스에서 실행)

- `ApiClient.postMultipart`(`MockClient`): 멀티파트 요청의 method/path/`Authorization`/`Content-Type: multipart/form-data` 확인, JSON 디코드 반환, 401 → `ApiException(statusCode: 401)`.
- `AuthenticatedApiClient.postMultipart`: 401 → 리프레시 → 재시도(새 토큰 부착).
- `ProfileRepository`(목 `AuthenticatedApiClient`): `getMyProfile`(맵/널), `uploadPhoto` 위임.
- `GalleryImagePicker`(목 `ImagePicker` + `XFile.fromData`): 선택 시 `PickedImage`(bytes/filename/contentType), 취소 시 `null`.
- `ProfileScreen`(페이크 `ImagePickerService` + 목 `ProfileRepository`): 로드 후 이름/아바타 표시; 변경 탭 → 선택 → 업로드 → 새 사진 반영; 취소 시 업로드 미호출; 업로드 실패 시 에러 메시지.
- `flutter test` 전체 + `flutter analyze`. 각 단위 TDD.

## 알려진 제약 (구현 후 README 반영)

- 프로필 사진 업로드는 갤러리 선택만 지원(카메라·크롭·다중 사진은 후속).
- 실기기·시뮬레이터에서의 실제 갤러리 선택은 이 개발 환경 툴체인 부재로 검증되지 않고, `ImagePickerService` 페이크·목 기반 테스트로 갈음한다.

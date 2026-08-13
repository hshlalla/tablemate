# 토큰 영속 저장 설계 문서

**작성일:** 2026-08-14
**상태:** 설계 승인됨 (구현 계획 대기)

## 목표

현재 로그인/리프레시 토큰은 모바일 메모리에만 보관되어, 앱을 재시작하면 로그아웃된다. 토큰을 기기 secure storage에 영속 저장해, 앱을 껐다 켜도 로그인 세션이 유지되도록 한다.

## 설계 결정 (확정)

- **복원 전략:** 로그인/회전 시 **액세스+리프레시 토큰 둘 다** secure storage에 저장한다. 콜드 스타트 시 저장된 토큰을 메모리에 복원하고, 저장된 액세스 토큰에서 **userId를 로컬 디코딩**(네트워크 왕복 없이 즉시 홈 진입)한다. 액세스 토큰이 만료됐으면 기존 401 자동 갱신(`AuthenticatedApiClient` + `AppSession._refresh`)이 첫 API 호출에서 처리하고, 리프레시 토큰마저 무효면 그 갱신이 실패해 로그아웃 → 로그인 화면으로 전환된다.
- **저장 패키지:** `flutter_secure_storage`(iOS Keychain / Android EncryptedSharedPreferences). `flutter pub add flutter_secure_storage --dry-run`으로 해석 가능함을 스파이크로 확인했다.

## 비목표

- secure storage 자체의 암호화 키 로테이션, 생체인증(Face ID/지문) 게이트 — flutter_secure_storage 기본 보안 저장에 의존한다.
- 콜드 스타트 시 서버에 토큰 유효성을 선검증하는 스피너 플로우 — 대신 저장 토큰으로 즉시 홈 진입하고, 무효 시 기존 401 자동 갱신 경로가 로그인으로 되돌린다.

---

## 아키텍처

### 저장 추상화 (테스트 가능성)

`flutter_secure_storage`는 플랫폼 채널을 쓰므로 위젯/유닛 테스트에서 직접 호출하면 `MissingPluginException`이 난다. 이를 인터페이스 뒤로 숨기고 테스트에서는 인메모리 페이크를 주입한다.

- `TokenStore` (추상 클래스, `mobile/lib/auth/token_store.dart`):
  - `Future<({String? accessToken, String? refreshToken})> read()`
  - `Future<void> write({required String accessToken, required String refreshToken})`
  - `Future<void> clear()`
- `SecureTokenStore implements TokenStore` (`mobile/lib/auth/secure_token_store.dart`): `FlutterSecureStorage`를 래핑. 키는 `accessToken` / `refreshToken`. 생성자에 `FlutterSecureStorage`를 주입 가능하게 하여(기본은 `const FlutterSecureStorage()`) mock으로 키 매핑을 테스트한다.
- 테스트용 `FakeTokenStore`는 테스트 파일 안에 인메모리 구현으로 둔다(프로덕션 코드 아님).

### `AppSession` 변경

- 생성자에 `TokenStore tokenStore` 추가(기본 `SecureTokenStore()`). 필드 `_tokenStore`.
- `bool isRestoring` 상태 추가(기본 `false`). `restore()`가 시작 시 `true`로, 완료 시 `false`로 토글하고 `notifyListeners()`.
- `login()`: userId 디코딩 성공 후 토큰을 메모리에 반영하고 `_persist()` 호출.
- `_doRefresh()`: 회전된 토큰을 메모리에 반영한 뒤 `_persist()` 호출.
- `logout()`: 메모리 정리 후 `_tokenStore.clear()`(best-effort).
- 신규 `restore()`:
  1. `_isRestoring = true; notifyListeners();`
  2. `final stored = await _tokenStore.read();`(best-effort — 예외 시 빈 값 취급)
  3. `accessToken`과 `refreshToken`이 **둘 다** 있으면: 저장 액세스 토큰에서 `decodeUserId`(실패 시 `_tokenStore.clear()` 후 미인증 유지), 성공 시 메모리에 토큰/`userId` 세팅.
  4. `_isRestoring = false; notifyListeners();`
- **모든 저장소 접근(`_persist`/`clear`/`read`)은 best-effort(try-catch)**: 저장 실패가 인증 흐름을 깨지 않게 하고, `restore()`를 호출하지 않는 기존 테스트가 기본 `SecureTokenStore`에서 플러그인 예외로 실패하지 않게 한다.

  ```
  Future<void> _persist() async {
    final access = _accessToken;
    final refresh = _refreshToken;
    if (access == null || refresh == null) return;
    try {
      await _tokenStore.write(accessToken: access, refreshToken: refresh);
    } catch (_) {}
  }
  ```

### 부트스트랩 (`main.dart` / `AuthGate`)

- `main.dart`: `AppSession` 생성 후 `restore()` 호출. Provider `create`에서:

  ```
  ChangeNotifierProvider(
    create: (_) => AppSession(baseUrl: kApiBaseUrl)..restore(),
    child: ...,
  )
  ```

  (`..restore()`는 동기 첫 구간에서 `_isRestoring=true`를 즉시 세팅하므로 첫 빌드가 스피너를 본다.)
- `AuthGate`: `isRestoring`이면 로딩 스피너(`Scaffold(body: Center(child: CircularProgressIndicator()))`), 아니면 기존대로 `isAuthenticated`에 따라 `HomeScreen`/`LoginScreen`.

### 소비자 영향

- `main.dart`, `auth_gate.dart` 수정. 기존 `login_screen`/`home_screen` 등은 변경 없음.
- 기존 테스트: `restore()`를 호출하지 않으므로 `isRestoring`는 기본 `false` 유지 → `AuthGate` 동작 동일. `login/logout/refresh`가 유발하는 저장소 쓰기는 best-effort로 삼켜져 회귀 없음.

---

## 테스트 & 검증

- **`SecureTokenStore`**(`secure_token_store_test.dart`): mock `FlutterSecureStorage`를 주입해 `read`/`write`/`clear`가 올바른 키(`accessToken`/`refreshToken`)로 위임되는지 검증(플랫폼 채널 미접촉).
- **`AppSession`**(`app_session_test.dart` 확장, `FakeTokenStore` 주입):
  - `restore()`가 저장된 두 토큰을 복원하고 userId를 디코딩한다.
  - 저장이 비어 있으면 미인증으로 복원 완료.
  - 저장된 액세스 토큰이 손상(디코딩 실패)이면 storage를 비우고 미인증.
  - `login()`이 두 토큰을 저장한다.
  - `logout()`이 storage를 비운다.
  - `_doRefresh`(401 자동 갱신 경유)가 회전된 토큰을 저장한다.
- **`AuthGate`**(`auth_gate_test.dart` 확장): `restore()` 진행 중 스피너, 저장 토큰이 있으면 복원 후 홈, 없으면 로그인.
- `flutter test` 전체 통과 + `flutter analyze` 클린. 각 단위 TDD.

## 의존성 변경

`mobile/pubspec.yaml`에 `flutter_secure_storage`(`flutter pub add`가 해석하는 최신 호환 버전) 추가. `flutter pub get` 수행.

## 알려진 제약 (구현 후 README 반영)

- 토큰이 이제 기기 secure storage에 영속 저장되어 앱 재시작 후에도 세션이 유지된다. (기존 "메모리 보관 → 재시작 시 로그아웃" 제약 해소.)
- 웹 타겟에서 flutter_secure_storage는 WebCrypto 기반 실험적 구현이다(모바일이 주 타겟).
- 실제 iOS/Android 기기·시뮬레이터에서의 검증은 이 개발 환경 툴체인 부재로 수행되지 않았고 자동 테스트로 갈음한다.

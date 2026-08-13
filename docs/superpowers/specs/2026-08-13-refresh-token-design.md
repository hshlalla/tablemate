# 리프레시 토큰 설계 문서

**작성일:** 2026-08-13
**상태:** 설계 승인됨 (구현 계획 대기)

## 목표

현재 로그인은 액세스 토큰(JWT, 1시간 만료)만 발급하며, 만료되면 사용자가 다시 로그인해야 한다. **Stateful 회전(rotation) 방식의 리프레시 토큰**을 도입해, 액세스 토큰이 만료돼도 모바일 앱이 세션 실행 중 자동으로 액세스 토큰을 갱신하도록 한다. 리프레시 토큰은 DB에 (해시로) 저장·회전·폐기되며, 로그아웃/재사용 감지 시 폐기할 수 있다.

## 설계 결정 (확정)

- **토큰 관리 방식:** Stateful 회전 — 리프레시 토큰을 DB에 해시로 저장, 사용할 때마다 회전, 폐기 가능.
- **모바일 범위:** 리프레시 토큰을 **메모리에만 보관**하고 액세스 토큰 401 시 **자동 갱신**. 기기 영속 저장(secure storage)은 **이번 범위 밖**(별개 후속 항목) — 앱 재시작 시 로그아웃되는 것은 의도된 동작.

## 비목표 (이번 작업에서 하지 않음)

- 기기 영속 저장(`flutter_secure_storage` 등) — 리프레시 토큰은 메모리 보관. 신규 모바일 패키지 추가 없음.
- 채팅 WebSocket의 장시간 연결 중 액세스 토큰 만료 자동 갱신 — 소켓은 생성 시점의 액세스 토큰을 사용. 알려진 제약으로 문서화.
- 회원가입 시 자동 로그인 — `POST /auth/signup`은 기존대로 `{id, email}`만 반환(토큰 없음). 기존 모바일 가입 → 로그인 흐름 보존.

---

## 백엔드 설계

### 토큰 수명 & 형태

- **액세스 토큰:** 기존 JWT 유지(payload `{sub, email}`). 기본 만료를 **15분**으로 단축(`JWT_EXPIRES_IN`, 기본값 `15m`). 모바일의 클라이언트 측 `decodeUserId`는 변경 없이 동작.
- **리프레시 토큰:** JWT가 아닌 **불투명(opaque) 랜덤 토큰**. `crypto.randomBytes(32)`를 hex로 인코딩(64자). 서버는 원문을 저장하지 않고 **sha256 해시(hex)만** DB에 저장. 기본 만료 **30일**(`REFRESH_EXPIRES_IN`, 기본값 `30d`).
- 리프레시 토큰 해싱에 **bcrypt가 아닌 Node 내장 `crypto`(sha256)** 사용. 이유: (1) 고엔트로피 랜덤 토큰이라 sha256으로 충분하고 해시로 조회(lookup)가 가능해야 함(bcrypt는 salt 때문에 조회 불가), (2) 새 로직이 이 개발 샌드박스의 bcrypt 코드서명 이슈에 영향받지 않아 테스트가 실제로 실행됨.

### 데이터 모델

신규 엔티티 `RefreshToken` (`backend/src/auth/refresh-token.entity.ts`, 테이블 `refresh_tokens`):

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | uuid PK | |
| `userId` | string, index | 소유 사용자 |
| `tokenHash` | string, unique | 원문 리프레시 토큰의 sha256 hex |
| `expiresAt` | timestamp | 만료 시각 |
| `revokedAt` | timestamp, nullable | 폐기/회전 시각 (null이면 활성) |
| `createdAt` | CreateDateColumn | |

### 엔드포인트

- `POST /auth/login` — 응답을 `{ accessToken }` → **`{ accessToken, refreshToken }`**로 확장. 로그인 성공 시 새 리프레시 토큰을 발급·저장.
- `POST /auth/refresh` (신규) — body `{ refreshToken }`. 검증·회전 후 **`{ accessToken, refreshToken }`**(둘 다 새 값) 반환. 무효/만료/재사용 시 **401 Unauthorized**.
- `POST /auth/logout` (신규) — body `{ refreshToken }`. 해당 리프레시 토큰을 폐기(`revokedAt` 설정). 성공 시 **204 No Content**. 이미 없는/무효한 토큰이어도 204(멱등).
- `POST /auth/signup` — **변경 없음** (`{id, email}` 반환).

### 회전 & 재사용 감지 로직 (`RefreshTokensService.rotate`)

1. 제출된 원문 토큰을 sha256 해시하여 `tokenHash`로 조회.
2. **행이 없으면** → `UnauthorizedException`.
3. **행이 있으나 이미 `revokedAt`이 설정됨**(폐기된 토큰의 재제출 = 재사용/탈취 의심) → 해당 `userId`의 **모든 활성 리프레시 토큰을 폐기**(`revokeAllForUser`) 후 `UnauthorizedException`.
4. **행이 있으나 `expiresAt`이 지남** → `UnauthorizedException`.
5. **정상** → 옛 토큰 행에 `revokedAt` 설정(회전), 새 리프레시 토큰 발급·저장, `{ userId, newRawToken }` 반환.

### 서비스 구조 (테스트 가능성)

- **`RefreshTokensService`** (신규, `backend/src/auth/refresh-tokens.service.ts`): `crypto` + TypeORM 리포지토리만 사용, **bcrypt를 import하지 않음**.
  - `issue(userId: string): Promise<string>` — 랜덤 원문 토큰 생성, 해시·만료시각과 함께 저장, 원문 반환.
  - `rotate(rawToken: string): Promise<{ userId: string; refreshToken: string }>` — 위 회전/재사용 감지 로직.
  - `revoke(rawToken: string): Promise<void>` — 해시로 조회해 `revokedAt` 설정(없으면 무시, 멱등).
  - `revokeAllForUser(userId: string): Promise<void>` — 유저의 활성 토큰 전부 `revokedAt` 설정.
  - **독자 spec(`refresh-tokens.service.spec.ts`)으로 완전 테스트되며, 이 샌드박스에서 실제 실행됨.**
- **`AuthService`** (기존): `login`에서 `refreshTokensService.issue(user.id)`를 호출해 리프레시 토큰을 함께 반환. 신규 `refresh(rawToken)`(→ `rotate` 후 새 액세스 JWT 서명 → `{accessToken, refreshToken}`), `logout(rawToken)`(→ `revoke`) 메서드 추가. *AuthService는 bcrypt를 import하므로 `auth.service.spec.ts`는 기존과 동일하게 이 샌드박스에서 로드 불가 — 그러나 회전/재사용의 핵심 로직은 `RefreshTokensService` spec이 커버한다.*
- **`AuthController`** (기존): `refresh`, `logout` 라우트 추가. `AuthModule`은 `TypeOrmModule.forFeature([RefreshToken])`와 `RefreshTokensService`(providers)를 추가.

### 시간 처리

`expiresAt`/`revokedAt`은 `RefreshTokensService` 내부에서 `new Date()`로 계산. 테스트에서는 만료 케이스를 위해 과거/미래 시각을 직접 구성한 엔티티를 mock 리포지토리가 반환하도록 한다(서비스에 시간 주입은 하지 않되, 만료 판정은 조회된 `expiresAt`과 현재 시각 비교로 검증).

---

## 모바일 설계 (신규 패키지 없음)

### 에러에 상태코드 노출

- `ApiException`에 `int? statusCode` 필드 추가.
- `ApiClient.get`/`post`가 에러 상태(>=400)로 던질 때 `statusCode`를 실어 던짐. 비-JSON 응답 방어 경로도 상태코드를 전달.

### `AuthenticatedApiClient` (신규)

`mobile/lib/api/authenticated_api_client.dart`. 순수 함수 주입으로 인증·자동 갱신을 캡슐화:

```
AuthenticatedApiClient(
  ApiClient api,
  String Function() currentAccessToken,
  Future<String> Function() refreshAccessToken,
)
```

- `get(path)` / `post(path, body)`: 현재 액세스 토큰을 붙여 `api` 호출. `ApiException`의 `statusCode == 401`이면 `refreshAccessToken()`를 1회 호출한 뒤 **새 토큰으로 한 번만 재시도**. 재시도도 실패하면 그대로 throw. 401이 아니면 즉시 rethrow.

### `AppSession` 변경

- `_refreshToken` 보관. `login()`이 액세스+리프레시 토큰을 모두 저장.
- `AuthRepository.login`이 두 토큰을 반환하도록 변경(`refresh`/`logout` 메서드 추가). 반환 형태는 Dart record `({String accessToken, String refreshToken})`.
- `_refresh()`: **single-flight**(진행 중이면 동일 Future를 await) 가드로 동시 401 다발을 한 번의 갱신으로 합침. `AuthRepository.refresh(_refreshToken)` 호출 → 액세스·리프레시 토큰 갱신 → 새 액세스 토큰 반환. 실패(리프레시 토큰 만료/폐기 → 예외) 시 `logout()` 처리하고 예외를 전파(→ `AuthGate`가 로그인 화면으로 전환).
- `discoverRepository`/`matchesRepository`는 이제 `AuthenticatedApiClient`를 받도록 생성자 변경. `AppSession`이 `AuthenticatedApiClient(_apiClient, () => _accessToken!, _refresh)`를 만들어 주입.
- `logout()`: 로컬 상태 정리 + 백엔드 `POST /auth/logout`(리프레시 토큰 폐기) 호출(실패는 무시, best-effort).

### 소비자 영향

- `DiscoverRepository`/`MatchesRepository`: 생성자가 `(ApiClient, String token)` → `(AuthenticatedApiClient)`로 변경. 내부 호출은 `authClient.get/post`로. 기존 위젯/유닛 테스트는 mock 대상만 바뀜.
- 채팅 소켓(`buildChatSocketClient`): 생성 시점의 현재 액세스 토큰 사용 — 변경 없음(범위 밖).

---

## 테스트 & 검증

- **백엔드:** 신규 `refresh-tokens.service.spec.ts`(발급/회전/재사용감지/폐기, **이 샌드박스에서 실행됨**), `auth.controller.spec.ts`에 refresh/logout 라우트 위임 테스트 추가. `npm run test`(auth.service.spec만 기존 bcrypt 이슈로 실패) + `npm run build`.
- **모바일:** 신규 `authenticated_api_client_test.dart`(401→갱신→재시도, 비401 rethrow), `app_session_test.dart`에 refresh/single-flight/refresh 실패 시 logout 테스트 추가. 기존 `login_screen_test`/`auth_gate_test`의 로그인 응답 mock을 두 토큰 형태로 갱신. `flutter test` + `flutter analyze`.
- 각 단위는 TDD(실패 테스트 → 최소 구현 → 통과 → 커밋).

## 환경 변수

`.env.example`에 추가/변경:

```
JWT_EXPIRES_IN=15m          # 1h → 15m 로 단축
REFRESH_EXPIRES_IN=30d      # 신규
```

## 알려진 제약 (구현 후 README 반영)

- 리프레시 토큰은 모바일 메모리에만 보관 — 앱 재시작 시 로그아웃(영속 저장은 별개 후속 항목).
- 채팅 WebSocket은 연결 시점의 액세스 토큰을 사용하며, 장시간 연결 중 만료를 자동 갱신하지 않는다.

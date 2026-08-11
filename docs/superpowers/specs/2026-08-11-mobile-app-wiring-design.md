# TableMate — 모바일 앱 내비게이션 와이어링 설계

- 작성일: 2026-08-11
- 상태: 승인됨 (사용자 승인)
- 다음 단계: writing-plans 스킬로 구현 계획 수립

## 배경

서브프로젝트 1(기반 리서치)에서 백엔드(NestJS)와 모바일(Flutter) 골격을 각각 구현했다. 백엔드는 회원가입/로그인/프로필/스와이프/매칭/채팅/맛집 API가 모두 동작하고, 모바일도 로그인·회원가입·discover(스와이프)·matches·chat 5개 화면과 각 리포지토리가 개별적으로 구현·테스트되어 있다.

다만 `mobile/lib/main.dart`가 `flutter create`의 기본 카운터 앱 그대로 남아 있어, 화면들이 하나의 앱으로 연결되어 있지 않다. 서브프로젝트 1의 최종 전체 브랜치 리뷰에서 이 문제와 함께, main.dart 와이어링만으로는 앱이 실제로 동작하지 않는다는 점도 함께 드러났다 — 스와이프 후보를 조회하는 API 자체가 백엔드에 없고, 클라이언트가 로그인 후 자신의 user id를 알아낼 방법도 없었다.

이 문서는 그 최종 리뷰에서 식별된 갭을 메워, `flutter run`으로 회원가입 → 로그인 → 스와이프 → 매칭 → 채팅까지 실제로 동작하는 앱을 만드는 작업을 다룬다.

## 이번 서브프로젝트의 범위

- 백엔드: 스와이프 후보 목록 API(`GET /swipes/candidates`) 신규 추가
- 모바일: `main.dart`에 로그인 게이트 + 하단 탭(Discover/Matches) 내비게이션 구조 추가
- 모바일: 세션 상태 관리(`AppSession`, `provider` 패키지 활용) 도입, JWT에서 user id 로컬 디코딩
- 모바일: 서브프로젝트 1 최종 리뷰가 "이 작업에 묶어서 처리하라"고 명시적으로 권고한 항목 반영
  - `ApiClient`에 `get()` 추가, `MatchesRepository`를 직접 `http.get` 호출 대신 `ApiClient` 경유로 이관
  - baseURL을 앱 전체에서 한 곳(`main.dart`)으로 단일화
  - `ChatSocketClient`/`ChatScreen`이 서버의 `history`/`error` 이벤트를 처리하도록 보강 (현재는 `history`가 수신되어도 버려져 기존 대화 내역이 보이지 않음)
  - `MatchesScreen`에 에러 처리 추가 (현재는 요청 실패 시 조용히 빈 화면이 됨)

**범위 밖:**
- 리프레시 토큰 (서브프로젝트 3에서 다룰 예정, 기존 계획대로 유지)
- 로그인 토큰의 기기 영속 저장 (앱 재시작 시 로그아웃되는 것이 이번 스코프의 의도된 동작)
- 프로필 편집 화면, 채팅 read-receipt/typing indicator 등 신규 기능
- Android/iOS 실기기·에뮬레이터 실행 검증 (이 개발 환경에 해당 툴체인이 없음 — Task 11~13과 동일한 제약)

## 검토한 대안과 결정

### 내비게이션/상태 관리 스택

| 후보 | 장단점 |
|---|---|
| **Navigator 1.0(`Navigator.push`) + `provider`** (채택) | 화면 5개 규모에 적합, 새 의존성 불필요(`provider`는 서브프로젝트 1에서 이미 추가됨), 기존 생성자 주입 패턴과 자연스럽게 이어짐 |
| `go_router` + Riverpod 등 정식 스택 | 선언적 라우팅·딥링크 등 강력하지만 새 의존성 2개 이상 필요, 화면 5개짜리 스켈레톤 단계에는 과함(YAGNI 위반) |
| `provider` 없이 생성자 인자로만 세션 전달 | 새 의존성은 없지만, 화면이 늘어날수록 토큰을 계속 손으로 전달해야 해서 전달 체인이 길어짐 |

**결정:** `Navigator.push(MaterialPageRoute(...))` + `provider`의 `AppSession`. 새 의존성 없이 서브프로젝트 1이 미리 깔아둔 패키지를 의도대로 사용한다.

### 내 user id를 알아내는 방법

| 후보 | 장단점 |
|---|---|
| **클라이언트에서 JWT payload 로컬 디코딩** (채택) | 새 백엔드 엔드포인트 불필요, 네트워크 왕복 없음. JWT는 `{sub, email}`을 이미 담고 있음(`backend/src/auth/auth.service.ts`) |
| 백엔드에 `GET /users/me` 신규 추가 | 향후 프로필 등 추가 정보를 함께 내려줄 확장성은 있으나, 지금은 id/email만 반환하는 엔드포인트 하나가 늘어날 뿐 |

**결정:** 클라이언트 로컬 디코딩. `mobile/lib/auth/jwt_decoder.dart`에 순수 함수로 구현(서명 검증은 하지 않음 — 자기 자신이 방금 발급받은 토큰이므로 신뢰 가능).

### 스와이프 후보 목록 제외 규칙

**결정:** 본인 + 이미 스와이프한 사람(좋아요/패스 무관) 전부 제외. 프로필이 있는 사용자만 후보로 노출. 최대 50건으로 상한을 둔다(페이지네이션은 범위 밖).

## 아키텍처

### 백엔드: `GET /swipes/candidates`

- `SwipesService.listSwipedTargetIds(userId): Promise<string[]>` — 신규. 내가 이미 스와이프한 `targetUserId` distinct 목록.
- `ProfilesService.listCandidates(excludeUserId: string, excludeTargetIds: string[]): Promise<Profile[]>` — 신규. 본인과 제외 목록을 뺀 프로필을 최대 50건 조회.
- `SwipesController.listCandidates`가 두 서비스를 조합 (기존 `SwipesController.create`가 `SwipesService`+`MatchesService`를 조합하던 패턴과 동일한 방식). 응답: `{ candidates: [{ userId, displayName, bio }] }`.
- `SwipesModule`이 `ProfilesModule`을 import (`profiles`는 `swipes`를 모르므로 순환 의존 없음, `forwardRef` 불필요).

### 모바일: 세션 레이어

```dart
class AppSession extends ChangeNotifier {
  String? get accessToken;
  String? get userId;                    // jwt_decoder.decodeUserId(accessToken)로 로그인 시점에 채움
  bool get isAuthenticated;

  AuthRepository get authRepository;
  DiscoverRepository get discoverRepository;  // accessToken 바인딩, 지연 생성
  MatchesRepository get matchesRepository;    // ApiClient.get() 경유로 변경됨

  Future<void> login(String email, String password);  // 토큰 저장 + userId 디코딩 + notifyListeners
  void logout();                                        // 세션 초기화 + notifyListeners
  ChatSocketClient buildChatSocketClient();             // 화면 하나당 소켓 하나, 매번 새로 생성
}
```

- `main.dart`에 `const String kApiBaseUrl = 'http://localhost:3000';` 한 곳만 정의, `ApiClient`/`ChatSocketClient` 생성 시 이 값을 사용.
- `ChangeNotifierProvider(create: (_) => AppSession(...))`로 앱 최상단에 제공.
- 화면은 `context.watch<AppSession>()`(반응형) 또는 `context.read<AppSession>()`(1회성 액션)로 접근.

### 모바일: 화면 흐름

```
main.dart
 └─ AuthGate (MaterialApp.home)
      ├─ AppSession.isAuthenticated == false → LoginScreen
      │     └─ "회원가입" → SignupScreen → 성공 시 안내 메시지와 함께 LoginScreen으로 pop (자동 로그인 없음)
      └─ AppSession.isAuthenticated == true  → HomeScreen (하단 탭바)
            ├─ [Discover 탭] DiscoverScreen
            │     - 진입 시 discoverRepository.fetchCandidates() 로딩
            │     - 한 명씩 노출, 좋아요/패스 성공 시 큐에서 다음 후보로 전진
            │     - 큐 소진 시 "더 이상 후보가 없습니다" 정적 문구 (자동 재조회 없음)
            ├─ [Matches 탭] MatchesScreen
            │     - 매칭 목록, 항목 탭 → Navigator.push(ChatScreen(matchId, socketClient: session.buildChatSocketClient()))
            └─ AppBar 로그아웃 버튼 → AppSession.logout() → AuthGate가 자동으로 LoginScreen 표시
```

`AuthGate`는 `context.watch<AppSession>()`으로 인증 상태를 구독하는 얇은 위젯이라, 로그인/로그아웃 시 `notifyListeners()`만으로 화면이 자동 전환된다 (수동 라우트 이름 관리 불필요).

## 에러 처리

기존 `LoginScreen`/`DiscoverScreen`(Task 11/12에서 확립)에 쓰인 `_errorMessage` 상태 필드 + 빨간 `Text` 렌더링 패턴을 전 화면에 일관되게 적용한다:

- `MatchesScreen`: 현재 에러 처리가 전혀 없어 요청 실패 시 조용히 빈 화면이 되는 문제를 이 패턴으로 수정.
- `ChatScreen`: `ChatSocketClient`에 `onHistory`/`onError`/연결 실패 콜백을 추가하고, `history` 이벤트로 `_messages`를 초기화(현재는 수신되어도 버려짐), `error`/연결 실패 시 동일한 에러 텍스트로 노출.

`ChatScreen`이 자신에게 주입된 `ChatSocketClient`를 계속 소유하고 `dispose()`에서 폐기하는 현재 구조는 유지한다 — "화면 하나당 소켓 하나, 화면과 함께 생성·폐기"라는 규칙을 `AppSession.buildChatSocketClient()`로 명시화할 뿐, 동작 자체는 바뀌지 않는다.

## 테스트 전략 (기존 TDD 컨벤션 유지)

**백엔드**
- `SwipesService.listSwipedTargetIds` 유닛 테스트
- `ProfilesService.listCandidates` 유닛 테스트
- `swipes.controller.spec.ts`에 `GET /swipes/candidates` 케이스 추가

**모바일**
- `jwt_decoder.dart` 순수 함수 유닛 테스트 (정상/손상된 토큰)
- `AppSession` 테스트: `login()`/`logout()` 후 상태 및 `notifyListeners` 확인
- `ApiClient.get()` 유닛 테스트 (기존 `post()` 테스트와 동일한 패턴)
- `MatchesRepository` 테스트를 `ApiClient.get()` 모킹으로 갱신
- `AuthGate` 위젯 테스트: 인증 상태에 따라 `LoginScreen`/`HomeScreen` 노출
- `DiscoverScreen` 후보 큐 순회 테스트 확장 (여러 후보, 소진 시 빈 상태)
- `MatchesScreen` 에러 처리 테스트 신규 추가
- `ChatSocketClient`/`ChatScreen`의 history/error 배선은 Task 13과 동일하게 실제 소켓 연결이 필요해 위젯 테스트 대상에서 제외, `flutter analyze` 타입체크로 갈음

## Self-Review 결과

- **스펙 커버리지:** 백엔드 후보 API, 모바일 세션/설정 레이어, 내비게이션 구조, 에러 처리, 테스트 전략 — 브레인스토밍에서 승인받은 5개 섹션을 모두 반영함
- **플레이스홀더 스캔:** 없음
- **일관성 확인:** `ApiClient.get()`(신규) → `MatchesRepository` 이관 → `AppSession.matchesRepository`까지 인터페이스가 일관되게 이어짐. `SwipesService.listSwipedTargetIds` → `ProfilesService.listCandidates` → `SwipesController.listCandidates` → 모바일 `DiscoverRepository.fetchCandidates`까지 필드명(`userId`, `displayName`, `bio`)이 일관됨

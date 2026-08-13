# 토큰 영속 저장 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 로그인/리프레시 토큰을 기기 secure storage에 영속 저장하고, 콜드 스타트 시 복원해 앱을 재시작해도 로그인 세션이 유지되도록 한다.

**Architecture:** `flutter_secure_storage`를 `TokenStore` 인터페이스 뒤에 숨겨(테스트는 인메모리 페이크 주입) `AppSession`이 로그인/회전 시 토큰을 저장하고 `restore()`로 복원한다. 복원 시 저장된 액세스 토큰에서 userId를 로컬 디코딩하고, 만료는 기존 401 자동 갱신이 처리한다. `AuthGate`는 복원 중 로딩 스피너를 보인다.

**Tech Stack:** Flutter(stable), `provider` 6.x(기존), `flutter_secure_storage`(신규), `mocktail`(dev, 기존).

**Spec:** `docs/superpowers/specs/2026-08-14-token-persistence-design.md`

## Global Constraints

- 모든 저장소 접근(`read`/`write`/`clear`)은 `AppSession`에서 best-effort(try-catch)로 감싼다: 저장 실패가 인증 흐름을 깨지 않고, `restore()`를 호출하지 않는 기존 테스트가 기본 `SecureTokenStore`의 플랫폼 채널 예외로 실패하지 않게 한다.
- `AppSession.isRestoring`의 기본값은 `false`. `restore()`만 이를 `true`→`false`로 토글한다(따라서 `restore()`를 부르지 않는 기존 테스트는 회귀 없음).
- 복원은 저장된 두 토큰(액세스+리프레시)이 **모두** 있을 때만 수행한다. userId는 저장된 액세스 토큰에서 로컬 디코딩한다(네트워크 없음).
- 모바일 flutter 명령은 `export PATH="/Users/studio/development/flutter/bin:$PATH"` 후 `cd mobile`에서 실행한다.
- 각 로직 단위는 TDD: 실패 테스트 → 최소 구현 → 통과 → 커밋.

---

## 파일 구조 개요

```
mobile/
  pubspec.yaml                              (수정: flutter_secure_storage 추가)
  lib/
    auth/
      token_store.dart                      (신규: 추상 TokenStore)
      secure_token_store.dart               (신규: FlutterSecureStorage 래퍼)
    app_session.dart                        (수정: tokenStore, isRestoring, restore, persist)
    auth_gate.dart                          (수정: 복원 로딩 상태)
    main.dart                               (수정: restore() 배선)
  test/
    auth/secure_token_store_test.dart       (신규)
    app_session_test.dart                   (수정: FakeTokenStore + restore/persist 테스트)
    auth_gate_test.dart                     (수정: 복원 로딩/복원-후-홈 테스트)
```

---

### Task 1: 의존성 추가 + `TokenStore` / `SecureTokenStore`

**Files:**
- Modify: `mobile/pubspec.yaml` (via `flutter pub add`)
- Create: `mobile/lib/auth/token_store.dart`
- Create: `mobile/lib/auth/secure_token_store.dart`
- Create: `mobile/test/auth/secure_token_store_test.dart`

**Interfaces:**
- Consumes: `flutter_secure_storage`의 `FlutterSecureStorage`
- Produces: `abstract class TokenStore { Future<({String? accessToken, String? refreshToken})> read(); Future<void> write({required String accessToken, required String refreshToken}); Future<void> clear(); }` — Task 2(`AppSession`)가 소비. `SecureTokenStore implements TokenStore`.

- [ ] **Step 1: 패키지 추가**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter pub add flutter_secure_storage`
Expected: `pubspec.yaml`/`pubspec.lock` 갱신, `flutter pub get` 성공.

- [ ] **Step 2: 추상 인터페이스 작성**

`mobile/lib/auth/token_store.dart`:

```dart
/// Persists the auth token pair. Abstracted so tests can inject an
/// in-memory fake instead of touching platform secure storage.
abstract class TokenStore {
  Future<({String? accessToken, String? refreshToken})> read();
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clear();
}
```

- [ ] **Step 3: 실패하는 테스트 작성**

`mobile/test/auth/secure_token_store_test.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/auth/secure_token_store.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('SecureTokenStore', () {
    test('read returns the access and refresh tokens by key', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.read(key: 'accessToken'))
          .thenAnswer((_) async => 'a-1');
      when(() => storage.read(key: 'refreshToken'))
          .thenAnswer((_) async => 'r-1');
      final store = SecureTokenStore(storage: storage);

      final result = await store.read();

      expect(result.accessToken, 'a-1');
      expect(result.refreshToken, 'r-1');
    });

    test('write persists both tokens under their keys', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
      final store = SecureTokenStore(storage: storage);

      await store.write(accessToken: 'a-1', refreshToken: 'r-1');

      verify(() => storage.write(key: 'accessToken', value: 'a-1')).called(1);
      verify(() => storage.write(key: 'refreshToken', value: 'r-1')).called(1);
    });

    test('clear deletes both token keys', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      final store = SecureTokenStore(storage: storage);

      await store.clear();

      verify(() => storage.delete(key: 'accessToken')).called(1);
      verify(() => storage.delete(key: 'refreshToken')).called(1);
    });
  });
}
```

- [ ] **Step 4: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth/secure_token_store_test.dart`
Expected: FAIL (`Target of URI doesn't exist: 'package:mobile/auth/secure_token_store.dart'`)

- [ ] **Step 5: 구현**

`mobile/lib/auth/secure_token_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'token_store.dart';

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'accessToken';
  static const _refreshKey = 'refreshToken';

  @override
  Future<({String? accessToken, String? refreshToken})> read() async {
    final accessToken = await _storage.read(key: _accessKey);
    final refreshToken = await _storage.read(key: _refreshKey);
    return (accessToken: accessToken, refreshToken: refreshToken);
  }

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
```

- [ ] **Step 6: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth/secure_token_store_test.dart`
Expected: PASS (3/3)

- [ ] **Step 7: 전체 스위트/analyze 회귀 없는지 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, analyze 클린(신규 패키지가 기존 테스트를 깨지 않음).

- [ ] **Step 8: 커밋**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/auth/token_store.dart mobile/lib/auth/secure_token_store.dart mobile/test/auth/secure_token_store_test.dart
git commit -m "feat: add TokenStore abstraction backed by flutter_secure_storage"
```

---

### Task 2: `AppSession` — 영속화 + 복원

**Files:**
- Modify: `mobile/lib/app_session.dart`
- Modify: `mobile/test/app_session_test.dart`

**Interfaces:**
- Consumes: `TokenStore`(Task 1)
- Produces: `AppSession({required String baseUrl, ApiClient? apiClient, TokenStore? tokenStore})`, `bool get isRestoring`, `Future<void> restore()`. Task 3(`AuthGate`/`main`)이 소비.

- [ ] **Step 1: 실패하는 테스트 작성 (`app_session_test.dart` 상단에 FakeTokenStore 추가 + 새 그룹)**

파일 상단 import 아래(`_fakeJwt` 헬퍼 위/아래 아무 곳)에 페이크를 추가한다:

```dart
class FakeTokenStore implements TokenStore {
  FakeTokenStore({this.accessToken, this.refreshToken});
  String? accessToken;
  String? refreshToken;
  int writes = 0;
  int clears = 0;

  @override
  Future<({String? accessToken, String? refreshToken})> read() async =>
      (accessToken: accessToken, refreshToken: refreshToken);

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    writes++;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    clears++;
  }
}
```

그리고 파일 상단 import에 다음을 추가:

```dart
import 'package:mobile/auth/token_store.dart';
```

파일 맨 끝(마지막 `}` 앞)에 새 그룹을 추가한다:

```dart
  group('AppSession persistence', () {
    test('restore loads stored tokens and decodes the user id', () async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      final store = FakeTokenStore(accessToken: token, refreshToken: 'r-1');
      final session =
          AppSession(baseUrl: 'http://localhost:3000', tokenStore: store);

      await session.restore();

      expect(session.isAuthenticated, isTrue);
      expect(session.userId, 'user-1');
      expect(session.isRestoring, isFalse);
    });

    test('restore leaves the session unauthenticated when nothing is stored',
        () async {
      final store = FakeTokenStore();
      final session =
          AppSession(baseUrl: 'http://localhost:3000', tokenStore: store);

      await session.restore();

      expect(session.isAuthenticated, isFalse);
      expect(session.isRestoring, isFalse);
    });

    test('restore clears storage when the stored access token is corrupt',
        () async {
      final store = FakeTokenStore(accessToken: 'not-a-jwt', refreshToken: 'r-1');
      final session =
          AppSession(baseUrl: 'http://localhost:3000', tokenStore: store);

      await session.restore();

      expect(session.isAuthenticated, isFalse);
      expect(store.accessToken, isNull);
      expect(store.clears, 1);
    });

    test('login persists both tokens', () async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      final store = FakeTokenStore();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'accessToken': token, 'refreshToken': 'r-1'}),
          200,
        );
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
        tokenStore: store,
      );

      await session.login('jane@x.com', 'pw');

      expect(store.accessToken, token);
      expect(store.refreshToken, 'r-1');
      expect(store.writes, 1);
    });

    test('logout clears the store', () async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      final store = FakeTokenStore();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'accessToken': token, 'refreshToken': 'r-1'}),
          200,
        );
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
        tokenStore: store,
      );
      await session.login('jane@x.com', 'pw');

      session.logout();
      await Future<void>.delayed(Duration.zero); // flush best-effort clear

      expect(store.clears, 1);
      expect(store.accessToken, isNull);
    });

    test('a 401 refresh persists the rotated tokens', () async {
      final loginAccess = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      final freshAccess = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      final store = FakeTokenStore();
      var candidatesCalls = 0;
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path == '/auth/login') {
          return http.Response(
            jsonEncode({'accessToken': loginAccess, 'refreshToken': 'r-1'}),
            200,
          );
        }
        if (path == '/auth/refresh') {
          return http.Response(
            jsonEncode({'accessToken': freshAccess, 'refreshToken': 'r-2'}),
            200,
          );
        }
        if (path == '/swipes/candidates') {
          candidatesCalls++;
          if (candidatesCalls == 1) {
            return http.Response(jsonEncode({'message': 'expired'}), 401);
          }
          return http.Response(jsonEncode({'candidates': []}), 200);
        }
        return http.Response(jsonEncode({'message': 'not found'}), 404);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
        tokenStore: store,
      );
      await session.login('jane@x.com', 'pw');

      await session.discoverRepository.fetchCandidates();

      expect(store.accessToken, freshAccess);
      expect(store.refreshToken, 'r-2');
    });
  });
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/app_session_test.dart`
Expected: FAIL (컴파일 에러 — `tokenStore` 파라미터/`isRestoring`/`restore` 미정의)

- [ ] **Step 3: 구현 (`app_session.dart` 수정)**

import 블록에 추가:

```dart
import 'auth/token_store.dart';
import 'auth/secure_token_store.dart';
```

생성자와 필드를 교체:

```dart
  AppSession({
    required String baseUrl,
    ApiClient? apiClient,
    TokenStore? tokenStore,
  })  : _baseUrl = baseUrl,
        _apiClient = apiClient ?? ApiClient(baseUrl: baseUrl),
        _tokenStore = tokenStore ?? SecureTokenStore();

  final String _baseUrl;
  final ApiClient _apiClient;
  final TokenStore _tokenStore;

  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  bool _isRestoring = false;
  Future<String>? _inFlightRefresh;
  DiscoverRepository? _discoverRepository;
  MatchesRepository? _matchesRepository;

  bool get isAuthenticated => _accessToken != null;
  bool get isRestoring => _isRestoring;
  String? get userId => _userId;
```

`login`의 끝(`notifyListeners();` 뒤)에 영속화 추가:

```dart
  Future<void> login(String email, String password) async {
    final tokens = await authRepository.login(email, password);
    final userId = decodeUserId(tokens.accessToken);
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
    _userId = userId;
    notifyListeners();
    await _persist();
  }
```

`_doRefresh`의 성공 경로에 영속화 추가:

```dart
  Future<String> _doRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      throw StateError('AppSession: not authenticated');
    }
    try {
      final tokens = await authRepository.refresh(refreshToken);
      _accessToken = tokens.accessToken;
      _refreshToken = tokens.refreshToken;
      await _persist();
      return tokens.accessToken;
    } catch (_) {
      logout();
      rethrow;
    }
  }
```

`logout`에 저장소 삭제 추가(기존 서버 폐기 호출 아래):

```dart
  void logout() {
    final refreshToken = _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    _discoverRepository = null;
    _matchesRepository = null;
    notifyListeners();
    if (refreshToken != null) {
      // Best-effort server-side revocation; ignore failures.
      authRepository.logout(refreshToken).catchError((_) {});
    }
    _clearStore();
  }
```

클래스 끝(`buildChatSocketClient` 아래)에 복원/영속 헬퍼 추가:

```dart
  Future<void> restore() async {
    _isRestoring = true;
    notifyListeners();
    try {
      final stored = await _tokenStore.read();
      final access = stored.accessToken;
      final refresh = stored.refreshToken;
      if (access != null && refresh != null) {
        final userId = decodeUserId(access);
        _accessToken = access;
        _refreshToken = refresh;
        _userId = userId;
      }
    } on FormatException {
      await _clearStore();
    } catch (_) {
      // Storage read failure -> treat as no stored session.
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final access = _accessToken;
    final refresh = _refreshToken;
    if (access == null || refresh == null) return;
    try {
      await _tokenStore.write(accessToken: access, refreshToken: refresh);
    } catch (_) {}
  }

  Future<void> _clearStore() async {
    try {
      await _tokenStore.clear();
    } catch (_) {}
  }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/app_session_test.dart`
Expected: PASS (기존 6개 + 신규 6개, 총 12개)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/app_session.dart mobile/test/app_session_test.dart
git commit -m "feat: persist and restore auth tokens in AppSession"
```

---

### Task 3: `AuthGate` 로딩 상태 + `main.dart` 복원 배선

**Files:**
- Modify: `mobile/lib/auth_gate.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/test/auth_gate_test.dart`

**Interfaces:**
- Consumes: `AppSession.isRestoring`/`restore()`(Task 2)
- Produces: 없음(조립 지점)

- [ ] **Step 1: 실패하는 테스트 작성 (`auth_gate_test.dart` 상단에 페이크 추가 + 새 테스트)**

파일 상단 import에 추가:

```dart
import 'package:mobile/auth/token_store.dart';
```

`_fakeJwt` 헬퍼 근처에 두 페이크를 추가:

```dart
class FakeTokenStore implements TokenStore {
  FakeTokenStore({this.accessToken, this.refreshToken});
  String? accessToken;
  String? refreshToken;

  @override
  Future<({String? accessToken, String? refreshToken})> read() async =>
      (accessToken: accessToken, refreshToken: refreshToken);

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> clear() async {}
}

class BlockingTokenStore implements TokenStore {
  final _never = Completer<({String? accessToken, String? refreshToken})>();

  @override
  Future<({String? accessToken, String? refreshToken})> read() => _never.future;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> clear() async {}
}
```

(파일 상단에 `import 'dart:async';`를 추가해 `Completer`를 사용한다.)

`void main() {` 안, 기존 테스트 뒤에 두 테스트를 추가:

```dart
  testWidgets('shows a loading indicator while restoring', (tester) async {
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      tokenStore: BlockingTokenStore(),
    );
    session.restore(); // never completes -> stays restoring

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSession>.value(
        value: session,
        child: const MaterialApp(home: AuthGate()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('restores a stored session straight into the home screen',
      (tester) async {
    final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
    final mockClient = MockClient((request) async {
      if (request.url.path == '/swipes/candidates') {
        return http.Response(jsonEncode({'candidates': []}), 200);
      }
      if (request.url.path == '/matches') {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response(jsonEncode({'message': 'not found'}), 404);
    });
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      apiClient: ApiClient(
        baseUrl: 'http://localhost:3000',
        httpClient: mockClient,
      ),
      tokenStore: FakeTokenStore(accessToken: token, refreshToken: 'r-1'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSession>.value(
        value: session,
        child: const MaterialApp(home: AuthGate()),
      ),
    );

    await session.restore();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('logoutButton')), findsOneWidget);
  });
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth_gate_test.dart`
Expected: FAIL (`AuthGate`가 아직 `isRestoring`을 반영하지 않아 로딩 스피너 테스트 실패)

- [ ] **Step 3: `AuthGate` 수정**

`mobile/lib/auth_gate.dart` 전체를 교체:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_session.dart';
import 'auth/login_screen.dart';
import 'home_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    if (session.isRestoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return session.isAuthenticated
        ? const HomeScreen()
        : LoginScreen(session: context.read<AppSession>());
  }
}
```

- [ ] **Step 4: `main.dart` 수정 — 부팅 시 복원**

`mobile/lib/main.dart`의 `ChangeNotifierProvider` `create`를 교체:

```dart
      create: (_) => AppSession(baseUrl: kApiBaseUrl)..restore(),
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth_gate_test.dart`
Expected: PASS (기존 1개 + 신규 2개)

- [ ] **Step 6: 전체 스위트 + analyze**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, analyze 클린.

- [ ] **Step 7: 커밋**

```bash
git add mobile/lib/auth_gate.dart mobile/lib/main.dart mobile/test/auth_gate_test.dart
git commit -m "feat: restore persisted session on startup with a loading gate"
```

---

### Task 4: 검증 + README 갱신

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: 없음
- Produces: 없음

- [ ] **Step 1: 모바일 전체 스위트 + analyze**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, 클린.

- [ ] **Step 2: 백엔드 회귀 확인(변경 없음이지만 확인)**

Run: `cd backend && npm run test`
Expected: 이전과 동일 — `auth.service.spec.ts`만 이 샌드박스의 bcrypt 이슈로 실패, 나머지 통과.

- [ ] **Step 3: README 갱신**

`README.md`를 Read한 뒤:

- "현재 상태 / Known limitations"의 첫 항목(`로그인 토큰은 메모리에만 보관됩니다 ...`)을 다음으로 교체한다: 토큰이 이제 기기 secure storage(`flutter_secure_storage`)에 영속 저장되어 앱을 재시작해도 세션이 유지된다. 콜드 스타트 시 저장된 액세스 토큰에서 userId를 로컬 디코딩하고, 만료 시 리프레시 토큰으로 자동 갱신한다.
- 웹 타겟에서 `flutter_secure_storage`는 WebCrypto 기반 실험적 구현이라는 점을 알려진 제약에 한 줄 추가한다.
- `mobile/` 구조 설명의 `lib/app_session.dart` 항목에 secure storage 복원(`restore()`)을 언급하고, `lib/auth/`에 `token_store.dart`/`secure_token_store.dart`를 추가한다.

- [ ] **Step 4: 커밋**

```bash
git add README.md
git commit -m "docs: document persistent token storage"
```

## Self-Review 결과

- **스펙 커버리지:** 의존성 추가(Task 1 Step 1), `TokenStore`/`SecureTokenStore`(Task 1), `AppSession` 영속화·복원·`isRestoring`(Task 2), `AuthGate` 로딩 + `main` 복원 배선(Task 3), 검증·문서(Task 4) — 스펙 전 항목 커버.
- **플레이스홀더 스캔:** 없음. 모든 코드 스텝에 실제 코드 포함.
- **타입 일관성:** `TokenStore.read()`의 반환 record `({String? accessToken, String? refreshToken})`가 Task 1 정의와 Task 2 소비(`stored.accessToken`/`stored.refreshToken`), 테스트 `FakeTokenStore`에서 일치. `AppSession` 생성자의 `tokenStore` 명명 파라미터(Task 2)가 Task 3의 테스트 및 `main.dart` 배선과 일치. `isRestoring`(Task 2)이 `AuthGate`(Task 3)의 사용처와 일치. best-effort try-catch 규칙(Global Constraints)이 `login`/`_doRefresh`/`logout`/`restore` 전반에 일관 적용.
